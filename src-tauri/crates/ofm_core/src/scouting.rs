use crate::game::{Game, ScoutingAssignment};
use domain::message::*;
use domain::staff::StaffRole;
use rand::Rng;
use std::collections::HashMap;
use uuid::Uuid;

fn params(pairs: &[(&str, &str)]) -> HashMap<String, String> {
    pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
}

/// Send a scout to evaluate a player. Returns an error string if invalid.
pub fn send_scout(game: &mut Game, scout_id: &str, player_id: &str) -> Result<(), String> {
    let user_team_id = game.manager.team_id.as_ref().ok_or("No team")?;

    // Validate scout exists and belongs to user's team
    let scout = game.staff.iter().find(|s| s.id == scout_id)
        .ok_or("Scout not found")?;
    if scout.role != StaffRole::Scout {
        return Err("Staff member is not a scout".to_string());
    }
    if scout.team_id.as_ref() != Some(user_team_id) {
        return Err("Scout does not belong to your team".to_string());
    }

    // Validate player exists and is not on user's team
    let player = game.players.iter().find(|p| p.id == player_id)
        .ok_or("Player not found")?;
    if player.team_id.as_deref() == Some(user_team_id.as_str()) {
        return Err("Cannot scout your own players".to_string());
    }

    // Check if scout is already on assignment
    if game.scouting_assignments.iter().any(|a| a.scout_id == scout_id) {
        return Err("Scout is already on an assignment".to_string());
    }

    // Check if player is already being scouted
    if game.scouting_assignments.iter().any(|a| a.player_id == player_id) {
        return Err("This player is already being scouted".to_string());
    }

    // Create assignment (2-5 days depending on scout quality)
    let judging = scout.attributes.judging_ability as u32;
    let days = if judging >= 80 { 2 } else if judging >= 60 { 3 } else if judging >= 40 { 4 } else { 5 };

    game.scouting_assignments.push(ScoutingAssignment {
        id: Uuid::new_v4().to_string(),
        scout_id: scout_id.to_string(),
        player_id: player_id.to_string(),
        days_remaining: days,
    });

    Ok(())
}

/// Process scouting assignments daily. Called from process_day().
/// Decrements days, delivers reports when complete.
pub fn process_scouting(game: &mut Game) {
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let mut completed: Vec<ScoutingAssignment> = Vec::new();

    for assignment in game.scouting_assignments.iter_mut() {
        if assignment.days_remaining > 0 {
            assignment.days_remaining -= 1;
        }
        if assignment.days_remaining == 0 {
            completed.push(assignment.clone());
        }
    }

    // Remove completed assignments
    game.scouting_assignments.retain(|a| a.days_remaining > 0);

    // Generate reports for completed assignments
    for assignment in &completed {
        let scout = game.staff.iter().find(|s| s.id == assignment.scout_id);
        let player = game.players.iter().find(|p| p.id == assignment.player_id);

        if let (Some(scout), Some(player)) = (scout, player) {
            let scout_name = format!("{} {}", scout.first_name, scout.last_name);
            let judging_ability = scout.attributes.judging_ability;
            let judging_potential = scout.attributes.judging_potential;

            let msg = build_scout_report(
                &assignment.id,
                &scout_name,
                &player.id,
                &player.match_name,
                &player.full_name,
                &player.nationality,
                &player.date_of_birth,
                &format!("{:?}", player.position),
                &player.attributes,
                player.morale,
                player.condition,
                judging_ability,
                judging_potential,
                &today,
            );
            game.messages.push(msg);
        }
    }
}

fn build_scout_report(
    assignment_id: &str,
    scout_name: &str,
    player_id: &str,
    player_name: &str,
    player_full_name: &str,
    nationality: &str,
    dob: &str,
    position: &str,
    attrs: &domain::player::PlayerAttributes,
    morale: u8,
    condition: u8,
    judging_ability: u8,
    judging_potential: u8,
    date: &str,
) -> InboxMessage {
    let mut rng = rand::thread_rng();

    // Accuracy: higher judging = less noise on reported attributes
    let noise_range = if judging_ability >= 80 { 2 }
        else if judging_ability >= 60 { 5 }
        else if judging_ability >= 40 { 8 }
        else { 12 };

    let mut fuzz = |val: u8| -> u8 {
        let delta: i16 = rng.gen_range(-(noise_range as i16)..=(noise_range as i16));
        ((val as i16) + delta).clamp(1, 99) as u8
    };

    // Build attribute report with fuzzed values
    let reported_pace = fuzz(attrs.pace);
    let reported_shooting = fuzz(attrs.shooting);
    let reported_passing = fuzz(attrs.passing);
    let reported_dribbling = fuzz(attrs.dribbling);
    let reported_defending = fuzz(attrs.defending);
    let reported_physical = fuzz(attrs.strength);

    // Overall assessment
    let avg_attrs = (reported_pace as u32 + reported_shooting as u32 + reported_passing as u32
        + reported_dribbling as u32 + reported_defending as u32 + reported_physical as u32) / 6;

    let rating_desc = if avg_attrs >= 80 { "Excellent" }
        else if avg_attrs >= 70 { "Very Good" }
        else if avg_attrs >= 60 { "Good" }
        else if avg_attrs >= 50 { "Average" }
        else { "Below Average" };

    // Potential assessment (based on judging_potential accuracy)
    let potential_desc = if judging_potential >= 70 {
        if avg_attrs >= 75 { "World class potential" }
        else if avg_attrs >= 60 { "Strong development potential" }
        else { "Moderate potential for growth" }
    } else {
        "Potential unclear — further scouting recommended"
    };

    // Confidence level
    let confidence = if judging_ability >= 80 { "High" }
        else if judging_ability >= 60 { "Moderate" }
        else { "Low" };

    let body = format!(
        "Scout Report — {}\n\n\
        Player: {} ({})\n\
        Position: {} | Nationality: {} | DOB: {}\n\
        Current Condition: {}% | Morale: {}/100\n\n\
        --- Key Attributes (estimated) ---\n\
        • Pace: {}\n\
        • Shooting: {}\n\
        • Passing: {}\n\
        • Dribbling: {}\n\
        • Defending: {}\n\
        • Physical: {}\n\n\
        Overall Assessment: {} (avg ~{})\n\
        Development: {}\n\
        Report Confidence: {}\n\n\
        — {}, Scout",
        player_name,
        player_full_name, player_name,
        position, nationality, dob,
        condition, morale,
        reported_pace, reported_shooting, reported_passing,
        reported_dribbling, reported_defending, reported_physical,
        rating_desc, avg_attrs,
        potential_desc,
        confidence,
        scout_name,
    );

    let msg_id = format!("scout_report_{}", assignment_id);

    InboxMessage::new(
        msg_id,
        format!("Scout Report — {}", player_name),
        body,
        scout_name.to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::ScoutReport)
    .with_priority(MessagePriority::Normal)
    .with_sender_role("Scout")
    .with_action(MessageAction {
        id: "ack".to_string(),
        label: "Noted".to_string(),
        action_type: ActionType::Acknowledge,
        resolved: false,
        label_key: Some("be.msg.event.ack".to_string()),
    })
    .with_context(MessageContext {
        player_id: Some(player_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        "be.msg.scoutReport.subject",
        "be.msg.scoutReport.body",
        params(&[("player", player_name), ("scout", scout_name)]),
    )
    .with_sender_i18n("be.sender.scout", "be.role.scout")
}
