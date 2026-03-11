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
    info!(
        "[cmd] propose_renewal: player_id={}, weekly_wage={}, contract_years={}",
        player_id, weekly_wage, contract_years
    );

    let mut game = state
        .get_game(|g: &Game| g.clone())
        .ok_or("No active game session".to_string())?;

    let outcome = ofm_core::contracts::propose_renewal(
        &mut game,
        &player_id,
        RenewalOffer {
            weekly_wage,
            contract_years,
        },
    )?;

    if let Some(save_id) = state.get_save_id() {
        let mut sm = sm_state
            .0
            .lock()
            .map_err(|error| format!("Lock error: {}", error))?;
        sm.save_game(&game, &save_id)?;
    }

    state.set_game(game.clone());

    Ok(RenewalCommandResponse {
        outcome: outcome.decision,
        game,
        suggested_wage: outcome.suggested_wage,
        suggested_years: outcome.suggested_years,
    })
}
