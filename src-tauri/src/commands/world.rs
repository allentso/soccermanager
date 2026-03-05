use log::info;
use tauri::Manager as TauriManager;
use tauri::State;

use ofm_core::state::StateManager;

/// List available world databases (built-in random + any user JSON files).
#[tauri::command]
pub fn list_world_databases(
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

/// Export the current world data to a JSON file so it can be shared/reused.
#[tauri::command]
pub fn export_world_database(
    state: State<StateManager>,
    export_path: String,
) -> Result<String, String> {
    info!("[cmd] export_world_database: path={}", export_path);
    let game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let world = ofm_core::generator::WorldData {
        name: "Exported World".to_string(),
        description: format!(
            "World with {} teams exported from saved game",
            game.teams.len()
        ),
        teams: game.teams.clone(),
        players: game.players.clone(),
        staff: game.staff.clone(),
    };

    let json = ofm_core::generator::export_world_to_json(&world)?;
    std::fs::write(&export_path, &json).map_err(|e| format!("Failed to write file: {}", e))?;
    Ok(export_path)
}

/// Write imported world database JSON to the user's databases directory.
/// Returns the full path so the frontend can pass it to start_new_game.
#[tauri::command]
pub fn write_temp_database(app_handle: tauri::AppHandle, json: String) -> Result<String, String> {
    info!("[cmd] write_temp_database: json_len={}", json.len());
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?;
    let db_dir = app_data_dir.join("databases");
    std::fs::create_dir_all(&db_dir).map_err(|e| e.to_string())?;

    // Generate a unique filename
    let filename = format!(
        "imported_{}.json",
        chrono::Utc::now().format("%Y%m%d_%H%M%S")
    );
    let path = db_dir.join(&filename);
    std::fs::write(&path, &json).map_err(|e| format!("Failed to write database: {}", e))?;
    Ok(path.to_string_lossy().to_string())
}
