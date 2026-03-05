use domain::league::{Fixture, FixtureStatus, League, StandingEntry};
use rusqlite::{Connection, params};

/// Insert or replace the league row and its fixtures + standings.
pub fn upsert_league(conn: &Connection, league: &League) -> Result<(), String> {
    conn.execute(
        "INSERT OR REPLACE INTO league (id, name, season) VALUES (?1, ?2, ?3)",
        params![league.id, league.name, league.season],
    )
    .map_err(|e| format!("Failed to upsert league: {}", e))?;

    // Clear existing fixtures/standings for this league, then re-insert
    conn.execute(
        "DELETE FROM fixtures WHERE league_id = ?1",
        params![league.id],
    )
    .map_err(|e| format!("Failed to clear fixtures: {}", e))?;
    conn.execute(
        "DELETE FROM standings WHERE league_id = ?1",
        params![league.id],
    )
    .map_err(|e| format!("Failed to clear standings: {}", e))?;

    for f in &league.fixtures {
        let status_str = format!("{:?}", f.status);
        let result_json = f
            .result
            .as_ref()
            .map(|r| serde_json::to_string(r).unwrap_or_default());
        conn.execute(
            "INSERT INTO fixtures (id, league_id, matchday, date, home_team_id, away_team_id, status, result)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                f.id,
                league.id,
                f.matchday,
                f.date,
                f.home_team_id,
                f.away_team_id,
                status_str,
                result_json,
            ],
        )
        .map_err(|e| format!("Failed to insert fixture: {}", e))?;
    }

    for s in &league.standings {
        conn.execute(
            "INSERT INTO standings (league_id, team_id, played, won, drawn, lost, goals_for, goals_against, points)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                league.id,
                s.team_id,
                s.played,
                s.won,
                s.drawn,
                s.lost,
                s.goals_for,
                s.goals_against,
                s.points,
            ],
        )
        .map_err(|e| format!("Failed to insert standing: {}", e))?;
    }

    Ok(())
}

fn parse_fixture_status(s: &str) -> FixtureStatus {
    match s {
        "InProgress" => FixtureStatus::InProgress,
        "Completed" => FixtureStatus::Completed,
        _ => FixtureStatus::Scheduled,
    }
}

/// Load the league (if any). Returns None if the league table is empty.
pub fn load_league(conn: &Connection) -> Result<Option<League>, String> {
    let mut stmt = conn
        .prepare("SELECT id, name, season FROM league LIMIT 1")
        .map_err(|e| format!("Failed to prepare league query: {}", e))?;

    let mut rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, u32>(2)?,
            ))
        })
        .map_err(|e| format!("Failed to query league: {}", e))?;

    let (league_id, name, season) = match rows.next() {
        Some(Ok(tuple)) => tuple,
        Some(Err(e)) => return Err(format!("Failed to read league row: {}", e)),
        None => return Ok(None),
    };

    // Load fixtures
    let mut fix_stmt = conn
        .prepare(
            "SELECT id, matchday, date, home_team_id, away_team_id, status, result
             FROM fixtures WHERE league_id = ?1 ORDER BY matchday, id",
        )
        .map_err(|e| format!("Failed to prepare fixtures query: {}", e))?;

    let fixture_rows = fix_stmt
        .query_map(params![league_id], |row| {
            let status_str: String = row.get(5)?;
            let result_json: Option<String> = row.get(6)?;
            Ok(Fixture {
                id: row.get(0)?,
                matchday: row.get(1)?,
                date: row.get(2)?,
                home_team_id: row.get(3)?,
                away_team_id: row.get(4)?,
                status: parse_fixture_status(&status_str),
                result: result_json.and_then(|j| serde_json::from_str(&j).ok()),
            })
        })
        .map_err(|e| format!("Failed to query fixtures: {}", e))?;

    let mut fixtures = Vec::new();
    for row in fixture_rows {
        fixtures.push(row.map_err(|e| format!("Failed to read fixture: {}", e))?);
    }

    // Load standings
    let mut stand_stmt = conn
        .prepare(
            "SELECT team_id, played, won, drawn, lost, goals_for, goals_against, points
             FROM standings WHERE league_id = ?1",
        )
        .map_err(|e| format!("Failed to prepare standings query: {}", e))?;

    let standing_rows = stand_stmt
        .query_map(params![league_id], |row| {
            Ok(StandingEntry {
                team_id: row.get(0)?,
                played: row.get(1)?,
                won: row.get(2)?,
                drawn: row.get(3)?,
                lost: row.get(4)?,
                goals_for: row.get(5)?,
                goals_against: row.get(6)?,
                points: row.get(7)?,
            })
        })
        .map_err(|e| format!("Failed to query standings: {}", e))?;

    let mut standings = Vec::new();
    for row in standing_rows {
        standings.push(row.map_err(|e| format!("Failed to read standing: {}", e))?);
    }

    Ok(Some(League {
        id: league_id,
        name,
        season,
        fixtures,
        standings,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::game_database::GameDatabase;
    use domain::league::{GoalEvent, MatchResult};

    fn test_db() -> GameDatabase {
        GameDatabase::open_in_memory().unwrap()
    }

    fn sample_league() -> League {
        let team_ids = vec!["team-001".to_string(), "team-002".to_string()];
        let mut league = League::new(
            "league-1".to_string(),
            "Premier Division".to_string(),
            2026,
            &team_ids,
        );
        league.fixtures = vec![
            Fixture {
                id: "fix-001".to_string(),
                matchday: 1,
                date: "2026-08-15".to_string(),
                home_team_id: "team-001".to_string(),
                away_team_id: "team-002".to_string(),
                status: FixtureStatus::Scheduled,
                result: None,
            },
            Fixture {
                id: "fix-002".to_string(),
                matchday: 2,
                date: "2026-08-22".to_string(),
                home_team_id: "team-002".to_string(),
                away_team_id: "team-001".to_string(),
                status: FixtureStatus::Completed,
                result: Some(MatchResult {
                    home_goals: 2,
                    away_goals: 1,
                    home_scorers: vec![GoalEvent {
                        player_id: "p-010".to_string(),
                        minute: 23,
                    }],
                    away_scorers: vec![],
                }),
            },
        ];
        league
    }

    #[test]
    fn test_upsert_and_load_league() {
        let db = test_db();
        let league = sample_league();

        upsert_league(db.conn(), &league).unwrap();
        let loaded = load_league(db.conn()).unwrap().unwrap();

        assert_eq!(loaded.id, "league-1");
        assert_eq!(loaded.name, "Premier Division");
        assert_eq!(loaded.season, 2026);
    }

    #[test]
    fn test_league_fixtures_roundtrip() {
        let db = test_db();
        let league = sample_league();

        upsert_league(db.conn(), &league).unwrap();
        let loaded = load_league(db.conn()).unwrap().unwrap();

        assert_eq!(loaded.fixtures.len(), 2);
        assert_eq!(loaded.fixtures[0].status, FixtureStatus::Scheduled);
        assert!(loaded.fixtures[0].result.is_none());
        assert_eq!(loaded.fixtures[1].status, FixtureStatus::Completed);
        assert!(loaded.fixtures[1].result.is_some());
        let result = loaded.fixtures[1].result.as_ref().unwrap();
        assert_eq!(result.home_goals, 2);
        assert_eq!(result.away_goals, 1);
    }

    #[test]
    fn test_league_standings_roundtrip() {
        let db = test_db();
        let league = sample_league();

        upsert_league(db.conn(), &league).unwrap();
        let loaded = load_league(db.conn()).unwrap().unwrap();

        assert_eq!(loaded.standings.len(), 2);
    }

    #[test]
    fn test_load_league_empty() {
        let db = test_db();
        let loaded = load_league(db.conn()).unwrap();
        assert!(loaded.is_none());
    }

    #[test]
    fn test_upsert_league_replaces_fixtures() {
        let db = test_db();
        let mut league = sample_league();
        upsert_league(db.conn(), &league).unwrap();

        // Modify and re-upsert — old fixtures should be replaced
        league.fixtures = vec![Fixture {
            id: "fix-003".to_string(),
            matchday: 3,
            date: "2026-08-29".to_string(),
            home_team_id: "team-001".to_string(),
            away_team_id: "team-002".to_string(),
            status: FixtureStatus::Scheduled,
            result: None,
        }];
        upsert_league(db.conn(), &league).unwrap();

        let loaded = load_league(db.conn()).unwrap().unwrap();
        assert_eq!(loaded.fixtures.len(), 1);
        assert_eq!(loaded.fixtures[0].id, "fix-003");
    }
}
