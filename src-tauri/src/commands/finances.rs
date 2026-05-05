use log::info;
use serde::Serialize;
use tauri::State;

use ofm_core::finances::TeamFinanceSnapshot;
use ofm_core::game::Game;
use ofm_core::state::StateManager;

#[derive(Debug, Clone, Serialize)]
pub struct FinanceSnapshotCommandResponse {
    pub snapshot: TeamFinanceSnapshot,
}

#[tauri::command]
pub async fn get_finance_snapshot(
    state: State<'_, StateManager>,
    team_id: Option<String>,
) -> Result<FinanceSnapshotCommandResponse, String> {
    get_finance_snapshot_internal(&state, team_id.as_deref())
}

fn get_finance_snapshot_internal(
    state: &StateManager,
    team_id: Option<&str>,
) -> Result<FinanceSnapshotCommandResponse, String> {
    info!("[cmd] get_finance_snapshot: team_id={:?}", team_id);

    let game = state
        .get_game(|g: &Game| g.clone())
        .ok_or("be.error.noActiveGameSession".to_string())?;

    let resolved_team_id = match team_id {
        Some(team_id) => team_id.to_string(),
        None => game
            .manager
            .team_id
            .clone()
            .ok_or("be.error.noTeamAssigned".to_string())?,
    };

    let snapshot = ofm_core::finances::team_finance_snapshot(&game, &resolved_team_id)
        .ok_or("be.error.managedTeamNotFound".to_string())?;

    Ok(FinanceSnapshotCommandResponse { snapshot })
}

#[cfg(test)]
mod tests {
    use super::get_finance_snapshot_internal;
    use chrono::{TimeZone, Utc};
    use domain::manager::Manager;
    use domain::player::{Player, PlayerAttributes, Position};
    use domain::team::Team;
    use ofm_core::clock::GameClock;
    use ofm_core::game::Game;
    use ofm_core::state::StateManager;

    fn make_team() -> Team {
        let mut team = Team::new(
            "team-1".to_string(),
            "User FC".to_string(),
            "USR".to_string(),
            "England".to_string(),
            "London".to_string(),
            "User Ground".to_string(),
            25_000,
        );
        team.finance = 500_000;
        team.wage_budget = 120_000;
        team.manager_id = Some("manager-1".to_string());
        team
    }

    fn make_player() -> Player {
        let attrs = PlayerAttributes {
            pace: 65,
            stamina: 65,
            strength: 65,
            agility: 65,
            passing: 65,
            shooting: 65,
            tackling: 65,
            dribbling: 65,
            defending: 65,
            positioning: 65,
            vision: 65,
            decisions: 65,
            composure: 65,
            aggression: 50,
            teamwork: 65,
            leadership: 50,
            handling: 20,
            reflexes: 30,
            aerial: 60,
        };
        let mut player = Player::new(
            "player-1".to_string(),
            "Player".to_string(),
            "Test Player".to_string(),
            "1998-01-01".to_string(),
            "GB".to_string(),
            Position::Midfielder,
            attrs,
        );
        player.team_id = Some("team-1".to_string());
        player.wage = 52_000;
        player
    }

    fn make_game() -> Game {
        let clock = GameClock::new(Utc.with_ymd_and_hms(2026, 8, 1, 12, 0, 0).unwrap());
        let mut manager = Manager::new(
            "manager-1".to_string(),
            "Test".to_string(),
            "Manager".to_string(),
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
    fn get_finance_snapshot_internal_returns_managed_team_snapshot() {
        let state = StateManager::new();
        state.set_game(make_game());

        let response = get_finance_snapshot_internal(&state, None).expect("response");

        assert_eq!(response.snapshot.annual_wage_bill, 52_000);
        assert_eq!(response.snapshot.weekly_wage_spend, 1_000);
        assert_eq!(response.snapshot.weekly_wage_budget, 120_000 / 52);
    }
}