use tauri::Manager as TauriManager;
use tauri::State;

use db::manager::DbManager;
use domain::manager::Manager;
use ofm_core::clock::GameClock;
use ofm_core::game::Game;
use ofm_core::live_match_manager::{self, MatchMode};
use ofm_core::state::StateManager;

/// Step 1: Create manager + generate world. No team assigned yet.
/// Returns the Game object so the frontend can show team selection.
#[tauri::command]
fn start_new_game(
    state: State<StateManager>,
    first_name: String,
    last_name: String,
    dob: String,
    nationality: String,
) -> Result<Game, String> {
    let manager = Manager::new(
        "mgr_user".to_string(),
        first_name,
        last_name,
        dob,
        nationality,
    );

    use chrono::TimeZone;
    let start_date = chrono::Utc.with_ymd_and_hms(2026, 7, 1, 0, 0, 0).unwrap();
    let clock = GameClock::new(start_date);

    // Generate world — no team is assigned to the user yet
    let (teams, players, staff) = ofm_core::generator::generate_world();

    let new_game = Game::new(
        clock,
        manager,
        teams,
        players,
        staff,
        vec![],
    );

    state.set_game(new_game.clone());
    Ok(new_game)
}

/// Step 2: User picks a team. Assigns manager, generates welcome message, saves to DB.
#[tauri::command]
fn select_team(
    state: State<StateManager>,
    app_handle: tauri::AppHandle,
    team_id: String,
) -> Result<Game, String> {
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    // Validate team exists
    let team = game.teams.iter().find(|t| t.id == team_id)
        .ok_or("Team not found".to_string())?;
    let team_name = team.name.clone();

    // Assign manager to team
    game.manager.hire(team_id.clone());
    if let Some(t) = game.teams.iter_mut().find(|t| t.id == team_id) {
        t.manager_id = Some(game.manager.id.clone());
    }

    // Generate league schedule — season starts 1 month after game start
    use chrono::Duration;
    let season_start = game.clock.current_date + Duration::days(30);
    let team_ids: Vec<String> = game.teams.iter().map(|t| t.id.clone()).collect();
    let league = ofm_core::schedule::generate_league(
        "Premier Division",
        2026,
        &team_ids,
        season_start,
    );
    game.league = Some(league);

    // Rich templated messages
    let date_str = game.clock.current_date.to_rfc3339();
    let welcome_msg = ofm_core::messages::welcome_message(&team_name, &team_id, &date_str);
    game.messages.push(welcome_msg);

    let season_msg = ofm_core::messages::season_schedule_message(
        "Premier Division",
        &season_start.format("%B %d, %Y").to_string(),
        &date_str,
    );
    game.messages.push(season_msg);

    let board_msg = ofm_core::messages::board_expectations_message(&team_name, &team_id, &date_str);
    game.messages.push(board_msg);

    // Save to DB
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?;
    std::fs::create_dir_all(&app_data_dir).map_err(|e| e.to_string())?;
    let db_path = app_data_dir.join("saves.db");

    let db_manager = DbManager::new(db_path).map_err(|e| e.to_string())?;

    let game_json = serde_json::to_string(&game).map_err(|e| e.to_string())?;
    let manager_name = format!("{} {}", game.manager.first_name, game.manager.last_name);
    let save_name = format!("{}'s Career", manager_name);

    db_manager
        .create_save(&save_name, &manager_name, &game_json)
        .map_err(|e| e.to_string())?;

    state.set_game(game.clone());
    Ok(game)
}

#[derive(serde::Serialize)]
pub struct SaveMetadata {
    pub id: i64,
    pub name: String,
    pub manager_name: String,
    pub created_at: String,
    pub last_played_at: String,
}

#[tauri::command]
fn get_saves(app_handle: tauri::AppHandle) -> Result<Vec<SaveMetadata>, String> {
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?;
    let db_path = app_data_dir.join("saves.db");

    // If DB doesn't exist, return empty list instead of erroring
    if !db_path.exists() {
        return Ok(Vec::new());
    }

    let db_manager = DbManager::new(db_path).map_err(|e| e.to_string())?;
    let saves = db_manager.get_saves().map_err(|e| e.to_string())?;

    Ok(saves
        .into_iter()
        .map(|s| SaveMetadata {
            id: s.0,
            name: s.1,
            manager_name: s.2,
            created_at: s.3,
            last_played_at: s.4,
        })
        .collect())
}

#[tauri::command]
fn load_game(
    state: State<StateManager>,
    app_handle: tauri::AppHandle,
    save_id: i64,
) -> Result<String, String> {
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?;
    let db_path = app_data_dir.join("saves.db");
    let db_manager = DbManager::new(db_path).map_err(|e| e.to_string())?;

    let game_json = db_manager.load_save(save_id).map_err(|e| e.to_string())?;
    let game: Game = serde_json::from_str(&game_json).map_err(|e| e.to_string())?;

    let mgr_name = format!("{} {}", game.manager.first_name, game.manager.last_name);

    state.set_game(game);
    Ok(mgr_name)
}

#[tauri::command]
fn get_active_game(state: State<StateManager>) -> Result<Game, String> {
    state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())
}

#[tauri::command]
fn advance_time(state: State<StateManager>) -> Result<Game, String> {
    let mut current_game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    // Process a full day: matchday simulation, training, messages, then advance clock
    ofm_core::turn::process_day(&mut current_game);

    state.set_game(current_game.clone());
    Ok(current_game)
}

#[tauri::command]
fn set_formation(state: State<StateManager>, formation: String) -> Result<Game, String> {
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game.manager.team_id.clone()
        .ok_or("No team assigned".to_string())?;

    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.formation = formation;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
fn set_play_style(state: State<StateManager>, play_style: String) -> Result<Game, String> {
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game.manager.team_id.clone()
        .ok_or("No team assigned".to_string())?;

    let style = match play_style.as_str() {
        "Attacking" => domain::team::PlayStyle::Attacking,
        "Defensive" => domain::team::PlayStyle::Defensive,
        "Possession" => domain::team::PlayStyle::Possession,
        "Counter" => domain::team::PlayStyle::Counter,
        "HighPress" => domain::team::PlayStyle::HighPress,
        _ => domain::team::PlayStyle::Balanced,
    };

    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.play_style = style;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
fn mark_message_read(state: State<StateManager>, message_id: String) -> Result<Game, String> {
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
        msg.read = true;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
fn resolve_message_action(
    state: State<StateManager>,
    message_id: String,
    action_id: String,
) -> Result<Game, String> {
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
        if let Some(action) = msg.actions.iter_mut().find(|a| a.id == action_id) {
            action.resolved = true;
        }
    }

    state.set_game(game.clone());
    Ok(game)
}

// ---------------------------------------------------------------------------
// Live Match Commands
// ---------------------------------------------------------------------------

/// Start a live match for a given fixture.
/// mode: "live" | "spectator" | "instant"
#[tauri::command]
fn start_live_match(
    state: State<StateManager>,
    fixture_index: usize,
    mode: String,
    allows_extra_time: bool,
) -> Result<engine::MatchSnapshot, String> {
    let game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let match_mode = match mode.as_str() {
        "spectator" => MatchMode::Spectator,
        "instant" => MatchMode::Instant,
        _ => MatchMode::Live,
    };

    let session = live_match_manager::create_live_match(&game, fixture_index, match_mode, allows_extra_time)?;
    let snapshot = session.snapshot();
    state.set_live_match(session);
    Ok(snapshot)
}

/// Step the live match forward by N minutes. Returns the events from each minute.
#[tauri::command]
fn step_live_match(
    state: State<StateManager>,
    minutes: u16,
) -> Result<Vec<engine::MinuteResult>, String> {
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
fn apply_match_command(
    state: State<StateManager>,
    command: engine::MatchCommand,
) -> Result<engine::MatchSnapshot, String> {
    state
        .with_live_match(|session| {
            session.apply_command(command)?;
            Ok(session.snapshot())
        })
        .ok_or_else(|| "No active live match".to_string())?
}

/// Get current match snapshot without advancing time.
#[tauri::command]
fn get_match_snapshot(
    state: State<StateManager>,
) -> Result<engine::MatchSnapshot, String> {
    state
        .with_live_match(|session| session.snapshot())
        .ok_or_else(|| "No active live match".to_string())
}

/// Finish the live match: generate report, update game state, clean up.
#[tauri::command]
fn finish_live_match(
    state: State<StateManager>,
) -> Result<Game, String> {
    let session = state
        .take_live_match()
        .ok_or("No active live match")?;

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

    state.set_game(game.clone());
    Ok(game)
}

/// Advance time with a specific match mode.
/// mode: "live" | "spectator" | "delegate" | "instant"
/// If mode is "live" or "spectator" and there's a user match today,
/// it sets up the live match session instead of auto-simulating.
#[tauri::command]
fn advance_time_with_mode(
    state: State<StateManager>,
    mode: String,
) -> Result<serde_json::Value, String> {
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
                "snapshot": snapshot
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(StateManager::new())
        .invoke_handler(tauri::generate_handler![
            start_new_game,
            select_team,
            get_saves,
            load_game,
            get_active_game,
            advance_time,
            advance_time_with_mode,
            set_formation,
            set_play_style,
            mark_message_read,
            resolve_message_action,
            start_live_match,
            step_live_match,
            apply_match_command,
            get_match_snapshot,
            finish_live_match
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
