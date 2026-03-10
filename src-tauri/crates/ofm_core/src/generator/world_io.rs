use super::definitions::{WorldData, WorldDatabaseInfo};

/// Generate a random world and wrap it in a `WorldData`.
/// If `data_dir` is provided, tries to load definition files from that directory.
pub fn generate_world_data(data_dir: Option<&std::path::Path>) -> WorldData {
    let (teams, players, staff) = super::generate_world(data_dir);
    WorldData {
        name: "Random World".to_string(),
        description: format!(
            "Randomly generated league with {} teams across Europe",
            teams.len()
        ),
        teams,
        players,
        staff,
    }
}

/// Parse a JSON string into a `WorldData`.
pub fn load_world_from_json(json: &str) -> Result<WorldData, String> {
    serde_json::from_str(json).map_err(|e| format!("Failed to parse world database: {}", e))
}

/// Serialise a `WorldData` to a pretty-printed JSON string.
pub fn export_world_to_json(world: &WorldData) -> Result<String, String> {
    serde_json::to_string_pretty(world).map_err(|e| format!("Failed to serialise world: {}", e))
}

/// Scan a directory for `.json` world database files and return their metadata.
pub fn scan_world_databases(dir: &std::path::Path) -> Vec<WorldDatabaseInfo> {
    let mut results = Vec::new();
    let Ok(entries) = std::fs::read_dir(dir) else {
        return results;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let Ok(contents) = std::fs::read_to_string(&path) else {
            continue;
        };
        // Parse just enough to get metadata — try full parse
        if let Ok(world) = serde_json::from_str::<WorldData>(&contents) {
            let file_stem = path
                .file_stem()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string();
            results.push(WorldDatabaseInfo {
                id: format!("file:{}", path.display()),
                name: world.name,
                description: world.description,
                team_count: world.teams.len(),
                player_count: world.players.len(),
                source: "user".to_string(),
                path: path.to_string_lossy().to_string(),
            });
            // suppress unused variable warning
            let _ = file_stem;
        }
    }
    results
}
