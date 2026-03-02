use log::{info, warn, debug};
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
    info!("[cmd] list_world_databases");
    use ofm_core::generator::WorldDatabaseInfo;

    // Always include the built-in random option
    let mut databases = vec![WorldDatabaseInfo {
        id: "random".to_string(),
        name: "Random World".to_string(),
        description: "Randomly generated league with 16 teams across Europe".to_string(),
        team_count: 16,
        player_count: 352,
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
    info!("[cmd] start_new_game: {} {} (nationality={}, world_source={:?})", first_name, last_name, nationality, world_source);
    // Validate inputs
    let first_name = first_name.trim().to_string();
    let last_name = last_name.trim().to_string();
    if first_name.is_empty() || last_name.is_empty() {
        return Err("First name and last name are required.".to_string());
    }
    let nationality = nationality.trim().to_string();
    if nationality.is_empty() {
        return Err("Nationality is required.".to_string());
    }

    // Validate DOB: must be a valid date and manager must be at least 30 years old
    let birth_date = chrono::NaiveDate::parse_from_str(&dob, "%Y-%m-%d")
        .map_err(|_| "Invalid date of birth. Use YYYY-MM-DD format.".to_string())?;
    let today = chrono::Utc::now().date_naive();
    let age = today.signed_duration_since(birth_date).num_days() / 365;
    if age < 30 {
        return Err("Manager must be at least 30 years old.".to_string());
    }
    if age > 99 {
        return Err("Invalid date of birth.".to_string());
    }

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
        ofm_core::generator::generate_world(None)
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

    info!("[cmd] start_new_game: world generated with {} teams, {} players, {} staff", new_game.teams.len(), new_game.players.len(), new_game.staff.len());
    state.set_game(new_game.clone());
    Ok(new_game)
}

/// Export the current world data to a JSON file so it can be shared/reused.
#[tauri::command]
fn export_world_database(
    state: State<StateManager>,
    export_path: String,
) -> Result<String, String> {
    info!("[cmd] export_world_database: path={}", export_path);
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
    info!("[cmd] write_temp_database: json_len={}", json.len());
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
    info!("[cmd] select_team: team_id={}", team_id);
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

    let staff_msg = ofm_core::messages::staff_advice_message(&team_name, &team_id, &date_str);
    game.messages.push(staff_msg);

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
    debug!("[cmd] get_saves");
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
    info!("[cmd] delete_save: save_id={}", save_id);
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
    info!("[cmd] load_game: save_id={}", save_id);
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
    debug!("[cmd] get_active_game");
    state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())
}

#[tauri::command]
fn advance_time(state: State<StateManager>) -> Result<Game, String> {
    let mut current_game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    info!("[cmd] advance_time: date={}", current_game.clock.current_date.format("%Y-%m-%d"));
    // Process a full day: matchday simulation, training, messages, then advance clock
    ofm_core::turn::process_day(&mut current_game);

    state.set_game(current_game.clone());
    Ok(current_game)
}

#[tauri::command]
fn set_formation(state: State<StateManager>, formation: String) -> Result<Game, String> {
    info!("[cmd] set_formation: {}", formation);
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
fn set_starting_xi(state: State<StateManager>, player_ids: Vec<String>) -> Result<Game, String> {
    info!("[cmd] set_starting_xi: {} players", player_ids.len());
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game.manager.team_id.clone()
        .ok_or("No team assigned".to_string())?;

    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.starting_xi_ids = player_ids;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
fn set_play_style(state: State<StateManager>, play_style: String) -> Result<Game, String> {
    info!("[cmd] set_play_style: {}", play_style);
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
    info!("[cmd] set_training: focus={}, intensity={}", focus, intensity);
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
    info!("[cmd] set_training_schedule: {}", schedule);
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
    info!("[cmd] hire_staff: staff_id={}", staff_id);
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
    info!("[cmd] release_staff: staff_id={}", staff_id);
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
    debug!("[cmd] mark_message_read: {}", message_id);
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
fn mark_all_messages_read(state: State<StateManager>) -> Result<Game, String> {
    debug!("[cmd] mark_all_messages_read");
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    for msg in game.messages.iter_mut() {
        msg.read = true;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
fn clear_old_messages(state: State<StateManager>) -> Result<Game, String> {
    debug!("[cmd] clear_old_messages");
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let current_date = game.clock.current_date.format("%Y-%m-%d").to_string();
    // Keep only: unread messages, messages with unresolved actions, and messages from recent 14 days
    game.messages.retain(|m| {
        if !m.read { return true; }
        if m.actions.iter().any(|a| !a.resolved) { return true; }
        // Keep recent messages (within 14 days)
        if let Ok(msg_date) = chrono::NaiveDate::parse_from_str(&m.date, "%Y-%m-%d") {
            if let Ok(cur_date) = chrono::NaiveDate::parse_from_str(&current_date, "%Y-%m-%d") {
                return (cur_date - msg_date).num_days() <= 14;
            }
        }
        false
    });

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
fn save_game(state: State<StateManager>, app_handle: tauri::AppHandle) -> Result<(), String> {
    info!("[cmd] save_game");
    let game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

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

    let saves = db_manager.get_saves().unwrap_or_default();
    if let Some(existing) = saves.first() {
        db_manager.update_save(&existing.id, &game_json)?;
    } else {
        db_manager.create_save(&save_name, &manager_name, &game_json)?;
    }
    Ok(())
}

#[tauri::command]
fn auto_select_set_pieces(
    state: State<StateManager>,
    player_ids: Vec<String>,
) -> Result<serde_json::Value, String> {
    debug!("[cmd] auto_select_set_pieces: {} players", player_ids.len());
    let game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let (captain, penalty, free_kick, corner) =
        ofm_core::live_match_manager::auto_select_set_pieces(&game, &player_ids);

    Ok(serde_json::json!({
        "captain": captain,
        "penalty_taker": penalty,
        "free_kick_taker": free_kick,
        "corner_taker": corner,
    }))
}

#[tauri::command]
fn toggle_transfer_list(
    state: State<StateManager>,
    player_id: String,
) -> Result<Game, String> {
    info!("[cmd] toggle_transfer_list: player_id={}", player_id);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    if let Some(p) = game.players.iter_mut().find(|p| p.id == player_id) {
        p.transfer_listed = !p.transfer_listed;
    } else {
        return Err("Player not found".into());
    }
    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
fn toggle_loan_list(
    state: State<StateManager>,
    player_id: String,
) -> Result<Game, String> {
    info!("[cmd] toggle_loan_list: player_id={}", player_id);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    if let Some(p) = game.players.iter_mut().find(|p| p.id == player_id) {
        p.loan_listed = !p.loan_listed;
    } else {
        return Err("Player not found".into());
    }
    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
fn make_transfer_bid(
    state: State<StateManager>,
    player_id: String,
    fee: u64,
) -> Result<serde_json::Value, String> {
    info!("[cmd] make_transfer_bid: player_id={}, fee={}", player_id, fee);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let result = ofm_core::transfers::make_transfer_bid(&mut game, &player_id, fee)?;
    state.set_game(game.clone());

    Ok(serde_json::json!({
        "result": result,
        "game": game,
    }))
}

#[tauri::command]
fn respond_to_offer(
    state: State<StateManager>,
    player_id: String,
    offer_id: String,
    accept: bool,
) -> Result<Game, String> {
    info!("[cmd] respond_to_offer: player_id={}, offer_id={}, accept={}", player_id, offer_id, accept);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    ofm_core::transfers::respond_to_offer(&mut game, &player_id, &offer_id, accept)?;
    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
fn send_scout(
    state: State<StateManager>,
    scout_id: String,
    player_id: String,
) -> Result<Game, String> {
    info!("[cmd] send_scout: scout_id={}, player_id={}", scout_id, player_id);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    ofm_core::scouting::send_scout(&mut game, &scout_id, &player_id)?;
    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
fn check_season_complete(
    state: State<StateManager>,
) -> Result<bool, String> {
    debug!("[cmd] check_season_complete");
    let game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;
    Ok(ofm_core::end_of_season::is_season_complete(&game))
}

#[tauri::command]
fn advance_to_next_season(
    state: State<StateManager>,
) -> Result<serde_json::Value, String> {
    info!("[cmd] advance_to_next_season");
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    if !ofm_core::end_of_season::is_season_complete(&game) {
        return Err("Season is not yet complete".to_string());
    }

    let summary = ofm_core::end_of_season::process_end_of_season(&mut game);
    state.set_game(game.clone());
    Ok(serde_json::json!({
        "game": game,
        "summary": summary,
    }))
}

#[tauri::command]
fn get_season_awards(
    state: State<StateManager>,
) -> Result<ofm_core::season_awards::SeasonAwards, String> {
    debug!("[cmd] get_season_awards");
    let game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;
    Ok(ofm_core::season_awards::compute_season_awards(&game))
}

#[tauri::command]
fn resolve_message_action(
    state: State<StateManager>,
    message_id: String,
    action_id: String,
    option_id: Option<String>,
) -> Result<serde_json::Value, String> {
    info!("[cmd] resolve_message_action: msg={}, action={}, option={:?}", message_id, action_id, option_id);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    // Try to apply player conversation or random event response
    let effect = if let Some(opt) = &option_id {
        // Try player events first, then random events
        let player_effect = ofm_core::player_events::apply_player_response(&mut game, &message_id, &action_id, opt);
        if player_effect.is_some() {
            player_effect
        } else {
            ofm_core::random_events::apply_event_response(&mut game, &message_id, &action_id, opt)
        }
    } else {
        // Standard resolve — just mark action as resolved
        if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
            if let Some(action) = msg.actions.iter_mut().find(|a| a.id == action_id) {
                action.resolved = true;
            }
        }
        None
    };

    state.set_game(game.clone());
    Ok(serde_json::json!({
        "game": game,
        "effect": effect
    }))
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
    info!("[cmd] start_live_match: fixture={}, mode={}, extra_time={}", fixture_index, mode, allows_extra_time);
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
    debug!("[cmd] step_live_match: minutes={}", minutes);
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
fn get_match_snapshot(
    state: State<StateManager>,
) -> Result<engine::MatchSnapshot, String> {
    debug!("[cmd] get_match_snapshot");
    state
        .with_live_match(|session| session.snapshot())
        .ok_or_else(|| "No active live match".to_string())
}

/// Finish the live match: generate report, update game state, clean up.
#[tauri::command]
fn finish_live_match(
    state: State<StateManager>,
) -> Result<Game, String> {
    info!("[cmd] finish_live_match");
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
    info!("[cmd] apply_team_talk: tone={}, context={}", tone, context);
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

/// Process press conference answers: generate news article, affect squad morale.
/// answers: array of { question_id, response_id, response_tone, response_text, question_text }
#[tauri::command]
fn submit_press_conference(
    state: State<StateManager>,
    answers: Vec<serde_json::Value>,
    home_team: String,
    away_team: String,
    home_score: u8,
    away_score: u8,
    user_team_name: String,
    user_team_id: String,
) -> Result<serde_json::Value, String> {
    info!("[cmd] submit_press_conference: {} {} - {} {}", home_team, home_score, away_score, away_team);
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
        let tone = answer.get("response_tone").and_then(|v| v.as_str()).unwrap_or("");
        let text = answer.get("response_text").and_then(|v| v.as_str()).unwrap_or("");
        let qid = answer.get("question_id").and_then(|v| v.as_str()).unwrap_or("");

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
    let result_str = format!("{} {} - {} {}", home_team, home_score, away_score, away_team);
    let headline = if quotes.is_empty() {
        format!("Post-Match: {} on {}", user_team_name, result_str)
    } else {
        let sources = [
            format!("{} Manager: {}", user_team_name, quotes[0]),
            format!("Press Conference: \"{}\" — {} boss", quotes[0].trim_matches('"'), user_team_name),
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

/// Check for blocking actions that should be resolved before advancing.
/// Returns a JSON array of blocking issues.
#[tauri::command]
fn check_blocking_actions(state: State<StateManager>) -> Result<serde_json::Value, String> {
    debug!("[cmd] check_blocking_actions");
    let game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let blockers = compute_blocking_actions(&game);
    Ok(serde_json::json!(blockers))
}

/// Compute blocking actions for the current game state.
fn compute_blocking_actions(game: &Game) -> Vec<serde_json::Value> {
    let mut blockers = Vec::new();
    let user_team_id = match &game.manager.team_id {
        Some(id) => id,
        None => return blockers,
    };

    let team = match game.teams.iter().find(|t| t.id == *user_team_id) {
        Some(t) => t,
        None => return blockers,
    };

    let roster: Vec<_> = game.players.iter().filter(|p| p.team_id.as_deref() == Some(user_team_id)).collect();
    let xi_ids = &team.starting_xi_ids;

    // Check for injured players in XI
    let injured_in_xi: Vec<_> = xi_ids.iter()
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
    let healthy_xi = xi_ids.iter()
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
    let urgent_unread = game.messages.iter()
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

/// Skip forward until the day before the next match for the user's team.
/// Processes each intermediate day normally (training, recovery, messages).
/// If blocking actions arise mid-skip, stops early and returns a "blocked" reason.
#[tauri::command]
fn skip_to_match_day(state: State<StateManager>) -> Result<serde_json::Value, String> {
    info!("[cmd] skip_to_match_day");
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

    info!("[cmd] skip_to_match_day: arrived after {} days", days_skipped);
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
fn advance_time_with_mode(
    state: State<StateManager>,
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
            let mut session = live_match_manager::create_live_match(&game, idx, MatchMode::Instant, false)?;
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

// ---------------------------------------------------------------------------
// Session Management
// ---------------------------------------------------------------------------

/// Save the current game and clear the active session so the player returns to the main menu.
#[tauri::command]
fn exit_to_menu(
    state: State<StateManager>,
    app_handle: tauri::AppHandle,
) -> Result<(), String> {
    info!("[cmd] exit_to_menu");
    let game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    // Auto-save
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

    // Try to update existing save first, create new if none exists
    let saves = db_manager.get_saves().unwrap_or_default();
    if let Some(existing) = saves.first() {
        db_manager.update_save(&existing.id, &game_json)?;
    } else {
        db_manager.create_save(&save_name, &manager_name, &game_json)?;
    }

    // Clear the in-memory game state
    state.clear_game();

    Ok(())
}

// ---------------------------------------------------------------------------
// Settings Commands
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AppSettings {
    pub theme: String,              // "dark" | "light" | "system"
    #[serde(default = "default_language")]
    pub language: String,           // "en" | "es" | "pt" | "fr" | "de"
    pub currency: String,           // "EUR" | "GBP" | "USD"
    pub default_match_mode: String, // "live" | "spectator" | "delegate"
    pub auto_save: bool,
    pub match_speed: String,        // "slow" | "normal" | "fast"
    pub show_match_commentary: bool,
    pub confirm_advance: bool,
    #[serde(default = "default_ui_scale")]
    pub ui_scale: String,  // "small" | "normal" | "large" | "xlarge"
    #[serde(default)]
    pub high_contrast: bool,
}

fn default_language() -> String { "en".to_string() }
fn default_ui_scale() -> String { "normal".to_string() }

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            theme: "dark".to_string(),
            language: "en".to_string(),
            currency: "EUR".to_string(),
            default_match_mode: "live".to_string(),
            auto_save: true,
            match_speed: "normal".to_string(),
            show_match_commentary: true,
            confirm_advance: false,
            ui_scale: "normal".to_string(),
            high_contrast: false,
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
    debug!("[cmd] get_settings");
    let path = settings_path(&app_handle)?;
    if !path.exists() {
        return Ok(AppSettings::default());
    }
    let json = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
    serde_json::from_str(&json).map_err(|e| format!("Failed to parse settings: {}", e))
}

#[tauri::command]
fn save_settings(app_handle: tauri::AppHandle, settings: AppSettings) -> Result<(), String> {
    info!("[cmd] save_settings: theme={}, lang={}", settings.theme, settings.language);
    let path = settings_path(&app_handle)?;
    let json = serde_json::to_string_pretty(&settings).map_err(|e| e.to_string())?;
    std::fs::write(&path, json).map_err(|e| format!("Failed to save settings: {}", e))
}

#[tauri::command]
fn clear_all_saves(app_handle: tauri::AppHandle) -> Result<(), String> {
    warn!("[cmd] clear_all_saves: deleting all save data!");
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
        .plugin(
            tauri_plugin_log::Builder::new()
                .level(log::LevelFilter::Info)
                .level_for("openfootmanager_lib", log::LevelFilter::Debug)
                .level_for("ofm_core", log::LevelFilter::Debug)
                .level_for("engine", log::LevelFilter::Debug)
                .level_for("db", log::LevelFilter::Debug)
                .rotation_strategy(tauri_plugin_log::RotationStrategy::KeepAll)
                .max_file_size(5_000_000) // 5 MB per log file
                .build(),
        )
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
            set_starting_xi,
            set_play_style,
            set_training,
            set_training_schedule,
            hire_staff,
            release_staff,
            mark_message_read,
            mark_all_messages_read,
            clear_old_messages,
            save_game,
            auto_select_set_pieces,
            toggle_transfer_list,
            toggle_loan_list,
            make_transfer_bid,
            respond_to_offer,
            send_scout,
            check_season_complete,
            advance_to_next_season,
            get_season_awards,
            resolve_message_action,
            start_live_match,
            step_live_match,
            apply_match_command,
            get_match_snapshot,
            finish_live_match,
            delete_save,
            skip_to_match_day,
            check_blocking_actions,
            apply_team_talk,
            submit_press_conference,
            exit_to_menu,
            get_settings,
            save_settings,
            clear_all_saves
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
