use crate::game::Game;
use domain::message::*;
use log::info;
use std::collections::HashMap;

const WARN_THRESHOLD: u8 = 25;
const FINAL_WARN_THRESHOLD: u8 = 18;
const FIRE_THRESHOLD: u8 = 10;

const BOARD_WARNING_ID: &str = "board_warning";
const BOARD_FINAL_WARNING_ID: &str = "board_final_warning";
const BOARD_FIRED_ID: &str = "board_fired";

fn has_message(game: &Game, id_prefix: &str) -> bool {
    game.messages.iter().any(|m| m.id.starts_with(id_prefix))
}

fn params(pairs: &[(&str, &str)]) -> HashMap<String, String> {
    pairs
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

/// Check manager satisfaction and issue warnings or fire.
/// Returns `true` if the manager was fired.
pub fn check_manager_firing(game: &mut Game) -> bool {
    if game.manager.team_id.is_none() {
        return false;
    }

    let satisfaction = game.manager.satisfaction;

    if satisfaction <= FIRE_THRESHOLD {
        // Grace period: only fire if at least one warning was previously sent
        let had_warning =
            has_message(game, BOARD_WARNING_ID) || has_message(game, BOARD_FINAL_WARNING_ID);
        if had_warning {
            execute_firing(game);
            return true;
        }
        // No prior warning — send one now instead of instant-firing
        if !has_message(game, BOARD_FINAL_WARNING_ID) {
            send_final_warning(game);
        }
    } else if satisfaction <= FINAL_WARN_THRESHOLD {
        if !has_message(game, BOARD_FINAL_WARNING_ID) {
            send_final_warning(game);
        }
    } else if satisfaction <= WARN_THRESHOLD && !has_message(game, BOARD_WARNING_ID) {
        send_warning(game);
    }

    false
}

fn execute_firing(game: &mut Game) {
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let team_id = game.manager.team_id.clone().unwrap_or_default();
    let team_name = game
        .teams
        .iter()
        .find(|t| t.id == team_id)
        .map(|t| t.name.clone())
        .unwrap_or_default();

    info!(
        "[firing] Manager {} fired from {} (satisfaction={})",
        game.manager.full_name(),
        team_name,
        game.manager.satisfaction
    );

    // Clear manager from team
    if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id) {
        team.manager_id = None;
    }

    // Close career history and unassign
    game.manager.fire(&today);

    // Send dismissal message
    let msg = InboxMessage::new(
        BOARD_FIRED_ID.to_string(),
        format!("Notice of Dismissal — {}", team_name),
        format!(
            "The board of directors at {} has decided to relieve you of your duties as manager, \
             effective immediately.\n\nWe thank you for your service and wish you well in your future career.",
            team_name
        ),
        "Board of Directors".to_string(),
        today,
    )
    .with_category(MessageCategory::BoardDirective)
    .with_priority(MessagePriority::Urgent)
    .with_sender_role("Chairman")
    .with_i18n(
        "be.msg.boardFired.subject",
        "be.msg.boardFired.body",
        params(&[("team", &team_name)]),
    )
    .with_sender_i18n("be.sender.boardOfDirectors", "be.role.chairman");

    game.messages.push(msg);
}

fn send_warning(game: &mut Game) {
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let team_name = game
        .manager
        .team_id
        .as_ref()
        .and_then(|tid| game.teams.iter().find(|t| &t.id == tid))
        .map(|t| t.name.clone())
        .unwrap_or_default();

    info!(
        "[firing] Board warning issued to {} (satisfaction={})",
        game.manager.full_name(),
        game.manager.satisfaction
    );

    let msg = InboxMessage::new(
        BOARD_WARNING_ID.to_string(),
        format!("Board Concern — Performance Review"),
        format!(
            "The board is growing increasingly concerned with recent results at {}. \
             Your position will come under serious review if there is no improvement in the near future.",
            team_name
        ),
        "Board of Directors".to_string(),
        today,
    )
    .with_category(MessageCategory::BoardDirective)
    .with_priority(MessagePriority::High)
    .with_sender_role("Chairman")
    .with_i18n(
        "be.msg.boardWarning.subject",
        "be.msg.boardWarning.body",
        params(&[("team", &team_name)]),
    )
    .with_sender_i18n("be.sender.boardOfDirectors", "be.role.chairman");

    game.messages.push(msg);
}

fn send_final_warning(game: &mut Game) {
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let team_name = game
        .manager
        .team_id
        .as_ref()
        .and_then(|tid| game.teams.iter().find(|t| &t.id == tid))
        .map(|t| t.name.clone())
        .unwrap_or_default();

    info!(
        "[firing] Final warning issued to {} (satisfaction={})",
        game.manager.full_name(),
        game.manager.satisfaction
    );

    let msg = InboxMessage::new(
        BOARD_FINAL_WARNING_ID.to_string(),
        format!("Final Warning — Immediate Improvement Required"),
        format!(
            "This is your final warning. The board at {} has lost patience with the current run of results. \
             Unless there is an immediate and significant improvement, we will have no choice but to consider your position.",
            team_name
        ),
        "Board of Directors".to_string(),
        today,
    )
    .with_category(MessageCategory::BoardDirective)
    .with_priority(MessagePriority::Urgent)
    .with_sender_role("Chairman")
    .with_i18n(
        "be.msg.boardFinalWarning.subject",
        "be.msg.boardFinalWarning.body",
        params(&[("team", &team_name)]),
    )
    .with_sender_i18n("be.sender.boardOfDirectors", "be.role.chairman");

    game.messages.push(msg);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::clock::GameClock;
    use chrono::{TimeZone, Utc};
    use domain::manager::{Manager, ManagerCareerEntry};
    use domain::team::Team;

    fn make_game(satisfaction: u8) -> Game {
        let clock = GameClock::new(Utc.with_ymd_and_hms(2026, 10, 15, 12, 0, 0).unwrap());
        let mut manager = Manager::new(
            "mgr1".to_string(),
            "Alex".to_string(),
            "Boss".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        manager.hire("team1".to_string());
        manager.satisfaction = satisfaction;
        manager.career_history.push(ManagerCareerEntry {
            team_id: "team1".to_string(),
            team_name: "Test FC".to_string(),
            start_date: "2026-07-01".to_string(),
            end_date: None,
            matches: 10,
            wins: 2,
            draws: 3,
            losses: 5,
            best_league_position: Some(12),
        });

        let mut team = Team::new(
            "team1".to_string(),
            "Test FC".to_string(),
            "TST".to_string(),
            "England".to_string(),
            "Testville".to_string(),
            "Test Ground".to_string(),
            20_000,
        );
        team.manager_id = Some("mgr1".to_string());

        Game::new(clock, manager, vec![team], vec![], vec![], vec![])
    }

    #[test]
    fn no_action_when_satisfaction_above_warning_threshold() {
        let mut game = make_game(50);
        let fired = check_manager_firing(&mut game);
        assert!(!fired);
        assert!(game.manager.team_id.is_some());
        assert!(game.messages.is_empty());
    }

    #[test]
    fn warning_sent_at_warning_threshold() {
        let mut game = make_game(25);
        let fired = check_manager_firing(&mut game);
        assert!(!fired);
        assert!(game.manager.team_id.is_some());
        assert_eq!(game.messages.len(), 1);
        assert_eq!(game.messages[0].id, BOARD_WARNING_ID);
        assert_eq!(game.messages[0].priority, MessagePriority::High);
    }

    #[test]
    fn final_warning_sent_at_final_warning_threshold() {
        let mut game = make_game(18);
        let fired = check_manager_firing(&mut game);
        assert!(!fired);
        assert!(game.manager.team_id.is_some());
        assert_eq!(game.messages.len(), 1);
        assert_eq!(game.messages[0].id, BOARD_FINAL_WARNING_ID);
        assert_eq!(game.messages[0].priority, MessagePriority::Urgent);
    }

    #[test]
    fn not_fired_at_fire_threshold_without_prior_warning() {
        let mut game = make_game(5);
        let fired = check_manager_firing(&mut game);
        assert!(!fired);
        assert!(game.manager.team_id.is_some());
        // Should send a final warning instead
        assert_eq!(game.messages.len(), 1);
        assert_eq!(game.messages[0].id, BOARD_FINAL_WARNING_ID);
    }

    #[test]
    fn fired_at_fire_threshold_with_prior_warning() {
        let mut game = make_game(5);
        // Simulate a prior warning existing
        game.messages.push(InboxMessage::new(
            BOARD_WARNING_ID.to_string(),
            "Warning".to_string(),
            "You are warned".to_string(),
            "Board".to_string(),
            "2026-10-10".to_string(),
        ));

        let fired = check_manager_firing(&mut game);
        assert!(fired);
        assert!(game.manager.team_id.is_none());
        // Should have the old warning + a fired message
        assert_eq!(game.messages.len(), 2);
        assert_eq!(game.messages[1].id, BOARD_FIRED_ID);
        assert_eq!(game.messages[1].priority, MessagePriority::Urgent);
    }

    #[test]
    fn career_history_closed_on_firing() {
        let mut game = make_game(5);
        game.messages.push(InboxMessage::new(
            BOARD_FINAL_WARNING_ID.to_string(),
            "Final".to_string(),
            "Last chance".to_string(),
            "Board".to_string(),
            "2026-10-12".to_string(),
        ));

        check_manager_firing(&mut game);
        let entry = &game.manager.career_history[0];
        assert_eq!(entry.end_date, Some("2026-10-15".to_string()));
    }

    #[test]
    fn team_manager_id_cleared_on_firing() {
        let mut game = make_game(5);
        game.messages.push(InboxMessage::new(
            BOARD_WARNING_ID.to_string(),
            "Warning".to_string(),
            "Warned".to_string(),
            "Board".to_string(),
            "2026-10-10".to_string(),
        ));

        check_manager_firing(&mut game);
        assert!(game.teams[0].manager_id.is_none());
    }

    #[test]
    fn warning_deduplication() {
        let mut game = make_game(25);
        check_manager_firing(&mut game);
        assert_eq!(game.messages.len(), 1);
        // Call again — should not add a second warning
        check_manager_firing(&mut game);
        assert_eq!(game.messages.len(), 1);
    }

    #[test]
    fn no_action_when_manager_has_no_team() {
        let mut game = make_game(5);
        game.manager.team_id = None;
        let fired = check_manager_firing(&mut game);
        assert!(!fired);
        assert!(game.messages.is_empty());
    }
}
