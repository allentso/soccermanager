use domain::player::{Player, PlayerAttributes, Position};
use rusqlite::{Connection, params};

/// Insert or replace a player row.
pub fn upsert_player(conn: &Connection, p: &Player) -> Result<(), String> {
    let attrs_json =
        serde_json::to_string(&p.attributes).map_err(|e| format!("JSON error: {}", e))?;
    let injury_json = p
        .injury
        .as_ref()
        .map(|i| serde_json::to_string(i).unwrap_or_default());
    let traits_json = serde_json::to_string(&p.traits).map_err(|e| format!("JSON error: {}", e))?;
    let stats_json = serde_json::to_string(&p.stats).map_err(|e| format!("JSON error: {}", e))?;
    let career_json = serde_json::to_string(&p.career).map_err(|e| format!("JSON error: {}", e))?;
    let offers_json =
        serde_json::to_string(&p.transfer_offers).map_err(|e| format!("JSON error: {}", e))?;
    let position_str = format!("{:?}", p.position);
    let natural_position_str = format!("{:?}", p.natural_position);
    let alt_positions_json =
        serde_json::to_string(&p.alternate_positions).map_err(|e| format!("JSON error: {}", e))?;

    conn.execute(
        "INSERT OR REPLACE INTO players
         (id, match_name, full_name, date_of_birth, nationality, position,
          attributes, condition, morale, injury, team_id, traits,
          contract_end, wage, market_value, stats, career,
          transfer_listed, loan_listed, transfer_offers, alternate_positions,
          natural_position)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22)",
        params![
            p.id,
            p.match_name,
            p.full_name,
            p.date_of_birth,
            p.nationality,
            position_str,
            attrs_json,
            p.condition,
            p.morale,
            injury_json,
            p.team_id,
            traits_json,
            p.contract_end,
            p.wage,
            p.market_value as i64,
            stats_json,
            career_json,
            p.transfer_listed as i32,
            p.loan_listed as i32,
            offers_json,
            alt_positions_json,
            natural_position_str,
        ],
    )
    .map_err(|e| format!("Failed to upsert player: {}", e))?;
    Ok(())
}

/// Insert or replace multiple players.
pub fn upsert_players(conn: &Connection, players: &[Player]) -> Result<(), String> {
    for p in players {
        upsert_player(conn, p)?;
    }
    Ok(())
}

fn parse_position(s: &str) -> Position {
    match s {
        "Goalkeeper" => Position::Goalkeeper,
        "Defender" => Position::Defender,
        "Midfielder" => Position::Midfielder,
        "Forward" => Position::Forward,
        _ => Position::Midfielder,
    }
}

/// Load all players.
pub fn load_all_players(conn: &Connection) -> Result<Vec<Player>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, match_name, full_name, date_of_birth, nationality, position,
                    attributes, condition, morale, injury, team_id, traits,
                    contract_end, wage, market_value, stats, career,
                    transfer_listed, loan_listed, transfer_offers, alternate_positions,
                    natural_position
             FROM players",
        )
        .map_err(|e| format!("Failed to prepare players query: {}", e))?;

    let rows = stmt
        .query_map([], row_to_player)
        .map_err(|e| format!("Failed to query players: {}", e))?;

    let mut players = Vec::new();
    for row in rows {
        players.push(row.map_err(|e| format!("Failed to read player row: {}", e))?);
    }
    Ok(players)
}

/// Load players by team id.
pub fn load_players_by_team(conn: &Connection, team_id: &str) -> Result<Vec<Player>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, match_name, full_name, date_of_birth, nationality, position,
                    attributes, condition, morale, injury, team_id, traits,
                    contract_end, wage, market_value, stats, career,
                    transfer_listed, loan_listed, transfer_offers, alternate_positions,
                    natural_position
             FROM players WHERE team_id = ?1",
        )
        .map_err(|e| format!("Failed to prepare players query: {}", e))?;

    let rows = stmt
        .query_map(params![team_id], row_to_player)
        .map_err(|e| format!("Failed to query players: {}", e))?;

    let mut players = Vec::new();
    for row in rows {
        players.push(row.map_err(|e| format!("Failed to read player row: {}", e))?);
    }
    Ok(players)
}

fn row_to_player(row: &rusqlite::Row) -> rusqlite::Result<Player> {
    let position_str: String = row.get(5)?;
    let attrs_json: String = row.get(6)?;
    let injury_json: Option<String> = row.get(9)?;
    let traits_json: String = row.get(11)?;
    let stats_json: String = row.get(15)?;
    let career_json: String = row.get(16)?;
    let offers_json: String = row.get(19)?;
    let alt_positions_json: String = row.get(20)?;
    let natural_position_str: String = row.get(21)?;
    let transfer_listed_int: i32 = row.get(17)?;
    let loan_listed_int: i32 = row.get(18)?;
    let market_value_i64: i64 = row.get(14)?;

    let position = parse_position(&position_str);
    let natural_position = if natural_position_str.is_empty() {
        position.clone()
    } else {
        parse_position(&natural_position_str)
    };

    Ok(Player {
        id: row.get(0)?,
        match_name: row.get(1)?,
        full_name: row.get(2)?,
        date_of_birth: row.get(3)?,
        nationality: row.get(4)?,
        position,
        natural_position,
        alternate_positions: serde_json::from_str(&alt_positions_json).unwrap_or_default(),
        attributes: serde_json::from_str(&attrs_json).unwrap_or(PlayerAttributes {
            pace: 50,
            stamina: 50,
            strength: 50,
            agility: 50,
            passing: 50,
            shooting: 50,
            tackling: 50,
            dribbling: 50,
            defending: 50,
            positioning: 50,
            vision: 50,
            decisions: 50,
            composure: 50,
            aggression: 50,
            teamwork: 50,
            leadership: 50,
            handling: 50,
            reflexes: 50,
            aerial: 50,
        }),
        condition: row.get(7)?,
        morale: row.get(8)?,
        injury: injury_json.and_then(|j| serde_json::from_str(&j).ok()),
        team_id: row.get(10)?,
        traits: serde_json::from_str(&traits_json).unwrap_or_default(),
        contract_end: row.get(12)?,
        wage: row.get(13)?,
        market_value: market_value_i64 as u64,
        stats: serde_json::from_str(&stats_json).unwrap_or_default(),
        career: serde_json::from_str(&career_json).unwrap_or_default(),
        transfer_listed: transfer_listed_int != 0,
        loan_listed: loan_listed_int != 0,
        transfer_offers: serde_json::from_str(&offers_json).unwrap_or_default(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::game_database::GameDatabase;
    use domain::player::Injury;

    fn test_db() -> GameDatabase {
        GameDatabase::open_in_memory().unwrap()
    }

    fn sample_player(id: &str, team_id: Option<&str>) -> Player {
        let mut p = Player::new(
            id.to_string(),
            "J. Smith".to_string(),
            "John Smith".to_string(),
            "2000-01-15".to_string(),
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
        p.team_id = team_id.map(|s| s.to_string());
        p.wage = 5000;
        p.market_value = 500_000;
        p
    }

    #[test]
    fn test_upsert_and_load_player() {
        let db = test_db();
        let player = sample_player("p-001", Some("team-001"));

        upsert_player(db.conn(), &player).unwrap();
        let all = load_all_players(db.conn()).unwrap();
        assert_eq!(all.len(), 1);
        assert_eq!(all[0].id, "p-001");
        assert_eq!(all[0].full_name, "John Smith");
        assert_eq!(all[0].position, Position::Midfielder);
        assert_eq!(all[0].team_id, Some("team-001".to_string()));
        assert_eq!(all[0].wage, 5000);
        assert_eq!(all[0].market_value, 500_000);
    }

    #[test]
    fn test_upsert_players_batch() {
        let db = test_db();
        let players = vec![
            sample_player("p-001", Some("team-001")),
            sample_player("p-002", Some("team-001")),
            sample_player("p-003", Some("team-002")),
        ];

        upsert_players(db.conn(), &players).unwrap();
        let all = load_all_players(db.conn()).unwrap();
        assert_eq!(all.len(), 3);
    }

    #[test]
    fn test_load_players_by_team() {
        let db = test_db();
        let players = vec![
            sample_player("p-001", Some("team-001")),
            sample_player("p-002", Some("team-001")),
            sample_player("p-003", Some("team-002")),
        ];
        upsert_players(db.conn(), &players).unwrap();

        let team1 = load_players_by_team(db.conn(), "team-001").unwrap();
        assert_eq!(team1.len(), 2);

        let team2 = load_players_by_team(db.conn(), "team-002").unwrap();
        assert_eq!(team2.len(), 1);
    }

    #[test]
    fn test_player_alternate_positions_roundtrip() {
        let db = test_db();
        let mut player = sample_player("p-001", Some("team-001"));
        player.alternate_positions = vec![Position::Defender, Position::Forward];

        upsert_player(db.conn(), &player).unwrap();
        let loaded = load_all_players(db.conn()).unwrap();

        assert_eq!(loaded[0].alternate_positions.len(), 2);
        assert_eq!(loaded[0].alternate_positions[0], Position::Defender);
        assert_eq!(loaded[0].alternate_positions[1], Position::Forward);
    }

    #[test]
    fn test_player_empty_alternate_positions_roundtrip() {
        let db = test_db();
        let player = sample_player("p-001", None);

        upsert_player(db.conn(), &player).unwrap();
        let loaded = load_all_players(db.conn()).unwrap();

        assert!(loaded[0].alternate_positions.is_empty());
    }

    #[test]
    fn test_player_attributes_roundtrip() {
        let db = test_db();
        let player = sample_player("p-001", None);

        upsert_player(db.conn(), &player).unwrap();
        let loaded = load_all_players(db.conn()).unwrap();

        assert_eq!(loaded[0].attributes.pace, 70);
        assert_eq!(loaded[0].attributes.passing, 80);
        assert_eq!(loaded[0].attributes.vision, 78);
    }

    #[test]
    fn test_player_injury_roundtrip() {
        let db = test_db();
        let mut player = sample_player("p-001", None);
        player.injury = Some(Injury {
            name: "Hamstring".to_string(),
            days_remaining: 14,
        });

        upsert_player(db.conn(), &player).unwrap();
        let loaded = load_all_players(db.conn()).unwrap();

        assert!(loaded[0].injury.is_some());
        let injury = loaded[0].injury.as_ref().unwrap();
        assert_eq!(injury.name, "Hamstring");
        assert_eq!(injury.days_remaining, 14);
    }

    #[test]
    fn test_player_no_injury_roundtrip() {
        let db = test_db();
        let player = sample_player("p-001", None);

        upsert_player(db.conn(), &player).unwrap();
        let loaded = load_all_players(db.conn()).unwrap();

        assert!(loaded[0].injury.is_none());
    }

    #[test]
    fn test_player_transfer_flags_roundtrip() {
        let db = test_db();
        let mut player = sample_player("p-001", None);
        player.transfer_listed = true;
        player.loan_listed = true;

        upsert_player(db.conn(), &player).unwrap();
        let loaded = load_all_players(db.conn()).unwrap();

        assert!(loaded[0].transfer_listed);
        assert!(loaded[0].loan_listed);
    }

    #[test]
    fn test_player_stats_roundtrip() {
        let db = test_db();
        let mut player = sample_player("p-001", None);
        player.stats.appearances = 20;
        player.stats.goals = 5;
        player.stats.assists = 8;

        upsert_player(db.conn(), &player).unwrap();
        let loaded = load_all_players(db.conn()).unwrap();

        assert_eq!(loaded[0].stats.appearances, 20);
        assert_eq!(loaded[0].stats.goals, 5);
        assert_eq!(loaded[0].stats.assists, 8);
    }
}
