mod commands;
use commands::*;

use ofm_core::state::StateManager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(
            tauri_plugin_log::Builder::new()
                .level(log::LevelFilter::Info)
                .level_for("openfootmanager_lib", log::LevelFilter::Debug)
                .level_for("ofm_core", log::LevelFilter::Debug)
                .level_for("engine", log::LevelFilter::Debug)
                .level_for("db", log::LevelFilter::Debug)
                .rotation_strategy(tauri_plugin_log::RotationStrategy::KeepAll)
                .max_file_size(5_000_000) // 5 MB per log file
                .build(),
        )
        .manage(StateManager::new())
        .invoke_handler(tauri::generate_handler![
            list_world_databases,
            start_new_game,
            export_world_database,
            write_temp_database,
            select_team,
            get_saves,
            load_game,
            get_active_game,
            advance_time,
            advance_time_with_mode,
            set_formation,
            set_starting_xi,
            set_play_style,
            set_training,
            set_training_schedule,
            hire_staff,
            release_staff,
            mark_message_read,
            mark_all_messages_read,
            clear_old_messages,
            save_game,
            auto_select_set_pieces,
            toggle_transfer_list,
            toggle_loan_list,
            make_transfer_bid,
            respond_to_offer,
            send_scout,
            check_season_complete,
            advance_to_next_season,
            get_season_awards,
            resolve_message_action,
            start_live_match,
            step_live_match,
            apply_match_command,
            get_match_snapshot,
            finish_live_match,
            delete_save,
            skip_to_match_day,
            check_blocking_actions,
            apply_team_talk,
            submit_press_conference,
            exit_to_menu,
            get_settings,
            save_settings,
            clear_all_saves
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
