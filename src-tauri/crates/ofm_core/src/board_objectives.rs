use crate::game::{BoardObjective, Game, ObjectiveType};
use domain::league::FixtureStatus;
use domain::message::*;

struct ObjectiveTargets {
    expected_pos: u32,
    win_target: u32,
    goals_target: u32,
}

fn objective_targets(reputation: u32, num_teams: u32) -> ObjectiveTargets {
    let expected_pos = if reputation >= 80 {
        1
    } else if reputation >= 70 {
        (num_teams / 4).max(2)
    } else if reputation >= 55 {
        num_teams / 2
    } else {
        (num_teams * 3 / 4).max(num_teams / 2 + 1)
    };

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

    let goals_target = if reputation >= 75 {
        (total_matchdays * 2).max(10)
    } else if reputation >= 55 {
        (total_matchdays * 3 / 2).max(8)
    } else {
        total_matchdays.max(5)
    };

    ObjectiveTargets {
        expected_pos,
        win_target,
        goals_target,
    }
}

fn board_message_id(season: u32) -> String {
    format!("board_objectives_{}", season)
}

fn build_objectives_message(
    objectives: &[BoardObjective],
    season: u32,
    today: String,
) -> InboxMessage {
    let objectives_text = objectives
        .iter()
        .enumerate()
        .map(|(idx, objective)| format!("{}. {}", idx + 1, objective.description))
        .collect::<Vec<_>>()
        .join("\n");

    InboxMessage::new(
        board_message_id(season),
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
    .with_sender_role("Chairman")
}

fn satisfaction_delta(met_count: usize, total: usize) -> i8 {
    if met_count == total {
        15
    } else if met_count * 2 > total {
        5
    } else if met_count > 0 {
        -5
    } else {
        -15
    }
}

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
    let targets = objective_targets(reputation, num_teams);

    game.board_objectives = vec![
        BoardObjective {
            id: "obj_position".to_string(),
            description: format!("Finish in the top {}", targets.expected_pos),
            target: targets.expected_pos,
            objective_type: ObjectiveType::LeaguePosition,
            met: false,
        },
        BoardObjective {
            id: "obj_wins".to_string(),
            description: format!("Win at least {} matches", targets.win_target),
            target: targets.win_target,
            objective_type: ObjectiveType::Wins,
            met: false,
        },
        BoardObjective {
            id: "obj_goals".to_string(),
            description: format!("Score at least {} goals", targets.goals_target),
            target: targets.goals_target,
            objective_type: ObjectiveType::GoalsScored,
            met: false,
        },
    ];

    // Send inbox message about objectives
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let existing_ids: std::collections::HashSet<String> =
        game.messages.iter().map(|m| m.id.clone()).collect();
    let season = game.league.as_ref().map(|l| l.season).unwrap_or(1);
    let msg_id = board_message_id(season);
    if !existing_ids.contains(&msg_id) {
        let msg = build_objectives_message(&game.board_objectives, season, today);
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

    satisfaction_delta(met_count, total)
}

#[cfg(test)]
mod tests {
    use super::{evaluate_objectives, generate_objectives, update_objective_progress};
    use crate::clock::GameClock;
    use crate::game::{BoardObjective, Game, ObjectiveType};
    use chrono::{TimeZone, Utc};
    use domain::league::{Fixture, FixtureStatus, League, MatchResult, StandingEntry};
    use domain::manager::Manager;
    use domain::message::{InboxMessage, MessageCategory, MessagePriority};
    use domain::team::Team;

    fn make_team(id: &str, name: &str, reputation: u32) -> Team {
        let mut team = Team::new(
            id.to_string(),
            name.to_string(),
            name.to_string(),
            "England".to_string(),
            "Testville".to_string(),
            "Test Ground".to_string(),
            20_000,
        );
        team.reputation = reputation;
        team
    }

    fn make_game(user_reputation: u32, season: u32, team_count: usize) -> Game {
        let clock = GameClock::new(Utc.with_ymd_and_hms(2025, 8, 1, 12, 0, 0).unwrap());
        let mut manager = Manager::new(
            "mgr1".to_string(),
            "Alex".to_string(),
            "Manager".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        manager.hire("team1".to_string());

        let teams: Vec<Team> = (1..=team_count)
            .map(|idx| {
                make_team(
                    &format!("team{}", idx),
                    &format!("Team {}", idx),
                    if idx == 1 { user_reputation } else { 50 },
                )
            })
            .collect();
        let team_ids: Vec<String> = teams.iter().map(|team| team.id.clone()).collect();

        let mut game = Game::new(clock, manager, teams, vec![], vec![], vec![]);
        game.league = Some(League::new(
            "league1".to_string(),
            "Test League".to_string(),
            season,
            &team_ids,
        ));
        game
    }

    fn make_objective(
        id: &str,
        objective_type: ObjectiveType,
        target: u32,
        met: bool,
    ) -> BoardObjective {
        BoardObjective {
            id: id.to_string(),
            description: format!("Objective {}", id),
            target,
            objective_type,
            met,
        }
    }

    fn objective_by_id<'a>(game: &'a Game, id: &str) -> &'a BoardObjective {
        game.board_objectives
            .iter()
            .find(|objective| objective.id == id)
            .unwrap()
    }

    #[test]
    fn generate_objectives_creates_targets_and_board_message() {
        let mut game = make_game(80, 3, 4);

        generate_objectives(&mut game);

        assert_eq!(game.board_objectives.len(), 3);
        assert_eq!(objective_by_id(&game, "obj_position").target, 1);
        assert_eq!(objective_by_id(&game, "obj_wins").target, 3);
        assert_eq!(objective_by_id(&game, "obj_goals").target, 12);

        let message = game
            .messages
            .iter()
            .find(|message| message.id == "board_objectives_3")
            .unwrap();
        assert_eq!(message.category, MessageCategory::BoardDirective);
        assert_eq!(message.priority, MessagePriority::High);
        assert_eq!(message.sender_role, "Chairman");
        assert!(message.body.contains("1. Finish in the top 1"));
        assert!(message.body.contains("2. Win at least 3 matches"));
        assert!(message.body.contains("3. Score at least 12 goals"));
    }

    #[test]
    fn generate_objectives_does_not_duplicate_existing_board_message() {
        let mut game = make_game(60, 2, 4);
        game.messages.push(
            InboxMessage::new(
                "board_objectives_2".to_string(),
                "Existing".to_string(),
                "Body".to_string(),
                "Board".to_string(),
                "2025-08-01".to_string(),
            )
            .with_category(MessageCategory::BoardDirective)
            .with_priority(MessagePriority::High),
        );

        generate_objectives(&mut game);

        assert_eq!(game.board_objectives.len(), 3);
        assert_eq!(
            game.messages
                .iter()
                .filter(|message| message.id == "board_objectives_2")
                .count(),
            1
        );
    }

    #[test]
    fn update_objective_progress_updates_each_objective_from_league_state() {
        let mut game = make_game(60, 1, 3);
        game.board_objectives = vec![
            make_objective("obj_position", ObjectiveType::LeaguePosition, 1, false),
            make_objective("obj_wins", ObjectiveType::Wins, 4, false),
            make_objective("obj_goals", ObjectiveType::GoalsScored, 6, false),
        ];

        let mut league = game.league.clone().unwrap();
        league.standings = vec![
            StandingEntry {
                team_id: "team1".to_string(),
                played: 4,
                won: 4,
                drawn: 0,
                lost: 0,
                goals_for: 5,
                goals_against: 1,
                points: 12,
            },
            StandingEntry {
                team_id: "team2".to_string(),
                played: 5,
                won: 5,
                drawn: 0,
                lost: 0,
                goals_for: 9,
                goals_against: 2,
                points: 15,
            },
            StandingEntry {
                team_id: "team3".to_string(),
                played: 4,
                won: 1,
                drawn: 0,
                lost: 3,
                goals_for: 2,
                goals_against: 7,
                points: 3,
            },
        ];
        league.fixtures = vec![
            Fixture {
                id: "f1".to_string(),
                matchday: 1,
                date: "2025-08-01".to_string(),
                home_team_id: "team1".to_string(),
                away_team_id: "team2".to_string(),
                status: FixtureStatus::Completed,
                result: Some(MatchResult {
                    home_goals: 2,
                    away_goals: 1,
                    home_scorers: vec![],
                    away_scorers: vec![],
                }),
            },
            Fixture {
                id: "f2".to_string(),
                matchday: 2,
                date: "2025-08-08".to_string(),
                home_team_id: "team3".to_string(),
                away_team_id: "team1".to_string(),
                status: FixtureStatus::Completed,
                result: Some(MatchResult {
                    home_goals: 0,
                    away_goals: 3,
                    home_scorers: vec![],
                    away_scorers: vec![],
                }),
            },
        ];
        game.league = Some(league);

        update_objective_progress(&mut game);

        assert!(!objective_by_id(&game, "obj_position").met);
        assert!(objective_by_id(&game, "obj_wins").met);
        assert!(!objective_by_id(&game, "obj_goals").met);
    }

    #[test]
    fn evaluate_objectives_distinguishes_some_met_from_majority_met() {
        let mut game = make_game(60, 1, 3);

        assert_eq!(evaluate_objectives(&game), 0);

        game.board_objectives = vec![
            make_objective("a", ObjectiveType::LeaguePosition, 1, true),
            make_objective("b", ObjectiveType::Wins, 1, false),
            make_objective("c", ObjectiveType::GoalsScored, 1, false),
        ];
        assert_eq!(evaluate_objectives(&game), -5);

        game.board_objectives = vec![
            make_objective("a", ObjectiveType::LeaguePosition, 1, true),
            make_objective("b", ObjectiveType::Wins, 1, true),
            make_objective("c", ObjectiveType::GoalsScored, 1, false),
        ];
        assert_eq!(evaluate_objectives(&game), 5);

        game.board_objectives = vec![
            make_objective("a", ObjectiveType::LeaguePosition, 1, true),
            make_objective("b", ObjectiveType::Wins, 1, true),
            make_objective("c", ObjectiveType::GoalsScored, 1, true),
        ];
        assert_eq!(evaluate_objectives(&game), 15);

        game.board_objectives = vec![
            make_objective("a", ObjectiveType::LeaguePosition, 1, true),
            make_objective("b", ObjectiveType::Wins, 1, true),
            make_objective("c", ObjectiveType::GoalsScored, 1, false),
            make_objective("d", ObjectiveType::GoalsScored, 1, false),
        ];
        assert_eq!(evaluate_objectives(&game), -5);

        game.board_objectives = vec![
            make_objective("a", ObjectiveType::LeaguePosition, 1, false),
            make_objective("b", ObjectiveType::Wins, 1, false),
            make_objective("c", ObjectiveType::GoalsScored, 1, false),
        ];
        assert_eq!(evaluate_objectives(&game), -15);
    }
}
