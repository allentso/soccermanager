use chrono::Utc;
use log::{debug, info, warn};
use std::fs;
use std::path::{Path, PathBuf};

use ofm_core::clock::GameClock;
use ofm_core::game::{BoardObjective, Game, ObjectiveType, ScoutingAssignment};

use crate::game_database::GameDatabase;
use crate::repositories::{
    league_repo, manager_repo, message_repo, meta_repo, news_repo, objective_repo, player_repo,
    scouting_repo, staff_repo, team_repo,
};
use crate::save_index::{
    self, SaveEntry, SaveIndex, compute_checksum, load_or_rebuild_index, write_index,
};

/// Manages save sessions: creating, loading, saving, deleting, and listing.
pub struct SaveManager {
    saves_dir: PathBuf,
    index_path: PathBuf,
    index: SaveIndex,
}

impl SaveManager {
    /// Initialize the SaveManager, loading or rebuilding the save index.
    pub fn init(saves_dir: &Path) -> Result<Self, String> {
        fs::create_dir_all(saves_dir)
            .map_err(|e| format!("Failed to create saves directory: {}", e))?;

        let index_path = saves_dir.join("save_index.json");
        let (index, validations) = load_or_rebuild_index(&index_path, saves_dir)?;

        for v in &validations {
            if let save_index::DbValidation::Invalid { filename, reason } = v {
                warn!(
                    "[save_manager] invalid database during init: {} — {}",
                    filename, reason
                );
            }
        }

        info!(
            "[save_manager] initialized with {} saves",
            index.saves.len()
        );

        Ok(Self {
            saves_dir: saves_dir.to_path_buf(),
            index_path,
            index,
        })
    }

    /// List all save entries.
    pub fn list_saves(&self) -> &[SaveEntry] {
        &self.index.saves
    }

    /// Create a new save from the current in-memory Game state.
    /// Returns the save_id.
    pub fn create_save(&mut self, game: &Game, save_name: &str) -> Result<String, String> {
        let save_id = uuid::Uuid::new_v4().to_string();
        let db_filename = format!("{}.db", save_id);
        let db_path = self.saves_dir.join(&db_filename);

        debug!("[save_manager] creating save {} at {:?}", save_id, db_path);

        let db = GameDatabase::open(&db_path)?;
        self.write_game_to_db(&db, game, &save_id, save_name)?;
        drop(db);

        let checksum = compute_checksum(&db_path)?;
        let now = Utc::now().to_rfc3339();
        let manager_name = format!("{} {}", game.manager.first_name, game.manager.last_name);

        let entry = SaveEntry {
            id: save_id.clone(),
            name: save_name.to_string(),
            manager_name,
            db_filename,
            checksum,
            created_at: now.clone(),
            last_played_at: now,
        };

        self.index.add(entry);
        write_index(&self.index_path, &self.index)?;

        info!("[save_manager] created save {}", save_id);
        Ok(save_id)
    }

    /// Save the current Game state to an existing save.
    pub fn save_game(&mut self, game: &Game, save_id: &str) -> Result<(), String> {
        let entry = self
            .index
            .find(save_id)
            .ok_or_else(|| format!("Save '{}' not found", save_id))?;

        let db_path = self.saves_dir.join(&entry.db_filename);
        let save_name = entry.name.clone();

        debug!("[save_manager] saving game to {}", save_id);

        let db = GameDatabase::open(&db_path)?;
        self.write_game_to_db(&db, game, save_id, &save_name)?;
        drop(db);

        let checksum = compute_checksum(&db_path)?;
        let now = Utc::now().to_rfc3339();
        let manager_name = format!("{} {}", game.manager.first_name, game.manager.last_name);

        let updated = self.index.update(&SaveEntry {
            id: save_id.to_string(),
            name: save_name,
            manager_name,
            db_filename: entry.db_filename.clone(),
            checksum,
            created_at: entry.created_at.clone(),
            last_played_at: now,
        });

        if !updated {
            return Err(format!("Failed to update index for save '{}'", save_id));
        }

        write_index(&self.index_path, &self.index)?;
        info!("[save_manager] saved game to {}", save_id);
        Ok(())
    }

    /// Load a Game from a save database.
    pub fn load_game(&self, save_id: &str) -> Result<Game, String> {
        let entry = self
            .index
            .find(save_id)
            .ok_or_else(|| format!("Save '{}' not found", save_id))?;

        let db_path = self.saves_dir.join(&entry.db_filename);
        debug!("[save_manager] loading game from {}", save_id);

        let db = GameDatabase::open(&db_path)?;
        self.read_game_from_db(&db)
    }

    /// Delete a save (removes DB file and index entry).
    pub fn delete_save(&mut self, save_id: &str) -> Result<bool, String> {
        let entry = match self.index.find(save_id) {
            Some(e) => e.clone(),
            None => return Ok(false),
        };

        let db_path = self.saves_dir.join(&entry.db_filename);
        if db_path.exists() {
            fs::remove_file(&db_path).map_err(|e| format!("Failed to delete save file: {}", e))?;
            debug!("[save_manager] deleted file {:?}", db_path);
        }

        self.index.remove(save_id);
        write_index(&self.index_path, &self.index)?;
        info!("[save_manager] deleted save {}", save_id);
        Ok(true)
    }

    /// Write the full Game state to a database.
    fn write_game_to_db(
        &self,
        db: &GameDatabase,
        game: &Game,
        save_id: &str,
        save_name: &str,
    ) -> Result<(), String> {
        let conn = db.conn();
        let now = Utc::now().to_rfc3339();

        // Meta
        meta_repo::upsert_meta(
            conn,
            &meta_repo::GameMeta {
                save_id: save_id.to_string(),
                save_name: save_name.to_string(),
                manager_id: game.manager.id.clone(),
                start_date: game.clock.start_date.to_rfc3339(),
                game_date: game.clock.current_date.to_rfc3339(),
                created_at: now.clone(),
                last_played_at: now,
            },
        )?;

        // Manager
        manager_repo::upsert_manager(conn, &game.manager)?;

        // Teams
        team_repo::upsert_teams(conn, &game.teams)?;

        // Players
        player_repo::upsert_players(conn, &game.players)?;

        // Staff
        staff_repo::upsert_staff_list(conn, &game.staff)?;

        // Messages
        message_repo::upsert_messages(conn, &game.messages)?;

        // News
        news_repo::upsert_news_list(conn, &game.news)?;

        // League
        if let Some(ref league) = game.league {
            league_repo::upsert_league(conn, league)?;
        }

        // Board objectives
        let obj_rows: Vec<objective_repo::BoardObjectiveRow> = game
            .board_objectives
            .iter()
            .map(|o| objective_repo::BoardObjectiveRow {
                id: o.id.clone(),
                description: o.description.clone(),
                target: o.target,
                objective_type: format!("{:?}", o.objective_type),
                met: o.met,
            })
            .collect();
        objective_repo::upsert_objectives(conn, &obj_rows)?;

        // Scouting assignments
        let scout_rows: Vec<scouting_repo::ScoutingAssignmentRow> = game
            .scouting_assignments
            .iter()
            .map(|s| scouting_repo::ScoutingAssignmentRow {
                id: s.id.clone(),
                scout_id: s.scout_id.clone(),
                player_id: s.player_id.clone(),
                days_remaining: s.days_remaining,
            })
            .collect();
        scouting_repo::upsert_scouting_list(conn, &scout_rows)?;

        Ok(())
    }

    /// Read the full Game state from a database.
    fn read_game_from_db(&self, db: &GameDatabase) -> Result<Game, String> {
        let conn = db.conn();

        let meta = meta_repo::load_meta(conn)?
            .ok_or_else(|| "No game_meta found in database".to_string())?;

        // Parse dates from meta
        let start_date = chrono::DateTime::parse_from_rfc3339(&meta.start_date)
            .map_err(|e| format!("Invalid start_date: {}", e))?
            .with_timezone(&Utc);
        let game_date = chrono::DateTime::parse_from_rfc3339(&meta.game_date)
            .map_err(|e| format!("Invalid game_date: {}", e))?
            .with_timezone(&Utc);

        let mut clock = GameClock::new(start_date);
        clock.current_date = game_date;

        // Manager
        let manager = manager_repo::load_manager(conn, &meta.manager_id)?
            .ok_or_else(|| format!("Manager '{}' not found", meta.manager_id))?;

        // Teams, players, staff
        let teams = team_repo::load_all_teams(conn)?;
        let players = player_repo::load_all_players(conn)?;
        let staff = staff_repo::load_all_staff(conn)?;

        // Messages, news
        let messages = message_repo::load_all_messages(conn)?;
        let news = news_repo::load_all_news(conn)?;

        // League
        let league = league_repo::load_league(conn)?;

        // Board objectives
        let obj_rows = objective_repo::load_all_objectives(conn)?;
        let board_objectives: Vec<BoardObjective> = obj_rows
            .into_iter()
            .map(|o| BoardObjective {
                id: o.id,
                description: o.description,
                target: o.target,
                objective_type: parse_objective_type(&o.objective_type),
                met: o.met,
            })
            .collect();

        // Scouting
        let scout_rows = scouting_repo::load_all_scouting(conn)?;
        let scouting_assignments: Vec<ScoutingAssignment> = scout_rows
            .into_iter()
            .map(|s| ScoutingAssignment {
                id: s.id,
                scout_id: s.scout_id,
                player_id: s.player_id,
                days_remaining: s.days_remaining,
            })
            .collect();

        Ok(Game {
            clock,
            manager,
            teams,
            players,
            staff,
            messages,
            news,
            league,
            scouting_assignments,
            board_objectives,
        })
    }
}

fn parse_objective_type(s: &str) -> ObjectiveType {
    match s {
        "LeaguePosition" => ObjectiveType::LeaguePosition,
        "Wins" => ObjectiveType::Wins,
        "GoalsScored" => ObjectiveType::GoalsScored,
        _ => ObjectiveType::Wins,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;
    use domain::player::{PlayerAttributes, Position};
    use domain::staff::{StaffAttributes, StaffRole};
    use domain::team::Team;

    fn sample_game() -> Game {
        let start = Utc.with_ymd_and_hms(2026, 7, 1, 0, 0, 0).unwrap();
        let mut clock = GameClock::new(start);
        clock.current_date = Utc.with_ymd_and_hms(2026, 8, 15, 0, 0, 0).unwrap();

        let mut manager = domain::manager::Manager::new(
            "mgr-user".to_string(),
            "John".to_string(),
            "Smith".to_string(),
            "1990-01-15".to_string(),
            "British".to_string(),
        );
        manager.hire("team-001".to_string());

        let team = Team::new(
            "team-001".to_string(),
            "London FC".to_string(),
            "LFC".to_string(),
            "GB".to_string(),
            "London".to_string(),
            "London Stadium".to_string(),
            50000,
        );

        let player = domain::player::Player::new(
            "p-001".to_string(),
            "J. Doe".to_string(),
            "John Doe".to_string(),
            "2000-01-01".to_string(),
            "GB".to_string(),
            Position::Midfielder,
            PlayerAttributes {
                pace: 70,
                stamina: 75,
                strength: 65,
                agility: 72,
                passing: 80,
                shooting: 60,
                tackling: 55,
                dribbling: 68,
                defending: 50,
                positioning: 65,
                vision: 78,
                decisions: 70,
                composure: 60,
                aggression: 55,
                teamwork: 80,
                leadership: 45,
                handling: 20,
                reflexes: 25,
                aerial: 40,
            },
        );

        let staff = domain::staff::Staff::new(
            "staff-001".to_string(),
            "Alice".to_string(),
            "Coach".to_string(),
            "1980-05-10".to_string(),
            StaffRole::Coach,
            StaffAttributes {
                coaching: 75,
                judging_ability: 60,
                judging_potential: 55,
                physiotherapy: 40,
            },
        );

        Game {
            clock,
            manager,
            teams: vec![team],
            players: vec![player],
            staff: vec![staff],
            messages: vec![],
            news: vec![],
            league: None,
            scouting_assignments: vec![],
            board_objectives: vec![],
        }
    }

    #[test]
    fn test_init_creates_directory() {
        let dir = tempfile::tempdir().unwrap();
        let saves_dir = dir.path().join("saves");

        let sm = SaveManager::init(&saves_dir).unwrap();
        assert!(saves_dir.exists());
        assert!(sm.list_saves().is_empty());
    }

    #[test]
    fn test_create_and_list_save() {
        let dir = tempfile::tempdir().unwrap();
        let saves_dir = dir.path().join("saves");

        let mut sm = SaveManager::init(&saves_dir).unwrap();
        let game = sample_game();

        let save_id = sm.create_save(&game, "John's Career").unwrap();
        assert!(!save_id.is_empty());

        let saves = sm.list_saves();
        assert_eq!(saves.len(), 1);
        assert_eq!(saves[0].name, "John's Career");
        assert_eq!(saves[0].manager_name, "John Smith");
        assert!(!saves[0].checksum.is_empty());
    }

    #[test]
    fn test_create_and_load_game() {
        let dir = tempfile::tempdir().unwrap();
        let saves_dir = dir.path().join("saves");

        let mut sm = SaveManager::init(&saves_dir).unwrap();
        let game = sample_game();

        let save_id = sm.create_save(&game, "Test Career").unwrap();
        let loaded = sm.load_game(&save_id).unwrap();

        assert_eq!(loaded.manager.id, "mgr-user");
        assert_eq!(loaded.manager.first_name, "John");
        assert_eq!(loaded.manager.last_name, "Smith");
        assert_eq!(loaded.teams.len(), 1);
        assert_eq!(loaded.teams[0].name, "London FC");
        assert_eq!(loaded.players.len(), 1);
        assert_eq!(loaded.staff.len(), 1);
        assert_eq!(loaded.clock.start_date, game.clock.start_date);
        assert_eq!(loaded.clock.current_date, game.clock.current_date);
    }

    #[test]
    fn test_save_game_updates_existing() {
        let dir = tempfile::tempdir().unwrap();
        let saves_dir = dir.path().join("saves");

        let mut sm = SaveManager::init(&saves_dir).unwrap();
        let mut game = sample_game();

        let save_id = sm.create_save(&game, "Career").unwrap();
        let old_checksum = sm.list_saves()[0].checksum.clone();

        // Advance the game
        game.clock.advance_days(7);
        game.manager.reputation = 999;

        sm.save_game(&game, &save_id).unwrap();

        let saves = sm.list_saves();
        assert_eq!(saves.len(), 1);
        // Checksum should change since data changed
        assert_ne!(saves[0].checksum, old_checksum);

        // Reload and verify
        let loaded = sm.load_game(&save_id).unwrap();
        assert_eq!(loaded.manager.reputation, 999);
    }

    #[test]
    fn test_delete_save() {
        let dir = tempfile::tempdir().unwrap();
        let saves_dir = dir.path().join("saves");

        let mut sm = SaveManager::init(&saves_dir).unwrap();
        let game = sample_game();

        let save_id = sm.create_save(&game, "To Delete").unwrap();
        assert_eq!(sm.list_saves().len(), 1);

        let deleted = sm.delete_save(&save_id).unwrap();
        assert!(deleted);
        assert!(sm.list_saves().is_empty());

        // File should be gone
        let db_path = saves_dir.join(format!("{}.db", save_id));
        assert!(!db_path.exists());
    }

    #[test]
    fn test_delete_nonexistent_save() {
        let dir = tempfile::tempdir().unwrap();
        let saves_dir = dir.path().join("saves");

        let mut sm = SaveManager::init(&saves_dir).unwrap();
        let deleted = sm.delete_save("nonexistent").unwrap();
        assert!(!deleted);
    }

    #[test]
    fn test_load_nonexistent_save() {
        let dir = tempfile::tempdir().unwrap();
        let saves_dir = dir.path().join("saves");

        let sm = SaveManager::init(&saves_dir).unwrap();
        let result = sm.load_game("nonexistent");
        assert!(result.is_err());
    }

    #[test]
    fn test_save_to_nonexistent_save() {
        let dir = tempfile::tempdir().unwrap();
        let saves_dir = dir.path().join("saves");

        let mut sm = SaveManager::init(&saves_dir).unwrap();
        let game = sample_game();
        let result = sm.save_game(&game, "nonexistent");
        assert!(result.is_err());
    }

    #[test]
    fn test_multiple_saves() {
        let dir = tempfile::tempdir().unwrap();
        let saves_dir = dir.path().join("saves");

        let mut sm = SaveManager::init(&saves_dir).unwrap();
        let game = sample_game();

        let id1 = sm.create_save(&game, "Career 1").unwrap();
        let id2 = sm.create_save(&game, "Career 2").unwrap();
        let id3 = sm.create_save(&game, "Career 3").unwrap();

        assert_eq!(sm.list_saves().len(), 3);
        assert_ne!(id1, id2);
        assert_ne!(id2, id3);

        // Delete one
        sm.delete_save(&id2).unwrap();
        assert_eq!(sm.list_saves().len(), 2);

        // Others still loadable
        sm.load_game(&id1).unwrap();
        sm.load_game(&id3).unwrap();
    }

    #[test]
    fn test_index_persists_across_reinit() {
        let dir = tempfile::tempdir().unwrap();
        let saves_dir = dir.path().join("saves");

        // Create a save
        {
            let mut sm = SaveManager::init(&saves_dir).unwrap();
            let game = sample_game();
            sm.create_save(&game, "Persistent Career").unwrap();
        }

        // Re-init — should find the save in the index
        let sm = SaveManager::init(&saves_dir).unwrap();
        assert_eq!(sm.list_saves().len(), 1);
        assert_eq!(sm.list_saves()[0].name, "Persistent Career");
    }

    #[test]
    fn test_game_with_objectives_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let saves_dir = dir.path().join("saves");

        let mut sm = SaveManager::init(&saves_dir).unwrap();
        let mut game = sample_game();
        game.board_objectives.push(BoardObjective {
            id: "obj-001".to_string(),
            description: "Finish top 4".to_string(),
            target: 4,
            objective_type: ObjectiveType::LeaguePosition,
            met: false,
        });

        let save_id = sm.create_save(&game, "With Objectives").unwrap();
        let loaded = sm.load_game(&save_id).unwrap();

        assert_eq!(loaded.board_objectives.len(), 1);
        assert_eq!(loaded.board_objectives[0].description, "Finish top 4");
    }

    #[test]
    fn test_game_with_scouting_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let saves_dir = dir.path().join("saves");

        let mut sm = SaveManager::init(&saves_dir).unwrap();
        let mut game = sample_game();
        game.scouting_assignments.push(ScoutingAssignment {
            id: "sa-001".to_string(),
            scout_id: "staff-001".to_string(),
            player_id: "p-001".to_string(),
            days_remaining: 7,
        });

        let save_id = sm.create_save(&game, "With Scouting").unwrap();
        let loaded = sm.load_game(&save_id).unwrap();

        assert_eq!(loaded.scouting_assignments.len(), 1);
        assert_eq!(loaded.scouting_assignments[0].days_remaining, 7);
    }
}
