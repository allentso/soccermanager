use tauri::Manager as TauriManager;
use tauri::State;

use db::manager::{DbManager, SaveMetadata};
use domain::manager::Manager;
use ofm_core::clock::GameClock;
use ofm_core::game::Game;
use ofm_core::live_match_manager::{self, MatchMode};
use ofm_core::state::StateManager;
use rand::Rng;

/// List available world databases (built-in random + any user JSON files).
#[tauri::command]
fn list_world_databases(
    app_handle: tauri::AppHandle,
) -> Result<Vec<ofm_core::generator::WorldDatabaseInfo>, String> {
    use ofm_core::generator::WorldDatabaseInfo;

    // Always include the built-in random option
    let mut databases = vec![WorldDatabaseInfo {
        id: "random".to_string(),
        name: "Random World".to_string(),
        description: "Randomly generated league with 8 teams, players, and staff".to_string(),
        team_count: 8,
        player_count: 160,
        source: "builtin".to_string(),
        path: String::new(),
    }];

    // Scan bundled databases directory (next to the executable / in resources)
    if let Ok(resource_dir) = app_handle.path().resource_dir() {
        let bundled_dir = resource_dir.join("databases");
        let mut bundled = ofm_core::generator::scan_world_databases(&bundled_dir);
        for db in &mut bundled {
            db.source = "builtin".to_string();
        }
        databases.extend(bundled);
    }

    // Scan user databases directory in app data
    if let Ok(app_data_dir) = app_handle.path().app_data_dir() {
        let user_dir = app_data_dir.join("databases");
        let user_dbs = ofm_core::generator::scan_world_databases(&user_dir);
        databases.extend(user_dbs);
    }

    Ok(databases)
}

/// Step 1: Create manager + generate world. No team assigned yet.
/// Returns the Game object so the frontend can show team selection.
/// world_source: "random" (default) or a file path to a JSON world database.
#[tauri::command]
fn start_new_game(
    state: State<StateManager>,
    first_name: String,
    last_name: String,
    dob: String,
    nationality: String,
    world_source: Option<String>,
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

    // Load world based on source
    let world_source = world_source.unwrap_or_else(|| "random".to_string());
    let (teams, players, staff) = if world_source == "random" {
        ofm_core::generator::generate_world()
    } else {
        // Try to load from file path (strip "file:" prefix if present)
        let path = world_source.strip_prefix("file:").unwrap_or(&world_source);
        let json = std::fs::read_to_string(path)
            .map_err(|e| format!("Failed to read world database: {}", e))?;
        let world = ofm_core::generator::load_world_from_json(&json)?;
        (world.teams, world.players, world.staff)
    };

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

/// Export the current world data to a JSON file so it can be shared/reused.
#[tauri::command]
fn export_world_database(
    state: State<StateManager>,
    export_path: String,
) -> Result<String, String> {
    let game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let world = ofm_core::generator::WorldData {
        name: "Exported World".to_string(),
        description: format!("World with {} teams exported from saved game", game.teams.len()),
        teams: game.teams.clone(),
        players: game.players.clone(),
        staff: game.staff.clone(),
    };

    let json = ofm_core::generator::export_world_to_json(&world)?;
    std::fs::write(&export_path, &json)
        .map_err(|e| format!("Failed to write file: {}", e))?;
    Ok(export_path)
}

/// Write imported world database JSON to the user's databases directory.
/// Returns the full path so the frontend can pass it to start_new_game.
#[tauri::command]
fn write_temp_database(
    app_handle: tauri::AppHandle,
    json: String,
) -> Result<String, String> {
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?;
    let db_dir = app_data_dir.join("databases");
    std::fs::create_dir_all(&db_dir).map_err(|e| e.to_string())?;

    // Generate a unique filename
    let filename = format!("imported_{}.json", chrono::Utc::now().format("%Y%m%d_%H%M%S"));
    let path = db_dir.join(&filename);
    std::fs::write(&path, &json).map_err(|e| format!("Failed to write database: {}", e))?;
    Ok(path.to_string_lossy().to_string())
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
        .create_save(&save_name, &manager_name, &game_json)?;

    state.set_game(game.clone());
    Ok(game)
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
    db_manager.get_saves()
}

#[tauri::command]
fn delete_save(app_handle: tauri::AppHandle, save_id: String) -> Result<bool, String> {
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?;
    let db_path = app_data_dir.join("saves.db");
    if !db_path.exists() {
        return Err("No saves database found".to_string());
    }
    let db_manager = DbManager::new(db_path).map_err(|e| e.to_string())?;
    db_manager.delete_save(&save_id)
}

#[tauri::command]
fn load_game(
    state: State<StateManager>,
    app_handle: tauri::AppHandle,
    save_id: String,
) -> Result<String, String> {
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?;
    let db_path = app_data_dir.join("saves.db");
    let db_manager = DbManager::new(db_path).map_err(|e| e.to_string())?;

    let game_json = db_manager.load_save(&save_id)?;
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

    // Parse formation into (def, mid, fwd) counts
    let parts: Vec<usize> = formation.split('-').filter_map(|s| s.parse().ok()).collect();
    let (num_def, num_mid, num_fwd) = match parts.len() {
        3 => (parts[0], parts[1], parts[2]),
        4 => (parts[0], parts[1] + parts[2], parts[3]),
        _ => (4, 4, 2),
    };

    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.formation = formation;
    }

    // Reassign positions for outfield players on this team
    let player_ids: Vec<String> = game.players.iter()
        .filter(|p| p.team_id.as_deref() == Some(&team_id) && p.position != domain::player::Position::Goalkeeper)
        .map(|p| p.id.clone())
        .collect();

    // Sort by defensive ability (most defensive first)
    let mut sorted_ids = player_ids.clone();
    sorted_ids.sort_by(|a_id, b_id| {
        let pa = game.players.iter().find(|p| p.id == *a_id).unwrap();
        let pb = game.players.iter().find(|p| p.id == *b_id).unwrap();
        let def_a = pa.attributes.defending as u16 + pa.attributes.tackling as u16 + pa.attributes.strength as u16;
        let def_b = pb.attributes.defending as u16 + pb.attributes.tackling as u16 + pb.attributes.strength as u16;
        def_b.cmp(&def_a)
    });

    // Assign positions
    for (slot, pid) in sorted_ids.iter().enumerate() {
        let new_pos = if slot < num_def {
            domain::player::Position::Defender
        } else if slot < num_def + num_mid {
            domain::player::Position::Midfielder
        } else if slot < num_def + num_mid + num_fwd {
            domain::player::Position::Forward
        } else {
            continue;
        };
        if let Some(player) = game.players.iter_mut().find(|p| p.id == *pid) {
            player.position = new_pos;
        }
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
fn set_training(
    state: State<StateManager>,
    focus: String,
    intensity: String,
) -> Result<Game, String> {
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game.manager.team_id.clone()
        .ok_or("No team assigned".to_string())?;

    let training_focus = match focus.as_str() {
        "Physical" => domain::team::TrainingFocus::Physical,
        "Technical" => domain::team::TrainingFocus::Technical,
        "Tactical" => domain::team::TrainingFocus::Tactical,
        "Defending" => domain::team::TrainingFocus::Defending,
        "Attacking" => domain::team::TrainingFocus::Attacking,
        "Recovery" => domain::team::TrainingFocus::Recovery,
        _ => domain::team::TrainingFocus::Physical,
    };

    let training_intensity = match intensity.as_str() {
        "Low" => domain::team::TrainingIntensity::Low,
        "Medium" => domain::team::TrainingIntensity::Medium,
        "High" => domain::team::TrainingIntensity::High,
        _ => domain::team::TrainingIntensity::Medium,
    };

    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.training_focus = training_focus;
        team.training_intensity = training_intensity;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
fn set_training_schedule(
    state: State<StateManager>,
    schedule: String,
) -> Result<Game, String> {
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game.manager.team_id.clone()
        .ok_or("No team assigned".to_string())?;

    let training_schedule = match schedule.as_str() {
        "Intense" => domain::team::TrainingSchedule::Intense,
        "Balanced" => domain::team::TrainingSchedule::Balanced,
        "Light" => domain::team::TrainingSchedule::Light,
        _ => domain::team::TrainingSchedule::Balanced,
    };

    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.training_schedule = training_schedule;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
fn hire_staff(state: State<StateManager>, staff_id: String) -> Result<Game, String> {
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game.manager.team_id.clone()
        .ok_or("No team assigned".to_string())?;

    let staff = game.staff.iter_mut().find(|s| s.id == staff_id)
        .ok_or("Staff member not found".to_string())?;

    if staff.team_id.is_some() {
        return Err("Staff member already employed by a team".to_string());
    }

    staff.team_id = Some(team_id.clone());

    // Deduct wage from team budget
    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.season_expenses += staff.wage as i64;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
fn release_staff(state: State<StateManager>, staff_id: String) -> Result<Game, String> {
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game.manager.team_id.clone()
        .ok_or("No team assigned".to_string())?;

    let staff = game.staff.iter_mut().find(|s| s.id == staff_id)
        .ok_or("Staff member not found".to_string())?;

    if staff.team_id.as_deref() != Some(&team_id) {
        return Err("Staff member does not belong to your team".to_string());
    }

    staff.team_id = None;

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

    // Complete the day: generate pre-match messages for upcoming fixtures, then advance the clock
    ofm_core::turn::finish_live_match_day(&mut game);

    state.set_game(game.clone());
    Ok(game)
}

/// Apply a team talk and return per-player morale changes.
/// tone: "calm" | "motivational" | "assertive" | "aggressive" | "praise" | "disappointed"
/// context: "winning" | "losing" | "drawing"
#[tauri::command]
fn apply_team_talk(
    state: State<StateManager>,
    tone: String,
    context: String,
) -> Result<Vec<serde_json::Value>, String> {
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let user_team_id = game
        .manager
        .team_id
        .clone()
        .ok_or("No team assigned")?;

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

/// Skip forward until the day before the next match for the user's team.
/// Processes each intermediate day normally (training, recovery, messages).
/// Returns the updated game state.
#[tauri::command]
fn skip_to_match_day(state: State<StateManager>) -> Result<Game, String> {
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let user_team_id = game
        .manager
        .team_id
        .clone()
        .ok_or("No team assigned")?;

    // Advance up to 60 days (safety limit)
    let mut days_skipped = 0u32;
    loop {
        if days_skipped >= 60 {
            break;
        }

        let today = game.clock.current_date.format("%Y-%m-%d").to_string();

        // Check if user has a match today
        let has_match = game.league.as_ref().map_or(false, |league| {
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
    }

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

// ---------------------------------------------------------------------------
// Settings Commands
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AppSettings {
    pub theme: String,              // "dark" | "light" | "system"
    pub currency: String,           // "EUR" | "GBP" | "USD"
    pub default_match_mode: String, // "live" | "spectator" | "delegate"
    pub auto_save: bool,
    pub match_speed: String,        // "slow" | "normal" | "fast"
    pub show_match_commentary: bool,
    pub confirm_advance: bool,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            theme: "dark".to_string(),
            currency: "EUR".to_string(),
            default_match_mode: "live".to_string(),
            auto_save: true,
            match_speed: "normal".to_string(),
            show_match_commentary: true,
            confirm_advance: false,
        }
    }
}

fn settings_path(app_handle: &tauri::AppHandle) -> Result<std::path::PathBuf, String> {
    let dir = app_handle.path().app_data_dir().map_err(|e| e.to_string())?;
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("settings.json"))
}

#[tauri::command]
fn get_settings(app_handle: tauri::AppHandle) -> Result<AppSettings, String> {
    let path = settings_path(&app_handle)?;
    if !path.exists() {
        return Ok(AppSettings::default());
    }
    let json = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
    serde_json::from_str(&json).map_err(|e| format!("Failed to parse settings: {}", e))
}

#[tauri::command]
fn save_settings(app_handle: tauri::AppHandle, settings: AppSettings) -> Result<(), String> {
    let path = settings_path(&app_handle)?;
    let json = serde_json::to_string_pretty(&settings).map_err(|e| e.to_string())?;
    std::fs::write(&path, json).map_err(|e| format!("Failed to save settings: {}", e))
}

#[tauri::command]
fn clear_all_saves(app_handle: tauri::AppHandle) -> Result<(), String> {
    let app_data_dir = app_handle.path().app_data_dir().map_err(|e| e.to_string())?;
    let db_path = app_data_dir.join("saves.db");
    if db_path.exists() {
        std::fs::remove_file(&db_path).map_err(|e| format!("Failed to delete saves: {}", e))?;
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(StateManager::new())
        .invoke_handler(tauri::generate_handler![
            list_world_databases,
            start_new_game,
            export_world_database,
            write_temp_database,
            select_team,
            get_saves,
            load_game,
            get_active_game,
            advance_time,
            advance_time_with_mode,
            set_formation,
            set_play_style,
            set_training,
            set_training_schedule,
            hire_staff,
            release_staff,
            mark_message_read,
            resolve_message_action,
            start_live_match,
            step_live_match,
            apply_match_command,
            get_match_snapshot,
            finish_live_match,
            delete_save,
            skip_to_match_day,
            apply_team_talk,
            get_settings,
            save_settings,
            clear_all_saves
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
