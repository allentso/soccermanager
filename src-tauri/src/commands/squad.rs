use log::info;
use tauri::State;

use ofm_core::game::Game;
use ofm_core::state::StateManager;

#[tauri::command]
pub fn set_formation(state: State<StateManager>, formation: String) -> Result<Game, String> {
    info!("[cmd] set_formation: {}", formation);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game
        .manager
        .team_id
        .clone()
        .ok_or("No team assigned".to_string())?;

    // Parse formation into (def, mid, fwd) counts
    let parts: Vec<usize> = formation
        .split('-')
        .filter_map(|s| s.parse().ok())
        .collect();
    let (num_def, num_mid, num_fwd) = match parts.len() {
        3 => (parts[0], parts[1], parts[2]),
        4 => (parts[0], parts[1] + parts[2], parts[3]),
        _ => (4, 4, 2),
    };

    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.formation = formation;
    }

    // Reassign positions for outfield players on this team
    let player_ids: Vec<String> = game
        .players
        .iter()
        .filter(|p| {
            p.team_id.as_deref() == Some(&team_id)
                && p.position != domain::player::Position::Goalkeeper
        })
        .map(|p| p.id.clone())
        .collect();

    // Sort by defensive ability (most defensive first)
    let mut sorted_ids = player_ids.clone();
    sorted_ids.sort_by(|a_id, b_id| {
        let pa = game.players.iter().find(|p| p.id == *a_id).unwrap();
        let pb = game.players.iter().find(|p| p.id == *b_id).unwrap();
        let def_a = pa.attributes.defending as u16
            + pa.attributes.tackling as u16
            + pa.attributes.strength as u16;
        let def_b = pb.attributes.defending as u16
            + pb.attributes.tackling as u16
            + pb.attributes.strength as u16;
        def_b.cmp(&def_a)
    });

    // Assign positions
    for (slot, pid) in sorted_ids.iter().enumerate() {
        let new_pos = if slot < num_def {
            domain::player::Position::Defender
        } else if slot < num_def + num_mid {
            domain::player::Position::Midfielder
        } else if slot < num_def + num_mid + num_fwd {
            domain::player::Position::Forward
        } else {
            continue;
        };
        if let Some(player) = game.players.iter_mut().find(|p| p.id == *pid) {
            player.position = new_pos;
        }
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn set_starting_xi(
    state: State<StateManager>,
    player_ids: Vec<String>,
) -> Result<Game, String> {
    info!("[cmd] set_starting_xi: {} players", player_ids.len());
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game
        .manager
        .team_id
        .clone()
        .ok_or("No team assigned".to_string())?;

    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.starting_xi_ids = player_ids;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn set_play_style(state: State<StateManager>, play_style: String) -> Result<Game, String> {
    info!("[cmd] set_play_style: {}", play_style);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game
        .manager
        .team_id
        .clone()
        .ok_or("No team assigned".to_string())?;

    let style = match play_style.as_str() {
        "Attacking" => domain::team::PlayStyle::Attacking,
        "Defensive" => domain::team::PlayStyle::Defensive,
        "Possession" => domain::team::PlayStyle::Possession,
        "Counter" => domain::team::PlayStyle::Counter,
        "HighPress" => domain::team::PlayStyle::HighPress,
        _ => domain::team::PlayStyle::Balanced,
    };

    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.play_style = style;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn set_training(
    state: State<StateManager>,
    focus: String,
    intensity: String,
) -> Result<Game, String> {
    info!(
        "[cmd] set_training: focus={}, intensity={}",
        focus, intensity
    );
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game
        .manager
        .team_id
        .clone()
        .ok_or("No team assigned".to_string())?;

    let training_focus = match focus.as_str() {
        "Physical" => domain::team::TrainingFocus::Physical,
        "Technical" => domain::team::TrainingFocus::Technical,
        "Tactical" => domain::team::TrainingFocus::Tactical,
        "Defending" => domain::team::TrainingFocus::Defending,
        "Attacking" => domain::team::TrainingFocus::Attacking,
        "Recovery" => domain::team::TrainingFocus::Recovery,
        _ => domain::team::TrainingFocus::Physical,
    };

    let training_intensity = match intensity.as_str() {
        "Low" => domain::team::TrainingIntensity::Low,
        "Medium" => domain::team::TrainingIntensity::Medium,
        "High" => domain::team::TrainingIntensity::High,
        _ => domain::team::TrainingIntensity::Medium,
    };

    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.training_focus = training_focus;
        team.training_intensity = training_intensity;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn set_training_schedule(state: State<StateManager>, schedule: String) -> Result<Game, String> {
    info!("[cmd] set_training_schedule: {}", schedule);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let team_id = game
        .manager
        .team_id
        .clone()
        .ok_or("No team assigned".to_string())?;

    let training_schedule = match schedule.as_str() {
        "Intense" => domain::team::TrainingSchedule::Intense,
        "Balanced" => domain::team::TrainingSchedule::Balanced,
        "Light" => domain::team::TrainingSchedule::Light,
        _ => domain::team::TrainingSchedule::Balanced,
    };

    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.training_schedule = training_schedule;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn auto_select_set_pieces(
    state: State<StateManager>,
    player_ids: Vec<String>,
) -> Result<serde_json::Value, String> {
    log::debug!("[cmd] auto_select_set_pieces: {} players", player_ids.len());
    let game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let (captain, penalty, free_kick, corner) =
        ofm_core::live_match_manager::auto_select_set_pieces(&game, &player_ids);

    Ok(serde_json::json!({
        "captain": captain,
        "penalty_taker": penalty,
        "free_kick_taker": free_kick,
        "corner_taker": corner,
    }))
}
