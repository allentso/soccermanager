use crate::game::{Game, ScoutingAssignment, YouthScoutingAssignment};
use domain::message::*;
use domain::staff::StaffRole;
use rand::RngExt;
use std::collections::HashMap;
use uuid::Uuid;

fn params(pairs: &[(&str, &str)]) -> HashMap<String, String> {
    pairs
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

/// Determine how many concurrent scouting assignments a scout can handle.
/// Higher judging_ability = more slots (1 to 5).
pub fn scout_max_assignments(judging_ability: u8) -> usize {
    if judging_ability >= 80 {
        5
    } else if judging_ability >= 60 {
        4
    } else if judging_ability >= 40 {
        3
    } else if judging_ability >= 20 {
        2
    } else {
        1
    }
}

fn scout_assignment_count(game: &Game, scout_id: &str) -> usize {
    game.scouting_assignments
        .iter()
        .filter(|assignment| assignment.scout_id == scout_id)
        .count()
        + game
            .youth_scouting_assignments
            .iter()
            .filter(|assignment| assignment.scout_id == scout_id)
            .count()
}

fn resolve_user_scout<'a>(game: &'a Game, scout_id: &str) -> Result<&'a domain::staff::Staff, String> {
    let user_team_id = game.manager.team_id.as_ref().ok_or("No team")?;

    let scout = game
        .staff
        .iter()
        .find(|staff_member| staff_member.id == scout_id)
        .ok_or("Scout not found")?;
    if scout.role != StaffRole::Scout {
        return Err("Staff member is not a scout".to_string());
    }
    if scout.team_id.as_ref() != Some(user_team_id) {
        return Err("Scout does not belong to your team".to_string());
    }

    Ok(scout)
}

fn assignment_days_for_player_scouting(judging_ability: u8) -> u32 {
    if judging_ability >= 80 {
        2
    } else if judging_ability >= 60 {
        3
    } else if judging_ability >= 40 {
        4
    } else {
        5
    }
}

fn assignment_days_for_youth_scouting(judging_potential: u8) -> u32 {
    if judging_potential >= 80 {
        4
    } else if judging_potential >= 60 {
        5
    } else if judging_potential >= 40 {
        6
    } else {
        7
    }
}

/// Send a scout to evaluate a player. Returns an error string if invalid.
pub fn send_scout(game: &mut Game, scout_id: &str, player_id: &str) -> Result<(), String> {
    let user_team_id = game.manager.team_id.as_ref().ok_or("No team")?;
    let scout = resolve_user_scout(game, scout_id)?;

    // Validate player exists and is not on user's team
    let player = game
        .players
        .iter()
        .find(|p| p.id == player_id)
        .ok_or("Player not found")?;
    if player.team_id.as_deref() == Some(user_team_id.as_str()) {
        return Err("Cannot scout your own players".to_string());
    }

    // Check scout capacity: higher ability = more concurrent assignments
    let max_slots = scout_max_assignments(scout.attributes.judging_ability);
    let current_count = scout_assignment_count(game, scout_id);
    if current_count >= max_slots {
        return Err(format!(
            "Scout is at capacity ({}/{} assignments). Higher judging ability allows more.",
            current_count, max_slots
        ));
    }

    // Check if player is already being scouted
    if game
        .scouting_assignments
        .iter()
        .any(|a| a.player_id == player_id)
    {
        return Err("This player is already being scouted".to_string());
    }

    // Create assignment (2-5 days depending on scout quality)
    let days = assignment_days_for_player_scouting(scout.attributes.judging_ability);

    game.scouting_assignments.push(ScoutingAssignment {
        id: Uuid::new_v4().to_string(),
        scout_id: scout_id.to_string(),
        player_id: player_id.to_string(),
        days_remaining: days,
    });

    Ok(())
}

pub fn start_youth_scouting(game: &mut Game, scout_id: &str) -> Result<(), String> {
    let scout = resolve_user_scout(game, scout_id)?;
    let max_slots = scout_max_assignments(scout.attributes.judging_ability);
    let current_count = scout_assignment_count(game, scout_id);
    if current_count >= max_slots {
        return Err(format!(
            "Scout is at capacity ({}/{} assignments). Higher judging ability allows more.",
            current_count, max_slots
        ));
    }

    let days = assignment_days_for_youth_scouting(scout.attributes.judging_potential);
    game.youth_scouting_assignments.push(YouthScoutingAssignment {
        id: Uuid::new_v4().to_string(),
        scout_id: scout_id.to_string(),
        days_remaining: days,
    });

    Ok(())
}

/// Process scouting assignments daily. Called from process_day().
/// Decrements days, delivers reports when complete.
pub fn process_scouting(game: &mut Game) {
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let mut completed: Vec<ScoutingAssignment> = Vec::new();
    let mut completed_youth: Vec<YouthScoutingAssignment> = Vec::new();

    for assignment in game.scouting_assignments.iter_mut() {
        if assignment.days_remaining > 0 {
            assignment.days_remaining -= 1;
        }
        if assignment.days_remaining == 0 {
            completed.push(assignment.clone());
        }
    }

    for assignment in game.youth_scouting_assignments.iter_mut() {
        if assignment.days_remaining > 0 {
            assignment.days_remaining -= 1;
        }
        if assignment.days_remaining == 0 {
            completed_youth.push(assignment.clone());
        }
    }

    // Remove completed assignments
    game.scouting_assignments.retain(|a| a.days_remaining > 0);
    game.youth_scouting_assignments
        .retain(|assignment| assignment.days_remaining > 0);

    // Generate reports for completed assignments
    for assignment in &completed {
        let scout = game.staff.iter().find(|s| s.id == assignment.scout_id);
        let player = game.players.iter().find(|p| p.id == assignment.player_id);

        if let (Some(scout), Some(player)) = (scout, player) {
            let scout_name = format!("{} {}", scout.first_name, scout.last_name);
            let judging_ability = scout.attributes.judging_ability;
            let judging_potential = scout.attributes.judging_potential;
            let team_name = player
                .team_id
                .as_ref()
                .and_then(|tid| game.teams.iter().find(|t| &t.id == tid))
                .map(|t| t.name.clone());

            let msg = build_scout_report(
                &assignment.id,
                &scout_name,
                &player.id,
                &player.match_name,
                &player.nationality,
                &player.date_of_birth,
                &format!("{:?}", player.position),
                &player.attributes,
                player.morale,
                player.condition,
                player.ovr,
                player.potential,
                judging_ability,
                judging_potential,
                team_name.as_deref(),
                &today,
            );
            game.messages.push(msg);
        }
    }

    for assignment in &completed_youth {
        complete_youth_scouting_assignment(game, assignment, &today);
    }
}

fn complete_youth_scouting_assignment(
    game: &mut Game,
    assignment: &YouthScoutingAssignment,
    date: &str,
) {
    let Some(scout) = game
        .staff
        .iter()
        .find(|staff_member| staff_member.id == assignment.scout_id)
        .cloned()
    else {
        return;
    };
    let Some(user_team_id) = game.manager.team_id.clone() else {
        return;
    };
    let Some(team) = game
        .teams
        .iter()
        .find(|candidate| candidate.id == user_team_id)
        .cloned()
    else {
        return;
    };

    let recruit = crate::generator::generate_youth_academy_recruit(&team);
    let recruit_id = recruit.id.clone();
    let recruit_name = recruit.full_name.clone();
    let recruit_position = format!("{:?}", recruit.position);
    game.players.push(recruit);

    let scout_name = format!("{} {}", scout.first_name, scout.last_name);
    game.messages.push(build_youth_recruitment_report(
        &assignment.id,
        &scout_name,
        &team.id,
        &team.name,
        &recruit_id,
        &recruit_name,
        &recruit_position,
        date,
    ));
}

fn build_youth_recruitment_report(
    assignment_id: &str,
    scout_name: &str,
    team_id: &str,
    team_name: &str,
    player_id: &str,
    player_name: &str,
    position: &str,
    date: &str,
) -> InboxMessage {
    InboxMessage::new(
        format!("youth-scout-{}", assignment_id),
        "Youth prospect found".to_string(),
        format!(
            "{} has signed {} to the {} academy as a {} prospect.",
            scout_name, player_name, team_name, position
        ),
        scout_name.to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::ScoutReport)
    .with_sender_role("Scout")
    .with_action(MessageAction {
        id: "view_player".to_string(),
        label: "View profile".to_string(),
        action_type: ActionType::NavigateTo {
            route: format!("/player/{}", player_id),
        },
        resolved: false,
        label_key: Some("squad.viewProfile".to_string()),
    })
    .with_action(MessageAction {
        id: "ack".to_string(),
        label: "Noted".to_string(),
        action_type: ActionType::Acknowledge,
        resolved: false,
        label_key: Some("be.msg.event.ack".to_string()),
    })
    .with_context(MessageContext {
        team_id: Some(team_id.to_string()),
        player_id: Some(player_id.to_string()),
        ..MessageContext::default()
    })
}

fn build_scout_report(
    assignment_id: &str,
    scout_name: &str,
    player_id: &str,
    player_name: &str,
    nationality: &str,
    dob: &str,
    position: &str,
    attrs: &domain::player::PlayerAttributes,
    morale: u8,
    condition: u8,
    player_ovr: u8,
    player_potential: u8,
    judging_ability: u8,
    judging_potential: u8,
    team_name: Option<&str>,
    date: &str,
) -> InboxMessage {
    let mut rng = rand::rng();

    // Accuracy: higher judging = less noise on reported attributes
    let noise_range = if judging_ability >= 80 {
        2
    } else if judging_ability >= 60 {
        5
    } else if judging_ability >= 40 {
        8
    } else {
        12
    };

    let mut fuzz = |val: u8| -> u8 {
        let delta: i16 = rng.random_range(-(noise_range as i16)..=(noise_range as i16));
        ((val as i16) + delta).clamp(1, 99) as u8
    };

    // Build fuzzed attribute values
    let all_fuzzed: [(u8, &str); 6] = [
        (fuzz(attrs.pace), "Pace"),
        (fuzz(attrs.shooting), "Shooting"),
        (fuzz(attrs.passing), "Passing"),
        (fuzz(attrs.dribbling), "Dribbling"),
        (fuzz(attrs.defending), "Defending"),
        (fuzz(attrs.strength), "Physical"),
    ];

    // Discovery mechanic: scout ability determines how many attrs are revealed
    // 80+: all 6 attrs + condition + morale
    // 60-79: 5 attrs + condition
    // 40-59: 3 attrs
    // <40: 2 attrs
    let reveal_count: usize = if judging_ability >= 80 {
        6
    } else if judging_ability >= 60 {
        5
    } else if judging_ability >= 40 {
        3
    } else {
        2
    };

    // Shuffle indices to determine which attrs are hidden
    let mut indices: Vec<usize> = (0..6).collect();
    for i in (1..indices.len()).rev() {
        let j = rng.random_range(0..=i);
        indices.swap(i, j);
    }
    let revealed: std::collections::HashSet<usize> =
        indices[..reveal_count].iter().cloned().collect();

    let to_opt = |idx: usize| -> Option<u8> {
        if revealed.contains(&idx) {
            Some(all_fuzzed[idx].0)
        } else {
            None
        }
    };

    let pace = to_opt(0);
    let shooting = to_opt(1);
    let passing = to_opt(2);
    let dribbling = to_opt(3);
    let defending = to_opt(4);
    let physical = to_opt(5);

    let reported_condition = if judging_ability >= 60 {
        Some(condition)
    } else {
        None
    };
    let reported_morale = if judging_ability >= 80 {
        Some(morale)
    } else {
        None
    };

    // Overall rating assessment based on the player's position-weighted OVR (fuzzed by scout ability).
    // Fall back to attribute average if OVR is unavailable (legacy players).
    let rating_base = if player_ovr > 0 {
        let delta: i16 = rng.random_range(-(noise_range as i16)..=(noise_range as i16));
        ((player_ovr as i16) + delta).clamp(1, 99) as u32
    } else {
        let revealed_vals: Vec<u32> =
            (0..6).filter_map(|i| to_opt(i).map(|v| v as u32)).collect();
        if revealed_vals.is_empty() {
            0
        } else {
            revealed_vals.iter().sum::<u32>() / revealed_vals.len() as u32
        }
    };

    let rating_key = if rating_base >= 80 {
        "common.scoutRatings.excellent"
    } else if rating_base >= 70 {
        "common.scoutRatings.veryGood"
    } else if rating_base >= 60 {
        "common.scoutRatings.good"
    } else if rating_base >= 50 {
        "common.scoutRatings.average"
    } else {
        "common.scoutRatings.belowAverage"
    };

    // Potential assessment: use the player's actual potential (fuzzed) when the scout
    // has sufficient judging_potential skill.  High-potential scouts can also spot
    // Wonderkid-level talent accurately.
    let potential_key = if judging_potential >= 70 {
        let fuzzed_potential = if player_potential > 0 {
            let delta: i16 = rng.random_range(-(noise_range as i16)..=(noise_range as i16));
            ((player_potential as i16) + delta).clamp(1, 99) as u32
        } else {
            rating_base // fallback to fuzzed OVR if no potential stored
        };
        if fuzzed_potential >= 85 {
            "common.scoutPotential.worldClass"
        } else if fuzzed_potential >= 70 {
            "common.scoutPotential.strong"
        } else {
            "common.scoutPotential.moderate"
        }
    } else {
        "common.scoutPotential.unclear"
    };

    // Confidence level
    let confidence_key = if judging_ability >= 80 {
        "common.scoutConfidence.high"
    } else if judging_ability >= 60 {
        "common.scoutConfidence.moderate"
    } else {
        "common.scoutConfidence.low"
    };

    // Build structured report data for the player card
    let report_data = ScoutReportData {
        player_id: player_id.to_string(),
        player_name: player_name.to_string(),
        position: position.to_string(),
        nationality: nationality.to_string(),
        dob: dob.to_string(),
        team_name: team_name.map(|s| s.to_string()),
        pace,
        shooting,
        passing,
        dribbling,
        defending,
        physical,
        condition: reported_condition,
        morale: reported_morale,
        avg_rating: Some(rating_base),
        rating_key: rating_key.to_string(),
        potential_key: potential_key.to_string(),
        confidence_key: confidence_key.to_string(),
    };

    // Fallback body text (used when i18n key is not found)
    let body = format!(
        "Scout report on {} completed by {}.",
        player_name, scout_name
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
        scout_report: Some(report_data),
        ..Default::default()
    })
    .with_i18n("be.msg.scoutReport.subject", "be.msg.scoutReport.body", {
        let mut p = params(&[("player", player_name), ("scout", scout_name)]);
        p.insert("ratingDesc".to_string(), rating_key.to_string());
        p.insert("potentialDesc".to_string(), potential_key.to_string());
        p.insert("confidence".to_string(), confidence_key.to_string());
        p
    })
    .with_sender_i18n("be.sender.scout", "be.role.scout")
}
