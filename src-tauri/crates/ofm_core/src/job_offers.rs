use crate::game::Game;
use domain::manager::ManagerCareerEntry;
use domain::message::*;
use log::info;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JobOpportunity {
    pub team_id: String,
    pub team_name: String,
    pub city: String,
    pub reputation: u32,
    pub last_league_position: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum JobApplicationResult {
    Hired,
    Rejected,
    InvalidTeam,
    AlreadyEmployed,
}

fn params(pairs: &[(&str, &str)]) -> HashMap<String, String> {
    pairs
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

/// Shared hiring flow used by both offer-accept and application-accept paths.
pub fn hire_manager(game: &mut Game, team_id: &str, date: &str) -> Result<String, String> {
    let team = game
        .teams
        .iter()
        .find(|t| t.id == team_id)
        .ok_or_else(|| format!("Team {} not found", team_id))?;
    let team_name = team.name.clone();
    let manager_id = game.manager.id.clone();

    // Assign manager to team
    game.manager.hire(team_id.to_string());
    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.manager_id = Some(manager_id);
    }

    // Create new career history entry
    game.manager.career_history.push(ManagerCareerEntry {
        team_id: team_id.to_string(),
        team_name: team_name.clone(),
        start_date: date.to_string(),
        end_date: None,
        matches: 0,
        wins: 0,
        draws: 0,
        losses: 0,
        best_league_position: None,
    });

    // Reset satisfaction to neutral
    game.manager.satisfaction = 50;

    // Clear job offer timer
    game.days_since_last_job_offer = None;

    // Send welcome message
    let msg = InboxMessage::new(
        format!("job_welcome_{}_{}", team_id, date),
        format!("Welcome to {}", team_name),
        format!(
            "The board of directors at {} is delighted to welcome you as the new manager. \
             We look forward to working with you and achieving great things together.",
            team_name
        ),
        "Board of Directors".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::BoardDirective)
    .with_priority(MessagePriority::High)
    .with_sender_role("Chairman")
    .with_i18n(
        "be.msg.jobHired.subject",
        "be.msg.jobHired.body",
        params(&[("team", &team_name)]),
    )
    .with_sender_i18n("be.sender.boardOfDirectors", "be.role.chairman");

    game.messages.push(msg);

    info!(
        "[job_offers] Manager {} hired at {} (satisfaction reset to 50)",
        game.manager.full_name(),
        team_name
    );

    Ok(team_name)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::clock::GameClock;
    use chrono::{TimeZone, Utc};
    use domain::manager::Manager;
    use domain::team::Team;

    fn make_game(satisfaction: u8, has_team: bool) -> Game {
        let clock = GameClock::new(Utc.with_ymd_and_hms(2026, 11, 1, 12, 0, 0).unwrap());
        let mut manager = Manager::new(
            "mgr1".to_string(),
            "Alex".to_string(),
            "Boss".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        manager.reputation = 500;
        manager.satisfaction = satisfaction;
        if has_team {
            manager.hire("team1".to_string());
        }

        let mut team1 = Team::new(
            "team1".to_string(),
            "Old FC".to_string(),
            "OLD".to_string(),
            "England".to_string(),
            "Oldville".to_string(),
            "Old Ground".to_string(),
            20_000,
        );
        team1.reputation = 500;
        if has_team {
            team1.manager_id = Some("mgr1".to_string());
        }

        let mut team2 = Team::new(
            "team2".to_string(),
            "New FC".to_string(),
            "NEW".to_string(),
            "England".to_string(),
            "Newville".to_string(),
            "New Ground".to_string(),
            25_000,
        );
        team2.reputation = 450;

        let mut team3 = Team::new(
            "team3".to_string(),
            "Elite FC".to_string(),
            "ELT".to_string(),
            "England".to_string(),
            "Elitetown".to_string(),
            "Elite Arena".to_string(),
            40_000,
        );
        team3.reputation = 800;

        Game::new(
            clock,
            manager,
            vec![team1, team2, team3],
            vec![],
            vec![],
            vec![],
        )
    }

    #[test]
    fn hire_manager_sets_team_id_and_manager_id() {
        let mut game = make_game(10, false);
        let result = hire_manager(&mut game, "team2", "2026-11-01");
        assert!(result.is_ok());
        assert_eq!(game.manager.team_id, Some("team2".to_string()));
        assert_eq!(
            game.teams.iter().find(|t| t.id == "team2").unwrap().manager_id,
            Some("mgr1".to_string())
        );
    }

    #[test]
    fn hire_manager_creates_career_entry() {
        let mut game = make_game(10, false);
        hire_manager(&mut game, "team2", "2026-11-01").unwrap();
        let entry = game.manager.career_history.last().unwrap();
        assert_eq!(entry.team_id, "team2");
        assert_eq!(entry.team_name, "New FC");
        assert_eq!(entry.start_date, "2026-11-01");
        assert!(entry.end_date.is_none());
        assert_eq!(entry.matches, 0);
        assert_eq!(entry.wins, 0);
    }

    #[test]
    fn hire_manager_resets_satisfaction_to_50() {
        let mut game = make_game(10, false);
        hire_manager(&mut game, "team2", "2026-11-01").unwrap();
        assert_eq!(game.manager.satisfaction, 50);
    }

    #[test]
    fn hire_manager_clears_job_offer_timer() {
        let mut game = make_game(10, false);
        game.days_since_last_job_offer = Some(5);
        hire_manager(&mut game, "team2", "2026-11-01").unwrap();
        assert!(game.days_since_last_job_offer.is_none());
    }

    #[test]
    fn hire_manager_sends_welcome_message() {
        let mut game = make_game(10, false);
        hire_manager(&mut game, "team2", "2026-11-01").unwrap();
        assert!(game.messages.iter().any(|m| m.id.starts_with("job_welcome_")));
    }

    #[test]
    fn hire_manager_invalid_team_returns_error() {
        let mut game = make_game(10, false);
        let result = hire_manager(&mut game, "nonexistent", "2026-11-01");
        assert!(result.is_err());
    }
}
