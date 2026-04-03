use domain::stats::PlayerMatchStatsRecord;
use ofm_core::state::StateManager;
use serde::{Deserialize, Serialize};
use tauri::State;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PlayerMatchHistoryEntryDto {
    pub fixture_id: String,
    pub date: String,
    pub competition: String,
    pub matchday: u32,
    pub opponent_team_id: String,
    pub opponent_name: String,
    pub team_goals: u8,
    pub opponent_goals: u8,
    pub minutes_played: u8,
    pub goals: u8,
    pub assists: u8,
    pub shots: u8,
    pub shots_on_target: u8,
    pub passes_completed: u8,
    pub passes_attempted: u8,
    pub tackles_won: u8,
    pub interceptions: u8,
    pub fouls_committed: u8,
    pub yellow_cards: u8,
    pub red_cards: u8,
    pub rating: f32,
}

fn competition_label(record: &PlayerMatchStatsRecord) -> String {
    match record.competition {
        domain::league::FixtureCompetition::League => "League".to_string(),
        domain::league::FixtureCompetition::Friendly => "Friendly".to_string(),
        domain::league::FixtureCompetition::PreseasonTournament => "PreseasonTournament".to_string(),
    }
}

fn opponent_name(state: &StateManager, opponent_team_id: &str) -> String {
    state
        .get_game(|game| {
            game.teams
                .iter()
                .find(|team| team.id == opponent_team_id)
                .map(|team| team.name.clone())
        })
        .flatten()
        .unwrap_or_else(|| opponent_team_id.to_string())
}

fn to_dto(state: &StateManager, record: &PlayerMatchStatsRecord) -> PlayerMatchHistoryEntryDto {
    let team_goals = if record.team_id == record.home_team_id {
        record.home_goals
    } else {
        record.away_goals
    };
    let opponent_goals = if record.team_id == record.home_team_id {
        record.away_goals
    } else {
        record.home_goals
    };

    PlayerMatchHistoryEntryDto {
        fixture_id: record.fixture_id.clone(),
        date: record.date.clone(),
        competition: competition_label(record),
        matchday: record.matchday,
        opponent_team_id: record.opponent_team_id.clone(),
        opponent_name: opponent_name(state, &record.opponent_team_id),
        team_goals,
        opponent_goals,
        minutes_played: record.minutes_played,
        goals: record.goals,
        assists: record.assists,
        shots: record.shots,
        shots_on_target: record.shots_on_target,
        passes_completed: record.passes_completed,
        passes_attempted: record.passes_attempted,
        tackles_won: record.tackles_won,
        interceptions: record.interceptions,
        fouls_committed: record.fouls_committed,
        yellow_cards: record.yellow_cards,
        red_cards: record.red_cards,
        rating: record.rating,
    }
}

pub fn get_player_match_history_internal(
    state: &StateManager,
    player_id: &str,
    limit: Option<usize>,
) -> Result<Vec<PlayerMatchHistoryEntryDto>, String> {
    let Some(mut history) = state.get_stats_state(|stats| {
        stats
            .player_matches
            .iter()
            .filter(|record| record.player_id == player_id)
            .cloned()
            .collect::<Vec<_>>()
    }) else {
        return Ok(Vec::new());
    };

    history.sort_by(|left, right| {
        right
            .date
            .cmp(&left.date)
            .then(right.matchday.cmp(&left.matchday))
            .then(right.fixture_id.cmp(&left.fixture_id))
    });

    let limit = limit.unwrap_or(5);
    Ok(history
        .into_iter()
        .take(limit)
        .map(|record| to_dto(state, &record))
        .collect())
}

#[tauri::command]
pub fn get_player_match_history(
    state: State<'_, StateManager>,
    player_id: String,
    limit: Option<usize>,
) -> Result<Vec<PlayerMatchHistoryEntryDto>, String> {
    get_player_match_history_internal(&state, &player_id, limit)
}

#[cfg(test)]
mod tests {
    use super::get_player_match_history_internal;
    use domain::league::FixtureCompetition;
    use domain::stats::{PlayerMatchStatsRecord, StatsState};
    use ofm_core::state::StateManager;

    fn sample_stats_state() -> StatsState {
        StatsState {
            player_matches: vec![
                PlayerMatchStatsRecord {
                    fixture_id: "fixture-older".to_string(),
                    season: 2025,
                    matchday: 1,
                    date: "2025-06-10".to_string(),
                    competition: FixtureCompetition::League,
                    player_id: "player-1".to_string(),
                    team_id: "team-1".to_string(),
                    opponent_team_id: "team-2".to_string(),
                    home_team_id: "team-1".to_string(),
                    away_team_id: "team-2".to_string(),
                    home_goals: 2,
                    away_goals: 1,
                    minutes_played: 90,
                    goals: 1,
                    assists: 0,
                    shots: 4,
                    shots_on_target: 2,
                    passes_completed: 20,
                    passes_attempted: 24,
                    tackles_won: 1,
                    interceptions: 0,
                    fouls_committed: 1,
                    yellow_cards: 0,
                    red_cards: 0,
                    rating: 7.2,
                },
                PlayerMatchStatsRecord {
                    fixture_id: "fixture-latest".to_string(),
                    season: 2025,
                    matchday: 2,
                    date: "2025-06-17".to_string(),
                    competition: FixtureCompetition::League,
                    player_id: "player-1".to_string(),
                    team_id: "team-1".to_string(),
                    opponent_team_id: "team-3".to_string(),
                    home_team_id: "team-3".to_string(),
                    away_team_id: "team-1".to_string(),
                    home_goals: 0,
                    away_goals: 3,
                    minutes_played: 88,
                    goals: 2,
                    assists: 1,
                    shots: 5,
                    shots_on_target: 3,
                    passes_completed: 24,
                    passes_attempted: 28,
                    tackles_won: 2,
                    interceptions: 1,
                    fouls_committed: 0,
                    yellow_cards: 0,
                    red_cards: 0,
                    rating: 8.4,
                },
                PlayerMatchStatsRecord {
                    fixture_id: "fixture-other-player".to_string(),
                    season: 2025,
                    matchday: 2,
                    date: "2025-06-17".to_string(),
                    competition: FixtureCompetition::League,
                    player_id: "player-2".to_string(),
                    team_id: "team-1".to_string(),
                    opponent_team_id: "team-3".to_string(),
                    home_team_id: "team-3".to_string(),
                    away_team_id: "team-1".to_string(),
                    home_goals: 0,
                    away_goals: 3,
                    minutes_played: 90,
                    goals: 0,
                    assists: 0,
                    shots: 1,
                    shots_on_target: 0,
                    passes_completed: 40,
                    passes_attempted: 48,
                    tackles_won: 4,
                    interceptions: 3,
                    fouls_committed: 2,
                    yellow_cards: 1,
                    red_cards: 0,
                    rating: 7.0,
                },
            ],
            team_matches: vec![],
        }
    }

    #[test]
    fn get_player_match_history_returns_latest_matches_first_with_limit() {
        let state = StateManager::new();
        state.set_stats_state(sample_stats_state());

        let history = get_player_match_history_internal(&state, "player-1", Some(1)).unwrap();

        assert_eq!(history.len(), 1);
        assert_eq!(history[0].fixture_id, "fixture-latest");
        assert_eq!(history[0].opponent_team_id, "team-3");
        assert_eq!(history[0].goals, 2);
    }

    #[test]
    fn get_player_match_history_returns_empty_when_stats_state_is_missing() {
        let state = StateManager::new();

        let history = get_player_match_history_internal(&state, "player-1", None).unwrap();

        assert!(history.is_empty());
    }
}