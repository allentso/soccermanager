use crate::game::{BoardObjective, Game, ObjectiveType};
use domain::league::FixtureStatus;
use domain::message::*;

/// Generate board objectives for the current season.
/// Called at season start or when no objectives exist.
pub fn generate_objectives(game: &mut Game) {
    if !game.board_objectives.is_empty() {
        return;
    }

    let user_team_id = match &game.manager.team_id {
        Some(id) => id.clone(),
        None => return,
    };

    let team = match game.teams.iter().find(|t| t.id == user_team_id) {
        Some(t) => t,
        None => return,
    };

    let num_teams = game.teams.len() as u32;
    let reputation = team.reputation;

    // Determine expected league position based on reputation
    let expected_pos = if reputation >= 80 {
        1
    } else if reputation >= 70 {
        (num_teams / 4).max(2)
    } else if reputation >= 55 {
        num_teams / 2
    } else {
        (num_teams * 3 / 4).max(num_teams / 2 + 1)
    };

    // Determine win target
    let total_matchdays = if num_teams > 1 {
        (num_teams - 1) * 2
    } else {
        0
    };
    let win_target = if reputation >= 80 {
        (total_matchdays * 60 / 100).max(1)
    } else if reputation >= 65 {
        (total_matchdays * 45 / 100).max(1)
    } else {
        (total_matchdays * 30 / 100).max(1)
    };

    // Determine goals target
    let goals_target = if reputation >= 75 {
        (total_matchdays * 2).max(10)
    } else if reputation >= 55 {
        (total_matchdays * 3 / 2).max(8)
    } else {
        total_matchdays.max(5)
    };

    game.board_objectives = vec![
        BoardObjective {
            id: "obj_position".to_string(),
            description: format!("Finish in the top {}", expected_pos),
            target: expected_pos,
            objective_type: ObjectiveType::LeaguePosition,
            met: false,
        },
        BoardObjective {
            id: "obj_wins".to_string(),
            description: format!("Win at least {} matches", win_target),
            target: win_target,
            objective_type: ObjectiveType::Wins,
            met: false,
        },
        BoardObjective {
            id: "obj_goals".to_string(),
            description: format!("Score at least {} goals", goals_target),
            target: goals_target,
            objective_type: ObjectiveType::GoalsScored,
            met: false,
        },
    ];

    // Send inbox message about objectives
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let existing_ids: std::collections::HashSet<String> =
        game.messages.iter().map(|m| m.id.clone()).collect();
    let season = game.league.as_ref().map(|l| l.season).unwrap_or(1);
    let msg_id = format!("board_objectives_{}", season);
    if !existing_ids.contains(&msg_id) {
        let objectives_text = game
            .board_objectives
            .iter()
            .enumerate()
            .map(|(i, obj)| format!("{}. {}", i + 1, obj.description))
            .collect::<Vec<_>>()
            .join("\n");

        let msg = InboxMessage::new(
            msg_id,
            format!("Season {} — Board Expectations", season),
            format!(
                "The board has set the following objectives for this season:\n\n{}\n\n\
                Meeting these targets will improve the board's confidence in your management. \
                Failure to meet expectations may result in reduced budgets or further consequences.",
                objectives_text
            ),
            "Board of Directors".to_string(),
            today,
        )
        .with_category(MessageCategory::BoardDirective)
        .with_priority(MessagePriority::High)
        .with_sender_role("Chairman");
        game.messages.push(msg);
    }
}

/// Update objective progress based on current standings. Called daily.
pub fn update_objective_progress(game: &mut Game) {
    let user_team_id = match &game.manager.team_id {
        Some(id) => id.clone(),
        None => return,
    };

    let league = match &game.league {
        Some(l) => l,
        None => return,
    };

    let standings = league.sorted_standings();
    let user_pos = standings
        .iter()
        .position(|s| s.team_id == user_team_id)
        .map(|i| (i + 1) as u32)
        .unwrap_or(99);
    let user_standing = standings.iter().find(|s| s.team_id == user_team_id);

    // Count user goals from completed fixtures
    let user_goals: u32 = league
        .fixtures
        .iter()
        .filter(|f| f.status == FixtureStatus::Completed && f.result.is_some())
        .map(|f| {
            let r = f.result.as_ref().unwrap();
            if f.home_team_id == user_team_id {
                r.home_goals as u32
            } else if f.away_team_id == user_team_id {
                r.away_goals as u32
            } else {
                0
            }
        })
        .sum();

    let user_wins = user_standing.map(|s| s.won).unwrap_or(0);

    for obj in game.board_objectives.iter_mut() {
        match obj.objective_type {
            ObjectiveType::LeaguePosition => {
                obj.met = user_pos <= obj.target;
            }
            ObjectiveType::Wins => {
                obj.met = user_wins >= obj.target;
            }
            ObjectiveType::GoalsScored => {
                obj.met = user_goals >= obj.target;
            }
        }
    }
}

/// Evaluate objectives at end of season. Returns satisfaction delta.
pub fn evaluate_objectives(game: &Game) -> i8 {
    if game.board_objectives.is_empty() {
        return 0;
    }
    let met_count = game.board_objectives.iter().filter(|o| o.met).count();
    let total = game.board_objectives.len();

    if met_count == total {
        15 // All objectives met: +15 satisfaction
    } else if met_count >= total / 2 {
        5 // Majority met: +5
    } else if met_count > 0 {
        -5 // Some met: -5
    } else {
        -15 // None met: -15
    }
}
