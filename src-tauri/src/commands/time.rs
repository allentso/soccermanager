use log::info;
use tauri::State;

use ofm_core::game::Game;
use ofm_core::live_match_manager::{self, MatchMode};
use ofm_core::state::StateManager;

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
    let user_team_id = match &game.manager.team_id {
        Some(id) => id,
        None => return blockers,
    };

    let team = match game.teams.iter().find(|t| t.id == *user_team_id) {
        Some(t) => t,
        None => return blockers,
    };

    let roster: Vec<_> = game
        .players
        .iter()
        .filter(|p| p.team_id.as_deref() == Some(user_team_id))
        .collect();
    let xi_ids = &team.starting_xi_ids;

    // Check for injured players in XI
    let injured_in_xi: Vec<_> = xi_ids
        .iter()
        .filter_map(|id| roster.iter().find(|p| p.id == *id && p.injury.is_some()))
        .map(|p| p.match_name.clone())
        .collect();
    if !injured_in_xi.is_empty() {
        blockers.push(serde_json::json!({
            "id": "injured_xi",
            "severity": "warn",
            "text": format!("{} injured player(s) in Starting XI: {}", injured_in_xi.len(), injured_in_xi.join(", ")),
            "tab": "Squad"
        }));
    }

    // Check if XI is incomplete (fewer than 11 healthy players)
    let healthy_xi = xi_ids
        .iter()
        .filter(|id| roster.iter().any(|p| p.id == **id && p.injury.is_none()))
        .count();
    if healthy_xi < 11 && roster.len() >= 11 {
        blockers.push(serde_json::json!({
            "id": "incomplete_xi",
            "severity": "warn",
            "text": format!("Starting XI has only {} healthy players — set your lineup", healthy_xi),
            "tab": "Squad"
        }));
    }

    // Check for unresolved urgent messages
    let urgent_unread = game
        .messages
        .iter()
        .filter(|m| !m.read && m.priority == domain::message::MessagePriority::Urgent)
        .count();
    if urgent_unread > 0 {
        blockers.push(serde_json::json!({
            "id": "urgent_messages",
            "severity": "info",
            "text": format!("{} urgent unread message(s)", urgent_unread),
            "tab": "Inbox"
        }));
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
