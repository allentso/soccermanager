use log::info;
use tauri::State;

use ofm_core::game::Game;
use ofm_core::state::StateManager;

#[tauri::command]
pub fn upgrade_facility(state: State<'_, StateManager>, facility: String) -> Result<Game, String> {
    info!("[cmd] upgrade_facility: {}", facility);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game
        .manager
        .team_id
        .clone()
        .ok_or("No team assigned".to_string())?;

    let facility_type = match facility.as_str() {
        "Training" => domain::team::FacilityType::Training,
        "Medical" => domain::team::FacilityType::Medical,
        "Scouting" => domain::team::FacilityType::Scouting,
        _ => return Err(format!("Unknown facility type: {}", facility)),
    };

    let team = game
        .teams
        .iter_mut()
        .find(|team| team.id == team_id)
        .ok_or("Managed team not found".to_string())?;

    ofm_core::club::upgrade_facility(team, facility_type)?;

    state.set_game(game.clone());
    Ok(game)
}
