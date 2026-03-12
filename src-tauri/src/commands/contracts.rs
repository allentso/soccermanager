use log::info;
use serde::Serialize;
use tauri::State;

use ofm_core::contracts::{RenewalDecision, RenewalOffer};
use ofm_core::game::Game;
use ofm_core::state::StateManager;

use crate::SaveManagerState;

#[derive(Debug, Clone, Serialize)]
pub struct RenewalCommandResponse {
    pub outcome: RenewalDecision,
    pub game: Game,
    pub suggested_wage: Option<u32>,
    pub suggested_years: Option<u32>,
}

#[tauri::command]
pub async fn propose_renewal(
    state: State<'_, StateManager>,
    sm_state: State<'_, SaveManagerState>,
    player_id: String,
    weekly_wage: u32,
    contract_years: u32,
) -> Result<RenewalCommandResponse, String> {
    let response = propose_renewal_internal(&state, &player_id, weekly_wage, contract_years)?;

    if let Some(save_id) = state.get_save_id() {
        let mut sm = sm_state
            .0
            .lock()
            .map_err(|error| format!("Lock error: {}", error))?;
        sm.save_game(&response.game, &save_id)?;
    }

    Ok(response)
}

fn propose_renewal_internal(
    state: &StateManager,
    player_id: &str,
    weekly_wage: u32,
    contract_years: u32,
) -> Result<RenewalCommandResponse, String> {
    info!(
        "[cmd] propose_renewal: player_id={}, weekly_wage={}, contract_years={}",
        player_id, weekly_wage, contract_years
    );

    let mut game = state
        .get_game(|g: &Game| g.clone())
        .ok_or("No active game session".to_string())?;

    let outcome = ofm_core::contracts::propose_renewal(
        &mut game,
        player_id,
        RenewalOffer {
            weekly_wage,
            contract_years,
        },
    )?;

    state.set_game(game.clone());

    Ok(RenewalCommandResponse {
        outcome: outcome.decision,
        game,
        suggested_wage: outcome.suggested_wage,
        suggested_years: outcome.suggested_years,
    })
}

#[cfg(test)]
mod tests {
    use super::propose_renewal_internal;
    use chrono::{TimeZone, Utc};
    use domain::manager::Manager;
    use domain::player::{Player, PlayerAttributes, Position};
    use domain::team::Team;
    use ofm_core::clock::GameClock;
    use ofm_core::contracts::RenewalDecision;
    use ofm_core::game::Game;
    use ofm_core::state::StateManager;

    fn default_attrs() -> PlayerAttributes {
        PlayerAttributes {
            pace: 60,
            stamina: 60,
            strength: 60,
            agility: 60,
            passing: 60,
            shooting: 60,
            tackling: 60,
            dribbling: 60,
            defending: 60,
            positioning: 60,
            vision: 60,
            decisions: 60,
            composure: 60,
            aggression: 60,
            teamwork: 60,
            leadership: 60,
            handling: 30,
            reflexes: 30,
            aerial: 60,
        }
    }

    fn make_player() -> Player {
        let mut player = Player::new(
            "player-1".to_string(),
            "J. Smith".to_string(),
            "John Smith".to_string(),
            "2000-01-01".to_string(),
            "England".to_string(),
            Position::Forward,
            default_attrs(),
        );
        player.team_id = Some("team-1".to_string());
        player.contract_end = Some("2026-10-15".to_string());
        player.wage = 12_000;
        player.morale = 75;
        player.market_value = 350_000;
        player
    }

    fn make_team() -> Team {
        let mut team = Team::new(
            "team-1".to_string(),
            "Alpha FC".to_string(),
            "ALP".to_string(),
            "England".to_string(),
            "London".to_string(),
            "Alpha Ground".to_string(),
            30_000,
        );
        team.manager_id = Some("manager-1".to_string());
        team.reputation = 50;
        team.wage_budget = 50_000;
        team
    }

    fn make_game() -> Game {
        let clock = GameClock::new(Utc.with_ymd_and_hms(2026, 8, 1, 12, 0, 0).unwrap());
        let mut manager = Manager::new(
            "manager-1".to_string(),
            "Jane".to_string(),
            "Doe".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        manager.hire("team-1".to_string());

        Game::new(
            clock,
            manager,
            vec![make_team()],
            vec![make_player()],
            vec![],
            vec![],
        )
    }

    #[test]
    fn propose_renewal_internal_returns_response_and_updates_state() {
        let state = StateManager::new();
        state.set_game(make_game());

        let response = propose_renewal_internal(&state, "player-1", 15_000, 3).expect("response");

        assert!(matches!(response.outcome, RenewalDecision::Accepted));
        let player = response
            .game
            .players
            .iter()
            .find(|player| player.id == "player-1")
            .expect("player should exist");
        assert_eq!(player.wage, 15_000);
        assert_eq!(player.contract_end.as_deref(), Some("2029-08-01"));

        let stored_game = state.get_game(|game| game.clone()).expect("stored game");
        let stored_player = stored_game
            .players
            .iter()
            .find(|player| player.id == "player-1")
            .expect("stored player should exist");
        assert_eq!(stored_player.wage, 15_000);
        assert_eq!(stored_player.contract_end.as_deref(), Some("2029-08-01"));
    }
}
