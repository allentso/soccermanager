use log::{info, debug, warn, error};
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Lightweight metadata returned when listing saves (no game data).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SaveMetadata {
    pub id: String,
    pub name: String,
    pub manager_name: String,
    pub created_at: String,
    pub last_played_at: String,
}

/// SQLite-based save manager. All saves are stored in a single `saves.db`
/// database with a `saves` table.
pub struct DbManager {
    conn: Connection,
}

impl DbManager {
    /// Open (or create) the SQLite database at the given path
    /// and ensure the saves table exists with the correct schema.
    pub fn new(db_path: PathBuf) -> Result<Self, String> {
        debug!("[db] opening database at {:?}", db_path);
        let conn = Connection::open(&db_path)
            .map_err(|e| {
                error!("[db] failed to open database at {:?}: {}", db_path, e);
                format!("Failed to open database: {}", e)
            })?;

        // Check if the saves table exists with the old INTEGER id schema
        // and migrate to the new TEXT id schema if needed.
        let needs_migration = conn
            .query_row(
                "SELECT type FROM pragma_table_info('saves') WHERE name = 'id'",
                [],
                |row| row.get::<_, String>(0),
            )
            .ok()
            .map_or(false, |col_type| col_type.to_uppercase() != "TEXT");

        if needs_migration {
            warn!("[db] migrating old INTEGER id schema to TEXT");
            conn.execute_batch("DROP TABLE IF EXISTS saves;")
                .map_err(|e| format!("Failed to drop old saves table: {}", e))?;
        }

        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS saves (
                id              TEXT PRIMARY KEY,
                name            TEXT NOT NULL,
                manager_name    TEXT NOT NULL,
                game_data       TEXT NOT NULL,
                created_at      TEXT NOT NULL DEFAULT (datetime('now')),
                last_played_at  TEXT NOT NULL DEFAULT (datetime('now'))
            );"
        )
        .map_err(|e| format!("Failed to create saves table: {}", e))?;

        Ok(Self { conn })
    }

    /// Create a new save. Returns the generated UUID save id.
    pub fn create_save(
        &self,
        name: &str,
        manager_name: &str,
        game_data: &str,
    ) -> Result<String, String> {
        let id = uuid::Uuid::new_v4().to_string();
        info!("[db] create_save: id={}, name='{}', data_len={}", id, name, game_data.len());

        self.conn
            .execute(
                "INSERT INTO saves (id, name, manager_name, game_data) VALUES (?1, ?2, ?3, ?4)",
                params![id, name, manager_name, game_data],
            )
            .map_err(|e| format!("Failed to create save: {}", e))?;

        Ok(id)
    }

    /// Update an existing save's game data and bump last_played_at.
    pub fn update_save(&self, id: &str, game_data: &str) -> Result<(), String> {
        info!("[db] update_save: id={}, data_len={}", id, game_data.len());
        let rows = self
            .conn
            .execute(
                "UPDATE saves SET game_data = ?1, last_played_at = datetime('now') WHERE id = ?2",
                params![game_data, id],
            )
            .map_err(|e| format!("Failed to update save: {}", e))?;

        if rows == 0 {
            return Err(format!("Save not found: {}", id));
        }
        Ok(())
    }

    /// List all saves ordered by most recently played (metadata only).
    pub fn get_saves(&self) -> Result<Vec<SaveMetadata>, String> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, name, manager_name, created_at, last_played_at FROM saves ORDER BY last_played_at DESC")
            .map_err(|e| format!("Failed to prepare query: {}", e))?;

        let rows = stmt
            .query_map([], |row| {
                Ok(SaveMetadata {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    manager_name: row.get(2)?,
                    created_at: row.get(3)?,
                    last_played_at: row.get(4)?,
                })
            })
            .map_err(|e| format!("Failed to query saves: {}", e))?;

        let mut saves = Vec::new();
        for row in rows {
            saves.push(row.map_err(|e| format!("Failed to read row: {}", e))?);
        }
        Ok(saves)
    }

    /// Load the full game data JSON string for a given save id.
    pub fn load_save(&self, id: &str) -> Result<String, String> {
        info!("[db] load_save: id={}", id);
        self.conn
            .query_row(
                "SELECT game_data FROM saves WHERE id = ?1",
                params![id],
                |row| row.get(0),
            )
            .map_err(|e| format!("Failed to load save ({}): {}", id, e))
    }

    /// Delete a save by id. Returns true if a row was deleted.
    pub fn delete_save(&self, id: &str) -> Result<bool, String> {
        warn!("[db] delete_save: id={}", id);
        let rows = self
            .conn
            .execute("DELETE FROM saves WHERE id = ?1", params![id])
            .map_err(|e| format!("Failed to delete save: {}", e))?;
        Ok(rows > 0)
    }
}
