use log::info;
use tauri::State;

use ofm_core::game::Game;
use ofm_core::live_match_manager::{self, MatchMode};
use ofm_core::state::StateManager;
use rand::Rng;

// ---------------------------------------------------------------------------
// Live Match Commands
// ---------------------------------------------------------------------------

/// Start a live match for a given fixture.
/// mode: "live" | "spectator" | "instant"
#[tauri::command]
pub fn start_live_match(
    state: State<'_, StateManager>,
    fixture_index: usize,
    mode: String,
    allows_extra_time: bool,
) -> Result<engine::MatchSnapshot, String> {
    info!(
        "[cmd] start_live_match: fixture={}, mode={}, extra_time={}",
        fixture_index, mode, allows_extra_time
    );
    let game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let match_mode = match mode.as_str() {
        "spectator" => MatchMode::Spectator,
        "instant" => MatchMode::Instant,
        _ => MatchMode::Live,
    };

    let session =
        live_match_manager::create_live_match(&game, fixture_index, match_mode, allows_extra_time)?;
    let snapshot = session.snapshot();
    state.set_live_match(session);
    Ok(snapshot)
}

/// Step the live match forward by N minutes. Returns the events from each minute.
#[tauri::command]
pub fn step_live_match(
    state: State<'_, StateManager>,
    minutes: u16,
) -> Result<Vec<engine::MinuteResult>, String> {
    log::debug!("[cmd] step_live_match: minutes={}", minutes);
    state
        .with_live_match(|session| {
            if minutes <= 1 {
                vec![session.step()]
            } else {
                session.step_many(minutes)
            }
        })
        .ok_or_else(|| "No active live match".to_string())
}

/// Apply a match command (substitution, tactic change, set piece taker, etc.)
#[tauri::command]
pub fn apply_match_command(
    state: State<'_, StateManager>,
    command: engine::MatchCommand,
) -> Result<engine::MatchSnapshot, String> {
    info!("[cmd] apply_match_command: {:?}", command);
    state
        .with_live_match(|session| {
            session.apply_command(command)?;
            Ok(session.snapshot())
        })
        .ok_or_else(|| "No active live match".to_string())?
}

/// Get current match snapshot without advancing time.
#[tauri::command]
pub fn get_match_snapshot(state: State<'_, StateManager>) -> Result<engine::MatchSnapshot, String> {
    log::debug!("[cmd] get_match_snapshot");
    state
        .with_live_match(|session| session.snapshot())
        .ok_or_else(|| "No active live match".to_string())
}

/// Finish the live match: generate report, update game state, clean up.
#[tauri::command]
pub fn finish_live_match(state: State<'_, StateManager>) -> Result<Game, String> {
    info!("[cmd] finish_live_match");
    let session = state.take_live_match().ok_or("No active live match")?;

    let fixture_index = session.fixture_index;
    let home_team_id = session.home_team_id.clone();
    let away_team_id = session.away_team_id.clone();

    let report = session.match_state.into_report();

    // Update the game state with the match result
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    // Apply the match result using the existing turn logic
    ofm_core::turn::apply_match_report(
        &mut game,
        fixture_index,
        &home_team_id,
        &away_team_id,
        &report,
    );

    // Complete the day: generate pre-match messages for upcoming fixtures, then advance the clock
    ofm_core::turn::finish_live_match_day(&mut game);

    state.set_game(game.clone());
    Ok(game)
}

/// Apply a team talk and return per-player morale changes.
/// tone: "calm" | "motivational" | "assertive" | "aggressive" | "praise" | "disappointed"
/// context: "winning" | "losing" | "drawing"
#[tauri::command]
pub fn apply_team_talk(
    state: State<'_, StateManager>,
    tone: String,
    context: String,
) -> Result<Vec<serde_json::Value>, String> {
    info!("[cmd] apply_team_talk: tone={}, context={}", tone, context);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let user_team_id = game.manager.team_id.clone().ok_or("No team assigned")?;

    let mut rng = rand::thread_rng();

    let mut results: Vec<serde_json::Value> = Vec::new();

    for player in game.players.iter_mut() {
        if player.team_id.as_deref() != Some(&user_team_id) {
            continue;
        }

        let base_morale = player.morale as i16;

        // Base delta depends on tone + context
        let delta: i16 = match (tone.as_str(), context.as_str()) {
            ("calm", _) => rng.gen_range(1..=4),
            ("motivational", "losing") => rng.gen_range(5..=12),
            ("motivational", "drawing") => rng.gen_range(3..=8),
            ("motivational", "winning") => rng.gen_range(2..=6),
            ("assertive", "losing") => rng.gen_range(2..=8),
            ("assertive", "drawing") => rng.gen_range(0..=5),
            ("assertive", "winning") => rng.gen_range(-3..=3),
            ("aggressive", "losing") => rng.gen_range(4..=10),
            ("aggressive", "drawing") => rng.gen_range(-2..=6),
            ("aggressive", "winning") => rng.gen_range(-6..=2),
            ("praise", "winning") => rng.gen_range(5..=12),
            ("praise", "drawing") => rng.gen_range(3..=8),
            ("praise", "losing") => rng.gen_range(-2..=3),
            ("disappointed", "losing") => rng.gen_range(-4..=4),
            ("disappointed", "drawing") => rng.gen_range(-6..=2),
            ("disappointed", "winning") => rng.gen_range(-8..=-2),
            _ => rng.gen_range(0..=3),
        };

        let new_morale = (base_morale + delta).clamp(10, 100) as u8;
        let actual_delta = new_morale as i16 - base_morale;
        player.morale = new_morale;

        results.push(serde_json::json!({
            "player_id": player.id,
            "player_name": player.match_name,
            "old_morale": base_morale,
            "new_morale": new_morale,
            "delta": actual_delta
        }));
    }

    state.set_game(game);
    Ok(results)
}

/// Process press conference answers: generate news article, affect squad morale.
/// answers: array of { question_id, response_id, response_tone, response_text, question_text }
#[tauri::command]
pub fn submit_press_conference(
    state: State<'_, StateManager>,
    answers: Vec<serde_json::Value>,
    home_team: String,
    away_team: String,
    home_score: u8,
    away_score: u8,
    user_team_name: String,
    user_team_id: String,
) -> Result<serde_json::Value, String> {
    info!(
        "[cmd] submit_press_conference: {} {} - {} {}",
        home_team, home_score, away_score, away_team
    );
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let mut rng = rand::thread_rng();

    // Build news article from press conference answers
    let mut quotes: Vec<String> = Vec::new();
    let mut morale_delta: i16 = 0;
    let mut mentioned_player_ids: Vec<String> = Vec::new();

    for answer in &answers {
        let tone = answer
            .get("response_tone")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let text = answer
            .get("response_text")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let qid = answer
            .get("question_id")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        if !text.is_empty() {
            quotes.push(format!("\"{}\"", text));
        }

        // Track player mentions
        if let Some(pid) = answer.get("player_id").and_then(|v| v.as_str()) {
            if !pid.is_empty() {
                mentioned_player_ids.push(pid.to_string());
            }
        }

        // Morale effects based on tone
        match tone {
            "Humble" | "Fair" | "Positive" | "Focused" => morale_delta += rng.gen_range(1..=3),
            "Confident" | "Ambitious" => morale_delta += rng.gen_range(2..=5),
            "Defiant" | "Frustrated" => morale_delta += rng.gen_range(-2..=2),
            "Curt" | "Evasive" => morale_delta += rng.gen_range(-3..=0),
            "Accept" | "Detailed" => morale_delta += rng.gen_range(0..=2),
            "Deflect" => morale_delta += rng.gen_range(-1..=1),
            "Praise" => morale_delta += rng.gen_range(3..=6),
            "Demanding" => morale_delta += rng.gen_range(-2..=3),
            _ => {}
        }

        // Player-focused question effects
        if qid == "player_focus" {
            if let Some(pid) = answer.get("player_id").and_then(|v| v.as_str()) {
                if !pid.is_empty() {
                    let player_delta: i16 = match tone {
                        "Praise" => rng.gen_range(4..=8),
                        "Demanding" => rng.gen_range(-3..=4),
                        "Deflect" => rng.gen_range(-2..=1),
                        _ => rng.gen_range(0..=3),
                    };
                    if let Some(p) = game.players.iter_mut().find(|p| p.id == pid) {
                        p.morale = ((p.morale as i16) + player_delta).clamp(10, 100) as u8;
                    }
                }
            }
        }
    }

    // Apply squad-wide morale effect
    morale_delta = morale_delta.clamp(-8, 8);
    if morale_delta != 0 {
        for p in game.players.iter_mut() {
            if p.team_id.as_deref() == Some(&user_team_id) {
                p.morale = ((p.morale as i16) + morale_delta).clamp(10, 100) as u8;
            }
        }
    }

    // Generate news article
    let result_str = format!(
        "{} {} - {} {}",
        home_team, home_score, away_score, away_team
    );
    let headline = if quotes.is_empty() {
        format!("Post-Match: {} on {}", user_team_name, result_str)
    } else {
        let sources = [
            format!("{} Manager: {}", user_team_name, quotes[0]),
            format!(
                "Press Conference: \"{}\" — {} boss",
                quotes[0].trim_matches('"'),
                user_team_name
            ),
        ];
        sources[rng.gen_range(0..sources.len())].clone()
    };

    let body = if quotes.len() > 1 {
        format!(
            "Speaking after the {} result, the {} manager addressed the press.\n\n{}\n\n\
            The conference covered the result, tactical approach, and what lies ahead for the team.",
            result_str, user_team_name,
            quotes.iter().map(|q| format!("• {}", q)).collect::<Vec<_>>().join("\n")
        )
    } else if quotes.len() == 1 {
        format!(
            "The {} manager spoke briefly after the {} result.\n\n{}",
            user_team_name, result_str, quotes[0]
        )
    } else {
        format!(
            "The {} manager declined to speak at length after the {} result.",
            user_team_name, result_str
        )
    };

    let article_id = format!("press_conf_{}", today);
    let article = domain::news::NewsArticle::new(
        article_id,
        headline,
        body,
        "Sports Daily".to_string(),
        today.clone(),
        domain::news::NewsCategory::MatchReport,
    )
    .with_teams(vec![user_team_id.clone()]);

    game.news.push(article);
    state.set_game(game.clone());

    Ok(serde_json::json!({
        "game": game,
        "morale_delta": morale_delta
    }))
}
