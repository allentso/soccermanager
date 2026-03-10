use std::collections::HashSet;

use log::info;
use tauri::State;

use ofm_core::game::Game;
use ofm_core::state::StateManager;

#[tauri::command]
pub fn mark_message_read(
    state: State<'_, StateManager>,
    message_id: String,
) -> Result<Game, String> {
    log::debug!("[cmd] mark_message_read: {}", message_id);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
        msg.read = true;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn delete_message(state: State<'_, StateManager>, message_id: String) -> Result<Game, String> {
    log::debug!("[cmd] delete_message: {}", message_id);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    game.messages.retain(|message| message.id != message_id);

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn delete_messages(
    state: State<'_, StateManager>,
    message_ids: Vec<String>,
) -> Result<Game, String> {
    log::debug!("[cmd] delete_messages: {}", message_ids.len());
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;
    let message_ids: HashSet<String> = message_ids.into_iter().collect();

    game.messages
        .retain(|message| !message_ids.contains(&message.id));

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn mark_all_messages_read(state: State<'_, StateManager>) -> Result<Game, String> {
    log::debug!("[cmd] mark_all_messages_read");
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    for msg in game.messages.iter_mut() {
        msg.read = true;
    }

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn clear_old_messages(state: State<'_, StateManager>) -> Result<Game, String> {
    log::debug!("[cmd] clear_old_messages");
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let current_date = game.clock.current_date.format("%Y-%m-%d").to_string();
    // Keep only: unread messages, messages with unresolved actions, and messages from recent 14 days
    game.messages.retain(|m| {
        if !m.read {
            return true;
        }
        if m.actions.iter().any(|a| !a.resolved) {
            return true;
        }
        // Keep recent messages (within 14 days)
        if let Ok(msg_date) = chrono::NaiveDate::parse_from_str(&m.date, "%Y-%m-%d") {
            if let Ok(cur_date) = chrono::NaiveDate::parse_from_str(&current_date, "%Y-%m-%d") {
                return (cur_date - msg_date).num_days() <= 14;
            }
        }
        false
    });

    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn resolve_message_action(
    state: State<'_, StateManager>,
    message_id: String,
    action_id: String,
    option_id: Option<String>,
) -> Result<serde_json::Value, String> {
    info!(
        "[cmd] resolve_message_action: msg={}, action={}, option={:?}",
        message_id, action_id, option_id
    );
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    // Try to apply player conversation or random event response
    let (effect, effect_i18n_key, effect_i18n_params) = if let Some(opt) = &option_id {
        // Try player events first, then random events
        let player_effect =
            ofm_core::player_events::apply_player_response(&mut game, &message_id, &action_id, opt);
        if let Some(player_effect) = player_effect {
            (
                Some(player_effect.message),
                Some(player_effect.i18n_key),
                Some(player_effect.i18n_params),
            )
        } else {
            (
                ofm_core::random_events::apply_event_response(
                    &mut game,
                    &message_id,
                    &action_id,
                    opt,
                ),
                None,
                None,
            )
        }
    } else {
        // Standard resolve — just mark action as resolved
        if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
            if let Some(action) = msg.actions.iter_mut().find(|a| a.id == action_id) {
                action.resolved = true;
            }
        }
        (None, None, None)
    };

    state.set_game(game.clone());
    Ok(serde_json::json!({
        "game": game,
        "effect": effect,
        "effect_i18n_key": effect_i18n_key,
        "effect_i18n_params": effect_i18n_params
    }))
}
