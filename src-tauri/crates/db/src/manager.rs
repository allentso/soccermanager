use rusqlite::{Connection, Result};
use std::path::PathBuf;

pub struct DbManager {
    conn: Connection,
}

impl DbManager {
    /// Initialize the main saves database
    pub fn new(db_path: PathBuf) -> Result<Self> {
        let conn = Connection::open(&db_path)?;
        let mut manager = Self { conn };
        manager.run_migrations()?;
        Ok(manager)
    }

    fn run_migrations(&mut self) -> Result<()> {
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS saves (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                manager_name TEXT NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                last_played_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                game_data TEXT NOT NULL 
            )",
            [],
        )?;
        Ok(())
    }

    pub fn create_save(&self, name: &str, manager_name: &str, game_data_json: &str) -> Result<i64> {
        self.conn.execute(
            "INSERT INTO saves (name, manager_name, game_data) VALUES (?1, ?2, ?3)",
            (name, manager_name, game_data_json),
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    pub fn get_saves(&self) -> Result<Vec<(i64, String, String, String, String)>> {
        let mut stmt = self.conn.prepare("SELECT id, name, manager_name, created_at, last_played_at FROM saves ORDER BY last_played_at DESC")?;
        let saves_iter = stmt.query_map([], |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
            ))
        })?;

        let mut saves = Vec::new();
        for save in saves_iter {
            saves.push(save?);
        }
        Ok(saves)
    }

    pub fn load_save(&self, id: i64) -> Result<String> {
        let mut stmt = self
            .conn
            .prepare("SELECT game_data FROM saves WHERE id = ?1")?;
        let mut rows = stmt.query([id])?;
        if let Some(row) = rows.next()? {
            Ok(row.get(0)?)
        } else {
            Err(rusqlite::Error::QueryReturnedNoRows)
        }
    }
}
