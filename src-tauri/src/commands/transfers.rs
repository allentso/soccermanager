use log::info;
use tauri::State;

use ofm_core::game::Game;
use ofm_core::state::StateManager;

#[tauri::command]
pub fn toggle_transfer_list(state: State<StateManager>, player_id: String) -> Result<Game, String> {
    info!("[cmd] toggle_transfer_list: player_id={}", player_id);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    if let Some(p) = game.players.iter_mut().find(|p| p.id == player_id) {
        p.transfer_listed = !p.transfer_listed;
    } else {
        return Err("Player not found".into());
    }
    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn toggle_loan_list(state: State<StateManager>, player_id: String) -> Result<Game, String> {
    info!("[cmd] toggle_loan_list: player_id={}", player_id);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    if let Some(p) = game.players.iter_mut().find(|p| p.id == player_id) {
        p.loan_listed = !p.loan_listed;
    } else {
        return Err("Player not found".into());
    }
    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn make_transfer_bid(
    state: State<StateManager>,
    player_id: String,
    fee: u64,
) -> Result<serde_json::Value, String> {
    info!(
        "[cmd] make_transfer_bid: player_id={}, fee={}",
        player_id, fee
    );
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let result = ofm_core::transfers::make_transfer_bid(&mut game, &player_id, fee)?;
    state.set_game(game.clone());

    Ok(serde_json::json!({
        "result": result,
        "game": game,
    }))
}

#[tauri::command]
pub fn respond_to_offer(
    state: State<StateManager>,
    player_id: String,
    offer_id: String,
    accept: bool,
) -> Result<Game, String> {
    info!(
        "[cmd] respond_to_offer: player_id={}, offer_id={}, accept={}",
        player_id, offer_id, accept
    );
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    ofm_core::transfers::respond_to_offer(&mut game, &player_id, &offer_id, accept)?;
    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn send_scout(
    state: State<StateManager>,
    scout_id: String,
    player_id: String,
) -> Result<Game, String> {
    info!(
        "[cmd] send_scout: scout_id={}, player_id={}",
        scout_id, player_id
    );
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    ofm_core::scouting::send_scout(&mut game, &scout_id, &player_id)?;
    state.set_game(game.clone());
    Ok(game)
}
