use log::info;
use tauri::State;

use ofm_core::game::Game;
use ofm_core::state::StateManager;

#[tauri::command]
pub fn hire_staff(state: State<'_, StateManager>, staff_id: String) -> Result<Game, String> {
    info!("[cmd] hire_staff: staff_id={}", staff_id);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game
        .manager
        .team_id
        .clone()
        .ok_or("No team assigned".to_string())?;

    let staff = game
        .staff
        .iter_mut()
        .find(|s| s.id == staff_id)
        .ok_or("Staff member not found".to_string())?;

    if staff.team_id.is_some() {
        return Err("Staff member already employed by a team".to_string());
    }

    staff.team_id = Some(team_id.clone());

    // Deduct wage from team budget
    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.season_expenses += staff.wage as i64;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn release_staff(state: State<'_, StateManager>, staff_id: String) -> Result<Game, String> {
    info!("[cmd] release_staff: staff_id={}", staff_id);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game
        .manager
        .team_id
        .clone()
        .ok_or("No team assigned".to_string())?;

    let staff = game
        .staff
        .iter_mut()
        .find(|s| s.id == staff_id)
        .ok_or("Staff member not found".to_string())?;

    if staff.team_id.as_deref() != Some(&team_id) {
        return Err("Staff member does not belong to your team".to_string());
    }

    staff.team_id = None;

    state.set_game(game.clone());
    Ok(game)
}
