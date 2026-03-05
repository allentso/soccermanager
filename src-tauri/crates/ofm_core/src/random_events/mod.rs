mod builders_reports;
mod message_builders;
mod responses;

pub use responses::apply_event_response;

use crate::game::Game;
use domain::message::*;
use rand::Rng;
use std::collections::HashMap;

fn params(pairs: &[(&str, &str)]) -> HashMap<String, String> {
    pairs
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

fn action(id: &str, label: &str, label_key: &str, action_type: ActionType) -> MessageAction {
    MessageAction {
        id: id.to_string(),
        label: label.to_string(),
        action_type,
        resolved: false,
        label_key: Some(label_key.to_string()),
    }
}

/// Generate random daily events. Called from process_day().
/// Events have low probability each day so they don't spam the player.
pub fn check_random_events(game: &mut Game) {
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let user_team_id = match game.manager.team_id.clone() {
        Some(id) => id,
        None => return,
    };

    let existing_ids: std::collections::HashSet<String> =
        game.messages.iter().map(|m| m.id.clone()).collect();

    let mut rng = rand::thread_rng();
    let mut new_messages: Vec<InboxMessage> = Vec::new();

    // --- 1. Sponsor offer (1% chance per day) ---
    {
        let msg_id = format!("sponsor_{}", today);
        if !existing_ids.contains(&msg_id) && rng.gen_range(0..100) == 0 {
            let team_name = game
                .teams
                .iter()
                .find(|t| t.id == user_team_id)
                .map(|t| t.name.as_str())
                .unwrap_or("Your Club");
            let amount = rng.gen_range(5..=30) * 10_000; // 50k - 300k
            let sponsor_names = [
                "GreenTech Industries",
                "Nova Sports",
                "Titan Energy",
                "BlueWave Solutions",
                "Summit Capital",
                "Apex Motors",
                "FreshBrew Co.",
                "CityLink Telecom",
            ];
            let sponsor = sponsor_names[rng.gen_range(0..sponsor_names.len())];

            new_messages.push(message_builders::sponsor_offer_message(
                &msg_id, team_name, sponsor, amount, &today,
            ));
        }
    }

    // --- 2. Training ground injury (2% chance per day, non-match days) ---
    {
        let has_match = game.league.as_ref().is_some_and(|l| {
            l.fixtures
                .iter()
                .any(|f| f.date == today && f.status == domain::league::FixtureStatus::Scheduled)
        });
        if !has_match && rng.gen_range(0..50) == 0 {
            // Pick a random non-injured player
            let eligible: Vec<&domain::player::Player> = game
                .players
                .iter()
                .filter(|p| p.team_id.as_deref() == Some(&user_team_id) && p.injury.is_none())
                .collect();
            if !eligible.is_empty() {
                let player = eligible[rng.gen_range(0..eligible.len())];
                let msg_id = format!("training_injury_{}_{}", player.id, today);
                if !existing_ids.contains(&msg_id) {
                    let days = rng.gen_range(3..=14);
                    let injury_names = [
                        "Minor muscle strain",
                        "Twisted ankle",
                        "Knee bruise",
                        "Hamstring tightness",
                        "Calf strain",
                    ];
                    let injury_name = injury_names[rng.gen_range(0..injury_names.len())];

                    new_messages.push(message_builders::training_injury_message(
                        &msg_id,
                        &player.id,
                        &player.match_name,
                        injury_name,
                        days,
                        &today,
                    ));

                    // Apply the injury
                    let pid = player.id.clone();
                    if let Some(p) = game.players.iter_mut().find(|p| p.id == pid) {
                        p.injury = Some(domain::player::Injury {
                            name: injury_name.to_string(),
                            days_remaining: days,
                        });
                    }
                }
            }
        }
    }

    // --- 3. Media story (3% chance per day) ---
    {
        let msg_id = format!("media_{}", today);
        if !existing_ids.contains(&msg_id) && rng.gen_range(0..33) == 0 {
            let team_name = game
                .teams
                .iter()
                .find(|t| t.id == user_team_id)
                .map(|t| t.name.as_str())
                .unwrap_or("Your Club");

            // Pick a random player for the story
            let team_players: Vec<&domain::player::Player> = game
                .players
                .iter()
                .filter(|p| p.team_id.as_deref() == Some(&user_team_id))
                .collect();
            if !team_players.is_empty() {
                let player = team_players[rng.gen_range(0..team_players.len())];
                let is_positive = rng.gen_bool(0.6); // 60% positive stories

                new_messages.push(message_builders::media_story_message(
                    &msg_id,
                    team_name,
                    &player.id,
                    &player.match_name,
                    is_positive,
                    &today,
                ));

                // Apply morale effect
                let pid = player.id.clone();
                if let Some(p) = game.players.iter_mut().find(|p| p.id == pid) {
                    let delta: i16 = if is_positive {
                        rng.gen_range(2..=5)
                    } else {
                        rng.gen_range(-5..=-1)
                    };
                    p.morale = ((p.morale as i16) + delta).clamp(10, 100) as u8;
                }
            }
        }
    }

    // --- 4. International call-up (5% chance per day, only if match in next 7 days) ---
    {
        let upcoming_match = game.league.as_ref().and_then(|l| {
            let current = game.clock.current_date;
            l.fixtures.iter().find(|f| {
                f.status == domain::league::FixtureStatus::Scheduled
                    && (f.home_team_id == user_team_id || f.away_team_id == user_team_id)
                    && {
                        if let Ok(d) = chrono::NaiveDate::parse_from_str(&f.date, "%Y-%m-%d") {
                            let diff = (d - current.date_naive()).num_days();
                            (1..=7).contains(&diff)
                        } else {
                            false
                        }
                    }
            })
        });

        if upcoming_match.is_some() && rng.gen_range(0..20) == 0 {
            let eligible: Vec<&domain::player::Player> = game
                .players
                .iter()
                .filter(|p| p.team_id.as_deref() == Some(&user_team_id) && p.injury.is_none())
                .collect();
            if !eligible.is_empty() {
                let player = eligible[rng.gen_range(0..eligible.len())];
                let msg_id = format!("intl_callup_{}_{}", player.id, today);
                if !existing_ids.contains(&msg_id) {
                    new_messages.push(message_builders::international_callup_message(
                        &msg_id,
                        &player.match_name,
                        &player.nationality,
                        &today,
                    ));
                    // Morale boost for being called up
                    let pid = player.id.clone();
                    if let Some(p) = game.players.iter_mut().find(|p| p.id == pid) {
                        p.morale = (p.morale as i16 + rng.gen_range(3..=8)).clamp(10, 100) as u8;
                    }
                }
            }
        }
    }

    // --- 5. Community event / club milestone (1% chance per day) ---
    {
        let msg_id = format!("community_{}", today);
        if !existing_ids.contains(&msg_id) && rng.gen_range(0..100) == 0 {
            let team_name = game
                .teams
                .iter()
                .find(|t| t.id == user_team_id)
                .map(|t| t.name.as_str())
                .unwrap_or("Your Club");
            new_messages.push(message_builders::community_event_message(
                &msg_id, team_name, &today,
            ));
        }
    }

    // --- 6. Dressing room mood report (weekly, ~14% chance per day = roughly once a week) ---
    {
        let msg_id = format!("mood_report_{}", today);
        if !existing_ids.contains(&msg_id) && rng.gen_range(0..7) == 0 {
            let team_players: Vec<&domain::player::Player> = game
                .players
                .iter()
                .filter(|p| p.team_id.as_deref() == Some(&user_team_id))
                .collect();
            if !team_players.is_empty() {
                let avg_morale: f64 = team_players.iter().map(|p| p.morale as f64).sum::<f64>()
                    / team_players.len() as f64;
                let low_morale_count = team_players.iter().filter(|p| p.morale < 40).count();
                let high_morale_count = team_players.iter().filter(|p| p.morale >= 80).count();

                new_messages.push(builders_reports::mood_report_message(
                    &msg_id,
                    avg_morale,
                    low_morale_count,
                    high_morale_count,
                    team_players.len(),
                    &today,
                ));
            }
        }
    }

    // --- 7. Board confidence check (after 3+ consecutive losses, 100% trigger once) ---
    {
        if let Some(league) = &game.league {
            let completed: Vec<_> = league
                .fixtures
                .iter()
                .filter(|f| {
                    f.status == domain::league::FixtureStatus::Completed
                        && (f.home_team_id == user_team_id || f.away_team_id == user_team_id)
                })
                .collect();
            if completed.len() >= 3 {
                let last3 = &completed[completed.len() - 3..];
                let losses = last3
                    .iter()
                    .filter(|f| {
                        if let Some(r) = &f.result {
                            let user_goals = if f.home_team_id == user_team_id {
                                r.home_goals
                            } else {
                                r.away_goals
                            };
                            let opp_goals = if f.home_team_id == user_team_id {
                                r.away_goals
                            } else {
                                r.home_goals
                            };
                            user_goals < opp_goals
                        } else {
                            false
                        }
                    })
                    .count();
                let msg_id = format!("board_confidence_{}", today);
                if losses >= 3 && !existing_ids.contains(&msg_id) {
                    new_messages.push(builders_reports::board_confidence_message(&msg_id, &today));
                }
            }
        }
    }

    // --- 8. Fan petition (2% chance per day) ---
    {
        let msg_id = format!("fan_petition_{}", today);
        if !existing_ids.contains(&msg_id) && rng.gen_range(0..50) == 0 {
            let team_name = game
                .teams
                .iter()
                .find(|t| t.id == user_team_id)
                .map(|t| t.name.as_str())
                .unwrap_or("Your Club");
            new_messages.push(builders_reports::fan_petition_message(
                &msg_id, team_name, &today,
            ));
        }
    }

    // --- 9. Rival interest in player (2% chance per day) ---
    {
        let msg_id = format!("rival_interest_{}", today);
        if !existing_ids.contains(&msg_id) && rng.gen_range(0..50) == 0 {
            let eligible: Vec<&domain::player::Player> = game
                .players
                .iter()
                .filter(|p| p.team_id.as_deref() == Some(&user_team_id) && p.injury.is_none())
                .collect();
            if !eligible.is_empty() {
                let player = eligible[rng.gen_range(0..eligible.len())];
                let rival_names = [
                    "FC Rival",
                    "Sporting Ambition",
                    "United Prestige",
                    "Real Progress",
                    "Bayern Elite",
                ];
                let rival = rival_names[rng.gen_range(0..rival_names.len())];
                new_messages.push(builders_reports::rival_interest_message(
                    &msg_id,
                    &player.id,
                    &player.match_name,
                    rival,
                    &today,
                ));
            }
        }
    }

    game.messages.extend(new_messages);
}

fn format_money(amount: u64) -> String {
    if amount >= 1_000_000 {
        format!("{:.1}M", amount as f64 / 1_000_000.0)
    } else if amount >= 1_000 {
        format!("{}K", amount / 1_000)
    } else {
        amount.to_string()
    }
}
