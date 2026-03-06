use log::info;
use tauri::State;

use ofm_core::game::Game;
use ofm_core::live_match_manager::{self, MatchMode};
use ofm_core::state::StateManager;

fn user_team_context<'a>(
    game: &'a Game,
) -> Option<(&'a domain::team::Team, Vec<&'a domain::player::Player>)> {
    let user_team_id = game.manager.team_id.as_deref()?;
    let team = game.teams.iter().find(|team| team.id == user_team_id)?;
    let roster = game
        .players
        .iter()
        .filter(|player| player.team_id.as_deref() == Some(user_team_id))
        .collect();

    Some((team, roster))
}

fn build_blocker(id: &str, severity: &str, text: String, tab: &str) -> serde_json::Value {
    serde_json::json!({
        "id": id,
        "severity": severity,
        "text": text,
        "tab": tab
    })
}

fn injured_starting_xi_blocker(
    xi_ids: &[String],
    roster: &[&domain::player::Player],
) -> Option<serde_json::Value> {
    let injured_in_xi: Vec<_> = xi_ids
        .iter()
        .filter_map(|id| {
            roster
                .iter()
                .find(|player| player.id == *id && player.injury.is_some())
        })
        .map(|player| player.match_name.clone())
        .collect();

    (!injured_in_xi.is_empty()).then(|| {
        build_blocker(
            "injured_xi",
            "warn",
            format!(
                "{} injured player(s) in Starting XI: {}",
                injured_in_xi.len(),
                injured_in_xi.join(", ")
            ),
            "Squad",
        )
    })
}

fn incomplete_starting_xi_blocker(
    xi_ids: &[String],
    roster: &[&domain::player::Player],
) -> Option<serde_json::Value> {
    let healthy_xi = xi_ids
        .iter()
        .filter(|id| {
            roster
                .iter()
                .any(|player| player.id == **id && player.injury.is_none())
        })
        .count();

    (healthy_xi < 11 && roster.len() >= 11).then(|| {
        build_blocker(
            "incomplete_xi",
            "warn",
            format!(
                "Starting XI has only {} healthy players — set your lineup",
                healthy_xi
            ),
            "Squad",
        )
    })
}

fn urgent_unread_messages_blocker(game: &Game) -> Option<serde_json::Value> {
    let urgent_unread = game
        .messages
        .iter()
        .filter(|message| {
            !message.read && message.priority == domain::message::MessagePriority::Urgent
        })
        .count();

    (urgent_unread > 0).then(|| {
        build_blocker(
            "urgent_messages",
            "info",
            format!("{} urgent unread message(s)", urgent_unread),
            "Inbox",
        )
    })
}

#[tauri::command]
pub fn advance_time(state: State<'_, StateManager>) -> Result<Game, String> {
    let mut current_game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    info!(
        "[cmd] advance_time: date={}",
        current_game.clock.current_date.format("%Y-%m-%d")
    );
    // Process a full day: matchday simulation, training, messages, then advance clock
    ofm_core::turn::process_day(&mut current_game);

    state.set_game(current_game.clone());
    Ok(current_game)
}

/// Compute blocking actions for the current game state.
pub fn compute_blocking_actions(game: &Game) -> Vec<serde_json::Value> {
    let mut blockers = Vec::new();
    let (team, roster) = match user_team_context(game) {
        Some(context) => context,
        None => return blockers,
    };
    let xi_ids = &team.starting_xi_ids;

    // Check for injured players in XI
    if let Some(blocker) = injured_starting_xi_blocker(xi_ids, &roster) {
        blockers.push(blocker);
    }

    // Check if XI is incomplete (fewer than 11 healthy players)
    if let Some(blocker) = incomplete_starting_xi_blocker(xi_ids, &roster) {
        blockers.push(blocker);
    }

    // Check for unresolved urgent messages
    if let Some(blocker) = urgent_unread_messages_blocker(game) {
        blockers.push(blocker);
    }

    blockers
}

/// Check for blocking actions that should be resolved before advancing.
/// Returns a JSON array of blocking issues.
#[tauri::command]
pub fn check_blocking_actions(state: State<'_, StateManager>) -> Result<serde_json::Value, String> {
    log::debug!("[cmd] check_blocking_actions");
    let game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let blockers = compute_blocking_actions(&game);
    Ok(serde_json::json!(blockers))
}

/// Skip forward until the day before the next match for the user's team.
/// Processes each intermediate day normally (training, recovery, messages).
/// If blocking actions arise mid-skip, stops early and returns a "blocked" reason.
#[tauri::command]
pub fn skip_to_match_day(state: State<'_, StateManager>) -> Result<serde_json::Value, String> {
    info!("[cmd] skip_to_match_day");
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let user_team_id = game.manager.team_id.clone().ok_or("No team assigned")?;

    // Advance up to 60 days (safety limit)
    let mut days_skipped = 0u32;
    loop {
        if days_skipped >= 60 {
            break;
        }

        let today = game.clock.current_date.format("%Y-%m-%d").to_string();

        // Check if user has a match today
        let has_match = game.league.as_ref().is_some_and(|league| {
            league.fixtures.iter().any(|f| {
                f.date == today
                    && f.status == domain::league::FixtureStatus::Scheduled
                    && (f.home_team_id == user_team_id || f.away_team_id == user_team_id)
            })
        });

        if has_match {
            // We've reached match day — stop here (don't process the match)
            break;
        }

        // Process this non-match day normally
        ofm_core::turn::process_day(&mut game);
        days_skipped += 1;

        // After processing, check if blocking actions arose
        let blockers = compute_blocking_actions(&game);
        if !blockers.is_empty() {
            state.set_game(game.clone());
            return Ok(serde_json::json!({
                "action": "blocked",
                "game": game,
                "blockers": blockers,
                "days_skipped": days_skipped
            }));
        }
    }

    info!(
        "[cmd] skip_to_match_day: arrived after {} days",
        days_skipped
    );
    state.set_game(game.clone());
    Ok(serde_json::json!({
        "action": "arrived",
        "game": game,
        "days_skipped": days_skipped
    }))
}

/// Advance time with a specific match mode.
/// mode: "live" | "spectator" | "delegate" | "instant"
/// If mode is "live" or "spectator" and there's a user match today,
/// it sets up the live match session instead of auto-simulating.
#[tauri::command]
pub fn advance_time_with_mode(
    state: State<'_, StateManager>,
    mode: String,
) -> Result<serde_json::Value, String> {
    info!("[cmd] advance_time_with_mode: mode={}", mode);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let user_team_id = game.manager.team_id.clone();

    // Check if user has a match today
    let user_fixture_idx = user_team_id.as_ref().and_then(|utid| {
        game.league.as_ref().and_then(|league| {
            league.fixtures.iter().enumerate().find_map(|(i, f)| {
                if f.date == today
                    && f.status == domain::league::FixtureStatus::Scheduled
                    && (f.home_team_id == *utid || f.away_team_id == *utid)
                {
                    Some(i)
                } else {
                    None
                }
            })
        })
    });

    match (mode.as_str(), user_fixture_idx) {
        ("live" | "spectator", Some(idx)) => {
            // Set up live match — don't advance the day yet
            let match_mode = if mode == "live" {
                MatchMode::Live
            } else {
                MatchMode::Spectator
            };
            let session = live_match_manager::create_live_match(&game, idx, match_mode, false)?;
            let snapshot = session.snapshot();
            state.set_live_match(session);

            // Simulate all OTHER matches for today instantly
            ofm_core::turn::simulate_other_matches(&mut game, &today, Some(idx));
            state.set_game(game);

            Ok(serde_json::json!({
                "action": "live_match",
                "fixture_index": idx,
                "snapshot": snapshot,
                "mode": mode
            }))
        }
        ("delegate", Some(idx)) => {
            // Delegate: AI controls user's team. Create session, run to completion, apply report.
            let mut session =
                live_match_manager::create_live_match(&game, idx, MatchMode::Instant, false)?;
            // AI controls BOTH sides (user_side is None for Instant mode auto-AI)
            session.user_side = None;
            session.run_to_completion();

            let home_team_id = session.home_team_id.clone();
            let away_team_id = session.away_team_id.clone();
            let report = session.match_state.into_report();

            // Simulate all other matches for today
            ofm_core::turn::simulate_other_matches(&mut game, &today, Some(idx));

            // Apply user's delegated match report
            ofm_core::turn::apply_match_report(
                &mut game,
                idx,
                &home_team_id,
                &away_team_id,
                &report,
            );

            // Complete the day
            ofm_core::turn::finish_live_match_day(&mut game);
            state.set_game(game.clone());

            Ok(serde_json::json!({
                "action": "advanced",
                "game": game
            }))
        }
        _ => {
            // Normal advance: simulate everything including user match
            ofm_core::turn::process_day(&mut game);
            state.set_game(game.clone());

            Ok(serde_json::json!({
                "action": "advanced",
                "game": game
            }))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::compute_blocking_actions;
    use chrono::{TimeZone, Utc};
    use domain::manager::Manager;
    use domain::message::{InboxMessage, MessagePriority};
    use domain::player::{Injury, Player, PlayerAttributes, Position};
    use domain::team::Team;
    use ofm_core::clock::GameClock;
    use ofm_core::game::Game;
    use serde_json::Value;

    fn default_attrs() -> PlayerAttributes {
        PlayerAttributes {
            pace: 60,
            stamina: 60,
            strength: 60,
            agility: 60,
            passing: 60,
            shooting: 60,
            tackling: 60,
            dribbling: 60,
            defending: 60,
            positioning: 60,
            vision: 60,
            decisions: 60,
            composure: 60,
            aggression: 60,
            teamwork: 60,
            leadership: 60,
            handling: 60,
            reflexes: 60,
            aerial: 60,
        }
    }

    fn make_player(id: &str, name: &str, team_id: &str, position: Position) -> Player {
        let mut player = Player::new(
            id.to_string(),
            name.to_string(),
            name.to_string(),
            "2000-01-01".to_string(),
            "England".to_string(),
            position,
            default_attrs(),
        );
        player.team_id = Some(team_id.to_string());
        player
    }

    fn make_game(roster_size: usize) -> Game {
        let clock = GameClock::new(Utc.with_ymd_and_hms(2025, 6, 15, 12, 0, 0).unwrap());
        let mut manager = Manager::new(
            "mgr1".to_string(),
            "Alex".to_string(),
            "Manager".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        manager.hire("team1".to_string());

        let players: Vec<Player> = (1..=roster_size)
            .map(|idx| {
                let position = if idx == 1 {
                    Position::Goalkeeper
                } else if idx <= 5 {
                    Position::Defender
                } else if idx <= 9 {
                    Position::Midfielder
                } else {
                    Position::Forward
                };

                make_player(
                    &format!("p{}", idx),
                    &format!("Player {}", idx),
                    "team1",
                    position,
                )
            })
            .collect();

        let mut team = Team::new(
            "team1".to_string(),
            "Test FC".to_string(),
            "TST".to_string(),
            "England".to_string(),
            "Testville".to_string(),
            "Test Ground".to_string(),
            20_000,
        );
        team.starting_xi_ids = players
            .iter()
            .take(11)
            .map(|player| player.id.clone())
            .collect();

        Game::new(clock, manager, vec![team], players, vec![], vec![])
    }

    fn make_message(id: &str, priority: MessagePriority, read: bool) -> InboxMessage {
        let mut message = InboxMessage::new(
            id.to_string(),
            "Subject".to_string(),
            "Body".to_string(),
            "Board".to_string(),
            "2025-06-15".to_string(),
        )
        .with_priority(priority);
        message.read = read;
        message
    }

    fn blocker_by_id<'a>(blockers: &'a [Value], id: &str) -> Option<&'a Value> {
        blockers
            .iter()
            .find(|blocker| blocker.get("id").and_then(Value::as_str) == Some(id))
    }

    #[test]
    fn healthy_squad_with_no_urgent_messages_has_no_blockers() {
        let game = make_game(11);

        let blockers = compute_blocking_actions(&game);

        assert!(blockers.is_empty());
    }

    #[test]
    fn injured_starters_trigger_injury_and_incomplete_xi_blockers() {
        let mut game = make_game(11);
        for player_id in ["p2", "p5"] {
            let player = game
                .players
                .iter_mut()
                .find(|player| player.id == player_id)
                .unwrap();
            player.injury = Some(Injury {
                name: "Hamstring".to_string(),
                days_remaining: 7,
            });
        }

        let blockers = compute_blocking_actions(&game);

        let injured = blocker_by_id(&blockers, "injured_xi").unwrap();
        assert_eq!(
            injured.get("severity").and_then(Value::as_str),
            Some("warn")
        );
        assert_eq!(injured.get("tab").and_then(Value::as_str), Some("Squad"));
        let injured_text = injured.get("text").and_then(Value::as_str).unwrap();
        assert!(injured_text.contains("2 injured player(s)"));
        assert!(injured_text.contains("Player 2"));
        assert!(injured_text.contains("Player 5"));

        let incomplete = blocker_by_id(&blockers, "incomplete_xi").unwrap();
        assert_eq!(
            incomplete.get("severity").and_then(Value::as_str),
            Some("warn")
        );
        assert_eq!(incomplete.get("tab").and_then(Value::as_str), Some("Squad"));
        assert_eq!(
            incomplete.get("text").and_then(Value::as_str),
            Some("Starting XI has only 9 healthy players — set your lineup")
        );
    }

    #[test]
    fn incomplete_xi_is_not_reported_when_roster_has_fewer_than_eleven_players() {
        let mut game = make_game(10);
        let player = game
            .players
            .iter_mut()
            .find(|player| player.id == "p3")
            .unwrap();
        player.injury = Some(Injury {
            name: "Knee".to_string(),
            days_remaining: 14,
        });

        let blockers = compute_blocking_actions(&game);

        assert!(blocker_by_id(&blockers, "injured_xi").is_some());
        assert!(blocker_by_id(&blockers, "incomplete_xi").is_none());
    }

    #[test]
    fn only_unread_urgent_messages_produce_message_blockers() {
        let mut game = make_game(11);
        game.messages = vec![
            make_message("urgent-1", MessagePriority::Urgent, false),
            make_message("urgent-2", MessagePriority::Urgent, false),
            make_message("urgent-read", MessagePriority::Urgent, true),
            make_message("high", MessagePriority::High, false),
        ];

        let blockers = compute_blocking_actions(&game);

        assert_eq!(blockers.len(), 1);
        let urgent = blocker_by_id(&blockers, "urgent_messages").unwrap();
        assert_eq!(urgent.get("severity").and_then(Value::as_str), Some("info"));
        assert_eq!(urgent.get("tab").and_then(Value::as_str), Some("Inbox"));
        assert_eq!(
            urgent.get("text").and_then(Value::as_str),
            Some("2 urgent unread message(s)")
        );
    }
}
