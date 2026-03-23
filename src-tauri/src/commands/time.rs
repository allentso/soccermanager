use log::info;
use serde::{Deserialize, Serialize};
use tauri::State;

use crate::commands::round_summary::{build_round_summary_dto, RoundSummaryDto};
use ofm_core::contracts::contract_warning_stage;
use ofm_core::game::Game;
use ofm_core::live_match_manager::{self, MatchMode};
use ofm_core::player_rating::{effective_rating_for_assignment, formation_slots, natural_ovr};
use ofm_core::state::StateManager;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdvanceTimeWithModeResponse {
    pub action: String,
    pub game: Option<Game>,
    pub snapshot: Option<engine::MatchSnapshot>,
    pub fixture_index: Option<usize>,
    pub mode: Option<String>,
    pub round_summary: Option<RoundSummaryDto>,
}

fn round_context_for_today(
    game: &Game,
    today: &str,
) -> Option<(u32, Vec<domain::league::StandingEntry>)> {
    let league = game.league.as_ref()?;
    let matchday = league
        .fixtures
        .iter()
        .find(|fixture| fixture.date == today)
        .map(|fixture| fixture.matchday)?;

    Some((matchday, league.standings.clone()))
}

fn scheduled_user_fixture_index(game: &Game, today: &str) -> Option<usize> {
    let user_team_id = game.manager.team_id.as_ref()?;
    let league = game.league.as_ref()?;

    league
        .fixtures
        .iter()
        .enumerate()
        .find_map(|(index, fixture)| {
            if fixture.date == today
                && fixture.status == domain::league::FixtureStatus::Scheduled
                && (fixture.home_team_id == *user_team_id || fixture.away_team_id == *user_team_id)
            {
                Some(index)
            } else {
                None
            }
        })
}

fn advance_time_with_mode_internal(
    state: &StateManager,
    mode: &str,
) -> Result<AdvanceTimeWithModeResponse, String> {
    info!("[cmd] advance_time_with_mode: mode={}", mode);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let round_context = round_context_for_today(&game, &today);
    let user_fixture_idx = scheduled_user_fixture_index(&game, &today);

    info!(
        "[cmd] advance_time_with_mode: date={}, user_team_id={:?}, user_fixture_idx={:?}",
        today, game.manager.team_id, user_fixture_idx
    );

    match (mode, user_fixture_idx) {
        ("live" | "spectator", Some(idx)) => {
            let match_mode = if mode == "live" {
                MatchMode::Live
            } else {
                MatchMode::Spectator
            };
            let session = live_match_manager::create_live_match(&game, idx, match_mode, false)?;
            let snapshot = session.snapshot();
            info!(
                "[cmd] advance_time_with_mode: live_match fixture_idx={}, phase={:?}, home_team={}, away_team={}",
                idx,
                snapshot.phase,
                snapshot.home_team.name,
                snapshot.away_team.name
            );
            state.set_live_match(session);

            ofm_core::turn::simulate_other_matches(&mut game, &today, Some(idx));
            let round_summary =
                round_context
                    .as_ref()
                    .and_then(|(matchday, previous_standings)| {
                        build_round_summary_dto(&game, *matchday, previous_standings)
                    });
            state.set_game(game);

            Ok(AdvanceTimeWithModeResponse {
                action: "live_match".to_string(),
                game: None,
                snapshot: Some(snapshot),
                fixture_index: Some(idx),
                mode: Some(mode.to_string()),
                round_summary,
            })
        }
        ("delegate", Some(idx)) => {
            info!(
                "[cmd] advance_time_with_mode: delegate fixture_idx={}, date={}",
                idx, today
            );
            let mut session =
                live_match_manager::create_live_match(&game, idx, MatchMode::Instant, false)?;
            session.user_side = None;
            session.run_to_completion();

            let home_team_id = session.home_team_id.clone();
            let away_team_id = session.away_team_id.clone();
            let report = session.match_state.into_report();

            ofm_core::turn::simulate_other_matches(&mut game, &today, Some(idx));

            ofm_core::turn::apply_match_report(
                &mut game,
                idx,
                &home_team_id,
                &away_team_id,
                &report,
            );

            let round_summary =
                round_context
                    .as_ref()
                    .and_then(|(matchday, previous_standings)| {
                        build_round_summary_dto(&game, *matchday, previous_standings)
                    });

            ofm_core::turn::finish_live_match_day(&mut game);
            state.set_game(game.clone());

            Ok(AdvanceTimeWithModeResponse {
                action: "advanced".to_string(),
                game: Some(game),
                snapshot: None,
                fixture_index: None,
                mode: None,
                round_summary,
            })
        }
        _ => {
            info!(
                "[cmd] advance_time_with_mode: normal_advance date={}, mode={}",
                today, mode
            );
            ofm_core::turn::process_day(&mut game);
            let round_summary =
                round_context
                    .as_ref()
                    .and_then(|(matchday, previous_standings)| {
                        build_round_summary_dto(&game, *matchday, previous_standings)
                    });
            state.set_game(game.clone());

            Ok(AdvanceTimeWithModeResponse {
                action: "advanced".to_string(),
                game: Some(game),
                snapshot: None,
                fixture_index: None,
                mode: None,
                round_summary,
            })
        }
    }
}

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

fn build_effective_healthy_starting_xi_ids(
    saved_xi_ids: &[String],
    roster: &[&domain::player::Player],
    formation: &str,
) -> Vec<String> {
    let healthy_roster: Vec<&domain::player::Player> = roster
        .iter()
        .copied()
        .filter(|player| player.injury.is_none())
        .collect();
    let by_id: std::collections::HashMap<&str, &domain::player::Player> = healthy_roster
        .iter()
        .map(|player| (player.id.as_str(), *player))
        .collect();
    let mut used = std::collections::HashSet::new();
    let mut valid_saved_ids = Vec::new();

    for id in saved_xi_ids {
        if by_id.contains_key(id.as_str()) && used.insert(id.clone()) {
            valid_saved_ids.push(id.clone());
        }
    }

    let mut remaining_players: Vec<&domain::player::Player> = healthy_roster
        .iter()
        .copied()
        .filter(|player| !used.contains(&player.id))
        .collect();
    remaining_players.sort_by(|a, b| {
        natural_ovr(b)
            .partial_cmp(&natural_ovr(a))
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let slots = formation_slots(formation);

    if valid_saved_ids.len() >= 8 {
        let mut xi_ids = valid_saved_ids;
        while xi_ids.len() < 11 {
            let slot = slots.get(xi_ids.len());
            let best_index = remaining_players
                .iter()
                .enumerate()
                .max_by(|(_, left), (_, right)| {
                    let left_rating = slot.map_or_else(
                        || natural_ovr(left),
                        |slot| effective_rating_for_assignment(left, slot),
                    );
                    let right_rating = slot.map_or_else(
                        || natural_ovr(right),
                        |slot| effective_rating_for_assignment(right, slot),
                    );
                    left_rating
                        .partial_cmp(&right_rating)
                        .unwrap_or(std::cmp::Ordering::Equal)
                })
                .map(|(index, _)| index);

            let Some(best_index) = best_index else {
                break;
            };

            let player = remaining_players.remove(best_index);
            xi_ids.push(player.id.clone());
        }
        xi_ids.truncate(11);
        return xi_ids;
    }
    let mut xi_ids = Vec::new();

    for slot in slots.iter().take(11) {
        let best_player = healthy_roster
            .iter()
            .copied()
            .filter(|player| !used.contains(&player.id))
            .max_by(|left, right| {
                effective_rating_for_assignment(left, slot)
                    .partial_cmp(&effective_rating_for_assignment(right, slot))
                    .unwrap_or(std::cmp::Ordering::Equal)
            });

        let Some(player) = best_player else {
            break;
        };

        if used.insert(player.id.clone()) {
            xi_ids.push(player.id.clone());
        }
    }

    xi_ids
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
    effective_healthy_xi_ids: &[String],
    roster: &[&domain::player::Player],
) -> Option<serde_json::Value> {
    let healthy_xi = effective_healthy_xi_ids.len();

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

fn key_contract_risk_blocker(
    roster: &[&domain::player::Player],
    effective_healthy_xi_ids: &[String],
    current_date: chrono::NaiveDate,
) -> Option<serde_json::Value> {
    let effective_xi_id_set: std::collections::HashSet<&str> = effective_healthy_xi_ids
        .iter()
        .map(String::as_str)
        .collect();

    let mut effective_xi_players: Vec<&domain::player::Player> = roster
        .iter()
        .copied()
        .filter(|player| effective_xi_id_set.contains(player.id.as_str()))
        .collect();
    effective_xi_players.sort_by(|a, b| {
        natural_ovr(b)
            .partial_cmp(&natural_ovr(a))
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let risky_key_players: Vec<&str> = effective_xi_players
        .into_iter()
        .take(3)
        .filter(|player| {
            contract_warning_stage(player.contract_end.as_deref(), current_date).is_some()
        })
        .map(|player| player.match_name.as_str())
        .collect();

    (!risky_key_players.is_empty()).then(|| {
        build_blocker(
            "key_contract_risk",
            "warn",
            format!(
                "Key player contract risk in squad planning: {}",
                risky_key_players.join(", ")
            ),
            "Squad",
        )
    })
}

fn contract_wage_risk_blocker(
    team: &domain::team::Team,
    roster: &[&domain::player::Player],
    current_date: chrono::NaiveDate,
) -> Option<serde_json::Value> {
    let at_risk_wages: u32 = roster
        .iter()
        .copied()
        .filter(|player| {
            contract_warning_stage(player.contract_end.as_deref(), current_date).is_some()
        })
        .map(|player| player.wage)
        .sum();

    let wage_budget = team.wage_budget.max(0) as u32;
    (wage_budget > 0 && at_risk_wages > wage_budget).then(|| {
        build_blocker(
            "contract_wage_risk",
            "warn",
            format!(
                "{} of wages are tied to at-risk contracts — review your wage budget",
                at_risk_wages
            ),
            "Finances",
        )
    })
}

/// Advance time with a specific match mode.
/// mode: "live" | "spectator" | "delegate" | "instant"
/// If mode is "live" or "spectator" and there's a user match today,
/// it sets up the live match session instead of auto-simulating.
#[tauri::command]
pub fn advance_time_with_mode(
    state: State<'_, StateManager>,
    mode: String,
) -> Result<AdvanceTimeWithModeResponse, String> {
    advance_time_with_mode_internal(&state, &mode)
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
    ofm_core::turn::process_day(&mut current_game);

    state.set_game(current_game.clone());
    Ok(current_game)
}

pub fn compute_blocking_actions(game: &Game) -> Vec<serde_json::Value> {
    let mut blockers = Vec::new();
    let (team, roster) = match user_team_context(game) {
        Some(context) => context,
        None => {
            info!("[cmd] compute_blocking_actions: no user team context");
            return blockers;
        }
    };
    let saved_xi_ids = &team.starting_xi_ids;
    let current_date = game.clock.current_date.date_naive();
    let effective_healthy_xi_ids =
        build_effective_healthy_starting_xi_ids(saved_xi_ids, &roster, &team.formation);

    if let Some(blocker) = injured_starting_xi_blocker(saved_xi_ids, &roster) {
        blockers.push(blocker);
    }

    if let Some(blocker) = incomplete_starting_xi_blocker(&effective_healthy_xi_ids, &roster) {
        blockers.push(blocker);
    }

    if let Some(blocker) =
        key_contract_risk_blocker(&roster, &effective_healthy_xi_ids, current_date)
    {
        blockers.push(blocker);
    }

    if let Some(blocker) = contract_wage_risk_blocker(team, &roster, current_date) {
        blockers.push(blocker);
    }

    if let Some(blocker) = urgent_unread_messages_blocker(game) {
        blockers.push(blocker);
    }

    let blocker_ids: Vec<String> = blockers
        .iter()
        .filter_map(|blocker| blocker.get("id").and_then(|id| id.as_str()))
        .map(|id| id.to_string())
        .collect();

    info!(
        "[cmd] compute_blocking_actions: date={}, team={}, roster={}, xi={}, blockers={:?}",
        game.clock.current_date.format("%Y-%m-%d"),
        team.id,
        roster.len(),
        effective_healthy_xi_ids.len(),
        blocker_ids
    );

    blockers
}

#[tauri::command]
pub fn check_blocking_actions(state: State<'_, StateManager>) -> Result<serde_json::Value, String> {
    log::debug!("[cmd] check_blocking_actions");
    let game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let blockers = compute_blocking_actions(&game);
    info!(
        "[cmd] check_blocking_actions: date={}, blocker_count={}",
        game.clock.current_date.format("%Y-%m-%d"),
        blockers.len()
    );
    Ok(serde_json::json!(blockers))
}

#[tauri::command]
pub fn skip_to_match_day(state: State<'_, StateManager>) -> Result<serde_json::Value, String> {
    info!("[cmd] skip_to_match_day");
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let user_team_id = game.manager.team_id.clone().ok_or("No team assigned")?;
    info!(
        "[cmd] skip_to_match_day: start_date={}, user_team_id={}",
        game.clock.current_date.format("%Y-%m-%d"),
        user_team_id
    );

    let mut days_skipped = 0u32;
    loop {
        if days_skipped >= 60 {
            break;
        }

        let today = game.clock.current_date.format("%Y-%m-%d").to_string();

        let has_match = game.league.as_ref().is_some_and(|league| {
            league.fixtures.iter().any(|fixture| {
                fixture.date == today
                    && fixture.status == domain::league::FixtureStatus::Scheduled
                    && (fixture.home_team_id == user_team_id
                        || fixture.away_team_id == user_team_id)
            })
        });

        if has_match {
            info!(
                "[cmd] skip_to_match_day: found match_day={}, days_skipped={}",
                today, days_skipped
            );
            break;
        }

        ofm_core::turn::process_day(&mut game);
        days_skipped += 1;

        let blockers = compute_blocking_actions(&game);
        if !blockers.is_empty() {
            info!(
                "[cmd] skip_to_match_day: blocked_after_days={}, date={}, blocker_count={}",
                days_skipped,
                game.clock.current_date.format("%Y-%m-%d"),
                blockers.len()
            );
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
        "[cmd] skip_to_match_day: arrived_after_days={}, final_date={}",
        days_skipped,
        game.clock.current_date.format("%Y-%m-%d")
    );
    state.set_game(game.clone());
    Ok(serde_json::json!({
        "action": "arrived",
        "game": game,
        "days_skipped": days_skipped
    }))
}

#[cfg(test)]
mod tests {
    use super::{advance_time_with_mode_internal, compute_blocking_actions};
    use chrono::{TimeZone, Utc};
    use domain::manager::Manager;
    use domain::message::{InboxMessage, MessagePriority};
    use domain::player::{Injury, Player, PlayerAttributes, Position};
    use domain::team::Team;
    use ofm_core::clock::GameClock;
    use ofm_core::game::Game;
    use ofm_core::state::StateManager;
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
    fn incomplete_xi_is_not_reported_when_a_partial_saved_lineup_can_be_filled_by_healthy_players()
    {
        let mut game = make_game(11);
        game.teams[0].starting_xi_ids = vec![
            "p1".to_string(),
            "p2".to_string(),
            "p3".to_string(),
            "p4".to_string(),
            "p5".to_string(),
            "p6".to_string(),
            "p7".to_string(),
            "p8".to_string(),
        ];

        let blockers = compute_blocking_actions(&game);

        assert!(blocker_by_id(&blockers, "injured_xi").is_none());
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

    #[test]
    fn key_player_contract_risk_triggers_squad_blocker() {
        let mut game = make_game(11);

        let first_key_player = game
            .players
            .iter_mut()
            .find(|player| player.id == "p10")
            .unwrap();
        first_key_player.contract_end = Some("2025-08-01".to_string());
        first_key_player.wage = 35_000;
        first_key_player.attributes.pace = 92;
        first_key_player.attributes.shooting = 94;
        first_key_player.attributes.dribbling = 90;

        let second_key_player = game
            .players
            .iter_mut()
            .find(|player| player.id == "p11")
            .unwrap();
        second_key_player.contract_end = Some("2025-09-01".to_string());
        second_key_player.wage = 25_000;
        second_key_player.attributes.pace = 90;
        second_key_player.attributes.shooting = 91;
        second_key_player.attributes.dribbling = 89;

        let blockers = compute_blocking_actions(&game);

        let contract_blocker = blocker_by_id(&blockers, "key_contract_risk").unwrap();
        assert_eq!(
            contract_blocker.get("severity").and_then(Value::as_str),
            Some("warn")
        );
        assert_eq!(
            contract_blocker.get("tab").and_then(Value::as_str),
            Some("Squad")
        );

        let text = contract_blocker
            .get("text")
            .and_then(Value::as_str)
            .unwrap();
        assert!(text.contains("Player 10"));
        assert!(text.contains("Player 11"));
    }

    #[test]
    fn large_at_risk_wage_share_triggers_finance_blocker() {
        let mut game = make_game(11);
        game.teams[0].wage_budget = 50_000;

        let first_risk = game
            .players
            .iter_mut()
            .find(|player| player.id == "p10")
            .unwrap();
        first_risk.contract_end = Some("2025-08-01".to_string());
        first_risk.wage = 35_000;

        let second_risk = game
            .players
            .iter_mut()
            .find(|player| player.id == "p11")
            .unwrap();
        second_risk.contract_end = Some("2025-09-01".to_string());
        second_risk.wage = 25_000;

        let blockers = compute_blocking_actions(&game);

        let finance_blocker = blocker_by_id(&blockers, "contract_wage_risk").unwrap();
        assert_eq!(
            finance_blocker.get("severity").and_then(Value::as_str),
            Some("warn")
        );
        assert_eq!(
            finance_blocker.get("tab").and_then(Value::as_str),
            Some("Finances")
        );

        let text = finance_blocker.get("text").and_then(Value::as_str).unwrap();
        assert!(text.contains("60000"));
        assert!(text.contains("wage budget"));
    }

    fn make_round_summary_game() -> Game {
        let clock = GameClock::new(Utc.with_ymd_and_hms(2025, 6, 15, 12, 0, 0).unwrap());
        let mut manager = Manager::new(
            "mgr1".to_string(),
            "Alex".to_string(),
            "Manager".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        manager.hire("team1".to_string());

        let teams = vec![
            Team::new(
                "team1".to_string(),
                "Test FC".to_string(),
                "TST".to_string(),
                "England".to_string(),
                "Testville".to_string(),
                "Test Ground".to_string(),
                20_000,
            ),
            Team::new(
                "team2".to_string(),
                "Rival FC".to_string(),
                "RIV".to_string(),
                "England".to_string(),
                "Rivaltown".to_string(),
                "Rival Ground".to_string(),
                20_000,
            ),
            Team::new(
                "team3".to_string(),
                "Third FC".to_string(),
                "THI".to_string(),
                "England".to_string(),
                "Thirdtown".to_string(),
                "Third Ground".to_string(),
                20_000,
            ),
            Team::new(
                "team4".to_string(),
                "Fourth FC".to_string(),
                "FOU".to_string(),
                "England".to_string(),
                "Fourthtown".to_string(),
                "Fourth Ground".to_string(),
                20_000,
            ),
        ];

        let mut players = Vec::new();
        for (team_id, prefix) in [
            ("team1", "a"),
            ("team2", "b"),
            ("team3", "c"),
            ("team4", "d"),
        ] {
            players.push(make_player(
                &format!("{}-gk", prefix),
                &format!("{} GK", prefix),
                team_id,
                Position::Goalkeeper,
            ));
            for idx in 0..4 {
                players.push(make_player(
                    &format!("{}-def{}", prefix, idx),
                    &format!("{} Def{}", prefix, idx),
                    team_id,
                    Position::Defender,
                ));
            }
            for idx in 0..4 {
                players.push(make_player(
                    &format!("{}-mid{}", prefix, idx),
                    &format!("{} Mid{}", prefix, idx),
                    team_id,
                    Position::Midfielder,
                ));
            }
            for idx in 0..2 {
                players.push(make_player(
                    &format!("{}-fwd{}", prefix, idx),
                    &format!("{} Fwd{}", prefix, idx),
                    team_id,
                    Position::Forward,
                ));
            }
        }

        let league = domain::league::League {
            id: "league1".to_string(),
            name: "Test League".to_string(),
            season: 1,
            fixtures: vec![
                domain::league::Fixture {
                    id: "fix1".to_string(),
                    matchday: 1,
                    date: "2025-06-15".to_string(),
                    home_team_id: "team1".to_string(),
                    away_team_id: "team2".to_string(),
                    status: domain::league::FixtureStatus::Scheduled,
                    result: None,
                },
                domain::league::Fixture {
                    id: "fix2".to_string(),
                    matchday: 1,
                    date: "2025-06-15".to_string(),
                    home_team_id: "team3".to_string(),
                    away_team_id: "team4".to_string(),
                    status: domain::league::FixtureStatus::Scheduled,
                    result: None,
                },
            ],
            standings: vec![
                domain::league::StandingEntry::new("team1".to_string()),
                domain::league::StandingEntry::new("team2".to_string()),
                domain::league::StandingEntry::new("team3".to_string()),
                domain::league::StandingEntry::new("team4".to_string()),
            ],
        };

        let mut game = Game::new(clock, manager, teams, players, vec![], vec![]);
        game.league = Some(league);
        game
    }

    #[test]
    fn advance_time_with_mode_live_returns_partial_round_summary() {
        let state = StateManager::new();
        state.set_game(make_round_summary_game());

        let response =
            advance_time_with_mode_internal(&state, "live").expect("live advance response");

        assert_eq!(response.action, "live_match");
        let round_summary = response.round_summary.expect("round summary");
        assert!(!round_summary.is_complete);
        assert_eq!(round_summary.pending_fixture_count, 1);
        assert_eq!(round_summary.completed_results.len(), 1);
    }

    #[test]
    fn advance_time_with_mode_delegate_returns_completed_round_summary() {
        let state = StateManager::new();
        state.set_game(make_round_summary_game());

        let response =
            advance_time_with_mode_internal(&state, "delegate").expect("delegate advance response");

        assert_eq!(response.action, "advanced");
        let round_summary = response.round_summary.expect("round summary");
        assert!(round_summary.is_complete);
        assert_eq!(round_summary.pending_fixture_count, 0);
        assert_eq!(round_summary.completed_results.len(), 2);
    }
}
