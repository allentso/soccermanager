mod message_builders;
mod responses;

pub use responses::apply_player_response;

use crate::game::Game;
use domain::message::InboxMessage;
use rand::Rng;

use message_builders::{
    bench_complaint_message, contract_concern_message, happy_player_message, low_morale_message,
};

/// Check all player-related events and generate inbox messages.
/// Called once per day from process_day().
pub fn check_player_events(game: &mut Game) {
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let user_team_id = match game.manager.team_id.clone() {
        Some(id) => id,
        None => return,
    };

    // Collect existing message IDs for deduplication
    let existing_ids: std::collections::HashSet<String> =
        game.messages.iter().map(|m| m.id.clone()).collect();

    let mut new_messages: Vec<InboxMessage> = Vec::new();

    // --- 1. Low morale meeting requests (morale < 30) ---
    for player in game.players.iter() {
        if player.team_id.as_deref() != Some(&user_team_id) {
            continue;
        }
        if player.injury.is_some() {
            continue;
        }

        let msg_id = format!("morale_talk_{}", player.id);
        if existing_ids.contains(&msg_id) {
            continue;
        }

        if player.morale < 30 {
            new_messages.push(low_morale_message(
                &msg_id,
                &player.id,
                &player.match_name,
                player.morale,
                &today,
            ));
        }
    }

    // --- 2. Benched player complaints ---
    // Count recent matches where user's team played, then check which players
    // didn't appear in any of the last 3 completed fixtures
    if let Some(league) = &game.league {
        let completed: Vec<&domain::league::Fixture> = league
            .fixtures
            .iter()
            .filter(|f| {
                f.status == domain::league::FixtureStatus::Completed
                    && (f.home_team_id == user_team_id || f.away_team_id == user_team_id)
            })
            .collect();

        let recent_count = completed.len().min(3);
        if recent_count >= 3 {
            let recent = &completed[completed.len() - 3..];

            // Collect player IDs who appeared in any of the last 3 matches
            // We use the player_stats from match results which contain player IDs
            let mut appeared: std::collections::HashSet<String> = std::collections::HashSet::new();
            for fixture in recent {
                if let Some(result) = &fixture.result {
                    for scorer in &result.home_scorers {
                        appeared.insert(scorer.player_id.clone());
                    }
                    for scorer in &result.away_scorers {
                        appeared.insert(scorer.player_id.clone());
                    }
                }
            }

            // Any non-GK, non-injured player with decent OVR who hasn't appeared
            for player in game.players.iter() {
                if player.team_id.as_deref() != Some(&user_team_id) {
                    continue;
                }
                if player.injury.is_some() {
                    continue;
                }
                if player.position == domain::player::Position::Goalkeeper {
                    continue;
                }

                let msg_id = format!("bench_complaint_{}", player.id);
                if existing_ids.contains(&msg_id) {
                    continue;
                }

                // Only complain if they have decent attributes (OVR >= 55) and morale is already dropping
                let attrs = &player.attributes;
                let ovr = (attrs.pace as u16
                    + attrs.stamina as u16
                    + attrs.strength as u16
                    + attrs.passing as u16
                    + attrs.shooting as u16
                    + attrs.tackling as u16
                    + attrs.dribbling as u16
                    + attrs.defending as u16
                    + attrs.positioning as u16
                    + attrs.vision as u16
                    + attrs.decisions as u16)
                    / 11;

                if ovr >= 55 && player.morale < 60 && !appeared.contains(&player.id) {
                    new_messages.push(bench_complaint_message(
                        &msg_id,
                        &player.id,
                        &player.match_name,
                        &today,
                    ));
                }
            }
        }
    }

    // --- 3. Happy player / high morale praise ---
    {
        let mut rng = rand::thread_rng();
        for player in game.players.iter() {
            if player.team_id.as_deref() != Some(&user_team_id) {
                continue;
            }

            let msg_id = format!("happy_player_{}", player.id);
            if existing_ids.contains(&msg_id) {
                continue;
            }

            // High morale player occasionally sends positive message (10% chance per day)
            if player.morale >= 90 && rng.gen_range(0..10) == 0 {
                new_messages.push(happy_player_message(
                    &msg_id,
                    &player.id,
                    &player.match_name,
                    &today,
                ));
            }
        }
    }

    // --- 4. Contract concern (< 90 days remaining) ---
    {
        let current_date = game.clock.current_date.date_naive();
        for player in game.players.iter() {
            if player.team_id.as_deref() != Some(&user_team_id) {
                continue;
            }

            let msg_id = format!("contract_concern_{}", player.id);
            if existing_ids.contains(&msg_id) {
                continue;
            }

            if let Some(end_str) = &player.contract_end
                && let Ok(end_date) = chrono::NaiveDate::parse_from_str(end_str, "%Y-%m-%d")
            {
                let days_remaining = (end_date - current_date).num_days();
                if days_remaining > 0 && days_remaining <= 90 {
                    new_messages.push(contract_concern_message(
                        &msg_id,
                        &player.id,
                        &player.match_name,
                        days_remaining,
                        &today,
                    ));
                }
            }
        }
    }

    game.messages.extend(new_messages);
}
