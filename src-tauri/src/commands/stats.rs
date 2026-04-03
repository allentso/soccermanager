use std::collections::HashMap;

use domain::player::{Player, PlayerSeasonStats, Position};
use domain::stats::{PlayerMatchStatsRecord, TeamMatchStatsRecord};
use ofm_core::state::StateManager;
use serde::{Deserialize, Serialize};
use tauri::State;

const DEFAULT_MINIMUM_MINUTES: u32 = 180;
const DEFAULT_MINIMUM_COHORT_SIZE: usize = 3;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PlayerAdvancedMetricDto {
    pub total: u32,
    pub per90: Option<f32>,
    pub percentile: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PlayerAdvancedPassMetricDto {
    pub completed: u32,
    pub attempted: u32,
    pub accuracy: Option<f32>,
    pub percentile: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PlayerStatsOverviewMetricsDto {
    pub shots: PlayerAdvancedMetricDto,
    pub shots_on_target: PlayerAdvancedMetricDto,
    pub passes: PlayerAdvancedPassMetricDto,
    pub tackles_won: PlayerAdvancedMetricDto,
    pub interceptions: PlayerAdvancedMetricDto,
    pub fouls_committed: PlayerAdvancedMetricDto,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PlayerStatsOverviewDto {
    pub percentile_eligible: bool,
    pub metrics: PlayerStatsOverviewMetricsDto,
}

#[derive(Debug, Clone, Default)]
struct PlayerAggregate {
    minutes_played: u32,
    shots: u32,
    shots_on_target: u32,
    passes_completed: u32,
    passes_attempted: u32,
    tackles_won: u32,
    interceptions: u32,
    fouls_committed: u32,
}

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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TeamMatchHistoryEntryDto {
    pub fixture_id: String,
    pub date: String,
    pub competition: String,
    pub matchday: u32,
    pub opponent_team_id: String,
    pub opponent_name: String,
    pub goals_for: u8,
    pub goals_against: u8,
    pub possession_pct: u8,
    pub shots: u16,
    pub shots_on_target: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TeamAdvancedMetricDto {
    pub total: u32,
    pub per_match: Option<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TeamAdvancedPassMetricDto {
    pub completed: u32,
    pub attempted: u32,
    pub accuracy: Option<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TeamStatsOverviewMetricsDto {
    pub shots: TeamAdvancedMetricDto,
    pub shots_on_target: TeamAdvancedMetricDto,
    pub passes: TeamAdvancedPassMetricDto,
    pub tackles_won: TeamAdvancedMetricDto,
    pub interceptions: TeamAdvancedMetricDto,
    pub fouls_committed: TeamAdvancedMetricDto,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TeamStatsOverviewDto {
    pub matches_played: u32,
    pub goals_for: u32,
    pub goals_against: u32,
    pub goal_difference: i32,
    pub possession_average: Option<f32>,
    pub metrics: TeamStatsOverviewMetricsDto,
}

#[derive(Debug, Clone, Default)]
struct TeamAggregate {
    matches_played: u32,
    goals_for: u32,
    goals_against: u32,
    possession_total: u32,
    shots: u32,
    shots_on_target: u32,
    passes_completed: u32,
    passes_attempted: u32,
    tackles_won: u32,
    interceptions: u32,
    fouls_committed: u32,
}

fn competition_label(record: &PlayerMatchStatsRecord) -> String {
    match record.competition {
        domain::league::FixtureCompetition::League => "League".to_string(),
        domain::league::FixtureCompetition::Friendly => "Friendly".to_string(),
        domain::league::FixtureCompetition::PreseasonTournament => "PreseasonTournament".to_string(),
    }
}

fn round_to(value: f32, digits: i32) -> f32 {
    let factor = 10_f32.powi(digits);
    (value * factor).round() / factor
}

fn calculate_per90(total: u32, minutes_played: u32) -> Option<f32> {
    if minutes_played == 0 {
        return None;
    }

    Some(round_to((total as f32 * 90.0) / minutes_played as f32, 1))
}

fn calculate_pass_accuracy(completed: u32, attempted: u32) -> Option<f32> {
    if attempted == 0 {
        return None;
    }

    Some(round_to((completed as f32 / attempted as f32) * 100.0, 1))
}

fn calculate_average(total: u32, count: u32) -> Option<f32> {
    if count == 0 {
        return None;
    }

    Some(round_to(total as f32 / count as f32, 1))
}

fn percentile_rank(values: &[f32], target: Option<f32>) -> Option<u32> {
    let target = target?;
    if values.is_empty() {
        return None;
    }

    let ranked_count = values.iter().filter(|value| **value <= target).count();
    Some(((ranked_count as f32 / values.len() as f32) * 100.0).round() as u32)
}

fn position_key(player: &Player) -> &Position {
    &player.natural_position
}

fn aggregate_from_history(records: &[PlayerMatchStatsRecord]) -> Option<PlayerAggregate> {
    if records.is_empty() {
        return None;
    }

    let mut aggregate = PlayerAggregate::default();
    for record in records {
        aggregate.minutes_played += record.minutes_played as u32;
        aggregate.shots += record.shots as u32;
        aggregate.shots_on_target += record.shots_on_target as u32;
        aggregate.passes_completed += record.passes_completed as u32;
        aggregate.passes_attempted += record.passes_attempted as u32;
        aggregate.tackles_won += record.tackles_won as u32;
        aggregate.interceptions += record.interceptions as u32;
        aggregate.fouls_committed += record.fouls_committed as u32;
    }

    Some(aggregate)
}

fn aggregate_from_season_stats(stats: &PlayerSeasonStats) -> PlayerAggregate {
    PlayerAggregate {
        minutes_played: stats.minutes_played,
        shots: stats.shots,
        shots_on_target: stats.shots_on_target,
        passes_completed: stats.passes_completed,
        passes_attempted: stats.passes_attempted,
        tackles_won: stats.tackles_won,
        interceptions: stats.interceptions,
        fouls_committed: stats.fouls_committed,
    }
}

fn metric_percentile<F>(
    peers: &[&PlayerAggregate],
    selector: F,
    player_aggregate: &PlayerAggregate,
) -> Option<u32>
where
    F: Fn(&PlayerAggregate) -> Option<f32>,
{
    let values = peers
        .iter()
        .filter_map(|aggregate| selector(aggregate))
        .collect::<Vec<_>>();

    percentile_rank(&values, selector(player_aggregate))
}

fn build_overview_from_aggregate(
    player_aggregate: &PlayerAggregate,
    peers: &[PlayerAggregate],
) -> PlayerStatsOverviewDto {
    let eligible_peers = peers
        .iter()
        .filter(|aggregate| aggregate.minutes_played >= DEFAULT_MINIMUM_MINUTES)
        .collect::<Vec<_>>();
    let can_compute_percentiles = player_aggregate.minutes_played >= DEFAULT_MINIMUM_MINUTES
        && eligible_peers.len() >= DEFAULT_MINIMUM_COHORT_SIZE;

    PlayerStatsOverviewDto {
        percentile_eligible: can_compute_percentiles,
        metrics: PlayerStatsOverviewMetricsDto {
            shots: PlayerAdvancedMetricDto {
                total: player_aggregate.shots,
                per90: calculate_per90(player_aggregate.shots, player_aggregate.minutes_played),
                percentile: if can_compute_percentiles {
                    metric_percentile(
                        &eligible_peers,
                        |aggregate| calculate_per90(aggregate.shots, aggregate.minutes_played),
                        player_aggregate,
                    )
                } else {
                    None
                },
            },
            shots_on_target: PlayerAdvancedMetricDto {
                total: player_aggregate.shots_on_target,
                per90: calculate_per90(
                    player_aggregate.shots_on_target,
                    player_aggregate.minutes_played,
                ),
                percentile: if can_compute_percentiles {
                    metric_percentile(
                        &eligible_peers,
                        |aggregate| {
                            calculate_per90(
                                aggregate.shots_on_target,
                                aggregate.minutes_played,
                            )
                        },
                        player_aggregate,
                    )
                } else {
                    None
                },
            },
            passes: PlayerAdvancedPassMetricDto {
                completed: player_aggregate.passes_completed,
                attempted: player_aggregate.passes_attempted,
                accuracy: calculate_pass_accuracy(
                    player_aggregate.passes_completed,
                    player_aggregate.passes_attempted,
                ),
                percentile: if can_compute_percentiles {
                    metric_percentile(
                        &eligible_peers,
                        |aggregate| {
                            calculate_pass_accuracy(
                                aggregate.passes_completed,
                                aggregate.passes_attempted,
                            )
                        },
                        player_aggregate,
                    )
                } else {
                    None
                },
            },
            tackles_won: PlayerAdvancedMetricDto {
                total: player_aggregate.tackles_won,
                per90: calculate_per90(
                    player_aggregate.tackles_won,
                    player_aggregate.minutes_played,
                ),
                percentile: if can_compute_percentiles {
                    metric_percentile(
                        &eligible_peers,
                        |aggregate| {
                            calculate_per90(aggregate.tackles_won, aggregate.minutes_played)
                        },
                        player_aggregate,
                    )
                } else {
                    None
                },
            },
            interceptions: PlayerAdvancedMetricDto {
                total: player_aggregate.interceptions,
                per90: calculate_per90(
                    player_aggregate.interceptions,
                    player_aggregate.minutes_played,
                ),
                percentile: if can_compute_percentiles {
                    metric_percentile(
                        &eligible_peers,
                        |aggregate| {
                            calculate_per90(aggregate.interceptions, aggregate.minutes_played)
                        },
                        player_aggregate,
                    )
                } else {
                    None
                },
            },
            fouls_committed: PlayerAdvancedMetricDto {
                total: player_aggregate.fouls_committed,
                per90: calculate_per90(
                    player_aggregate.fouls_committed,
                    player_aggregate.minutes_played,
                ),
                percentile: if can_compute_percentiles {
                    metric_percentile(
                        &eligible_peers,
                        |aggregate| {
                            calculate_per90(aggregate.fouls_committed, aggregate.minutes_played)
                        },
                        player_aggregate,
                    )
                } else {
                    None
                },
            },
        },
    }
}

fn build_history_overview(
    state: &StateManager,
    player_id: &str,
) -> Result<Option<PlayerStatsOverviewDto>, String> {
    let game = state
        .get_game(|game| game.clone())
        .ok_or("No active game session".to_string())?;
    let Some(player) = game.players.iter().find(|candidate| candidate.id == player_id) else {
        return Err("Player not found".to_string());
    };
    let target_position = position_key(player).clone();
    let same_position_ids = game
        .players
        .iter()
        .filter(|candidate| *position_key(candidate) == target_position)
        .map(|candidate| candidate.id.clone())
        .collect::<Vec<_>>();

    let Some(history_aggregates) = state.get_stats_state(|stats| {
        let mut records_by_player: HashMap<String, Vec<PlayerMatchStatsRecord>> = HashMap::new();

        for record in &stats.player_matches {
            if same_position_ids.iter().any(|candidate_id| candidate_id == &record.player_id) {
                records_by_player
                    .entry(record.player_id.clone())
                    .or_default()
                    .push(record.clone());
            }
        }

        records_by_player
            .into_iter()
            .filter_map(|(candidate_id, records)| {
                aggregate_from_history(&records).map(|aggregate| (candidate_id, aggregate))
            })
            .collect::<HashMap<_, _>>()
    }) else {
        return Ok(None);
    };

    let Some(player_aggregate) = history_aggregates.get(player_id) else {
        return Ok(None);
    };

    let peers = same_position_ids
        .iter()
        .filter_map(|candidate_id| history_aggregates.get(candidate_id).cloned())
        .collect::<Vec<_>>();

    Ok(Some(build_overview_from_aggregate(player_aggregate, &peers)))
}

fn build_legacy_overview(
    state: &StateManager,
    player_id: &str,
) -> Result<PlayerStatsOverviewDto, String> {
    let game = state
        .get_game(|game| game.clone())
        .ok_or("No active game session".to_string())?;
    let Some(player) = game.players.iter().find(|candidate| candidate.id == player_id) else {
        return Err("Player not found".to_string());
    };
    let target_position = position_key(player).clone();
    let peers = game
        .players
        .iter()
        .filter(|candidate| *position_key(candidate) == target_position)
        .map(|candidate| aggregate_from_season_stats(&candidate.stats))
        .collect::<Vec<_>>();

    Ok(build_overview_from_aggregate(
        &aggregate_from_season_stats(&player.stats),
        &peers,
    ))
}

fn aggregate_team_history(records: &[TeamMatchStatsRecord]) -> Option<TeamAggregate> {
    if records.is_empty() {
        return None;
    }

    let mut aggregate = TeamAggregate::default();
    for record in records {
        aggregate.matches_played += 1;
        aggregate.goals_for += record.goals_for as u32;
        aggregate.goals_against += record.goals_against as u32;
        aggregate.possession_total += record.possession_pct as u32;
        aggregate.shots += record.shots as u32;
        aggregate.shots_on_target += record.shots_on_target as u32;
        aggregate.passes_completed += record.passes_completed as u32;
        aggregate.passes_attempted += record.passes_attempted as u32;
        aggregate.tackles_won += record.tackles_won as u32;
        aggregate.interceptions += record.interceptions as u32;
        aggregate.fouls_committed += record.fouls_committed as u32;
    }

    Some(aggregate)
}

fn build_team_overview(aggregate: &TeamAggregate) -> TeamStatsOverviewDto {
    TeamStatsOverviewDto {
        matches_played: aggregate.matches_played,
        goals_for: aggregate.goals_for,
        goals_against: aggregate.goals_against,
        goal_difference: aggregate.goals_for as i32 - aggregate.goals_against as i32,
        possession_average: calculate_average(aggregate.possession_total, aggregate.matches_played),
        metrics: TeamStatsOverviewMetricsDto {
            shots: TeamAdvancedMetricDto {
                total: aggregate.shots,
                per_match: calculate_average(aggregate.shots, aggregate.matches_played),
            },
            shots_on_target: TeamAdvancedMetricDto {
                total: aggregate.shots_on_target,
                per_match: calculate_average(aggregate.shots_on_target, aggregate.matches_played),
            },
            passes: TeamAdvancedPassMetricDto {
                completed: aggregate.passes_completed,
                attempted: aggregate.passes_attempted,
                accuracy: calculate_pass_accuracy(
                    aggregate.passes_completed,
                    aggregate.passes_attempted,
                ),
            },
            tackles_won: TeamAdvancedMetricDto {
                total: aggregate.tackles_won,
                per_match: calculate_average(aggregate.tackles_won, aggregate.matches_played),
            },
            interceptions: TeamAdvancedMetricDto {
                total: aggregate.interceptions,
                per_match: calculate_average(aggregate.interceptions, aggregate.matches_played),
            },
            fouls_committed: TeamAdvancedMetricDto {
                total: aggregate.fouls_committed,
                per_match: calculate_average(aggregate.fouls_committed, aggregate.matches_played),
            },
        },
    }
}

fn to_team_history_dto(state: &StateManager, record: &TeamMatchStatsRecord) -> TeamMatchHistoryEntryDto {
    TeamMatchHistoryEntryDto {
        fixture_id: record.fixture_id.clone(),
        date: record.date.clone(),
        competition: match record.competition {
            domain::league::FixtureCompetition::League => "League".to_string(),
            domain::league::FixtureCompetition::Friendly => "Friendly".to_string(),
            domain::league::FixtureCompetition::PreseasonTournament => {
                "PreseasonTournament".to_string()
            }
        },
        matchday: record.matchday,
        opponent_team_id: record.opponent_team_id.clone(),
        opponent_name: opponent_name(state, &record.opponent_team_id),
        goals_for: record.goals_for,
        goals_against: record.goals_against,
        possession_pct: record.possession_pct,
        shots: record.shots,
        shots_on_target: record.shots_on_target,
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

pub fn get_player_stats_overview_internal(
    state: &StateManager,
    player_id: &str,
) -> Result<PlayerStatsOverviewDto, String> {
    if let Some(overview) = build_history_overview(state, player_id)? {
        return Ok(overview);
    }

    build_legacy_overview(state, player_id)
}

pub fn get_team_stats_overview_internal(
    state: &StateManager,
    team_id: &str,
) -> Result<Option<TeamStatsOverviewDto>, String> {
    let team_exists = state
        .get_game(|game| game.teams.iter().any(|team| team.id == team_id))
        .ok_or("No active game session".to_string())?;
    if !team_exists {
        return Err("Team not found".to_string());
    }

    let Some(records) = state.get_stats_state(|stats| {
        stats
            .team_matches
            .iter()
            .filter(|record| record.team_id == team_id)
            .cloned()
            .collect::<Vec<_>>()
    }) else {
        return Ok(None);
    };

    Ok(aggregate_team_history(&records).map(|aggregate| build_team_overview(&aggregate)))
}

pub fn get_team_match_history_internal(
    state: &StateManager,
    team_id: &str,
    limit: Option<usize>,
) -> Result<Vec<TeamMatchHistoryEntryDto>, String> {
    let team_exists = state
        .get_game(|game| game.teams.iter().any(|team| team.id == team_id))
        .ok_or("No active game session".to_string())?;
    if !team_exists {
        return Err("Team not found".to_string());
    }

    let Some(mut history) = state.get_stats_state(|stats| {
        stats
            .team_matches
            .iter()
            .filter(|record| record.team_id == team_id)
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
        .map(|record| to_team_history_dto(state, &record))
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

#[tauri::command]
pub fn get_player_stats_overview(
    state: State<'_, StateManager>,
    player_id: String,
) -> Result<PlayerStatsOverviewDto, String> {
    get_player_stats_overview_internal(&state, &player_id)
}

#[tauri::command]
pub fn get_team_stats_overview(
    state: State<'_, StateManager>,
    team_id: String,
) -> Result<Option<TeamStatsOverviewDto>, String> {
    get_team_stats_overview_internal(&state, &team_id)
}

#[tauri::command]
pub fn get_team_match_history(
    state: State<'_, StateManager>,
    team_id: String,
    limit: Option<usize>,
) -> Result<Vec<TeamMatchHistoryEntryDto>, String> {
    get_team_match_history_internal(&state, &team_id, limit)
}

#[cfg(test)]
mod tests {
    use super::{
        get_player_match_history_internal, get_player_stats_overview_internal,
        get_team_match_history_internal, get_team_stats_overview_internal,
    };
    use chrono::{TimeZone, Utc};
    use domain::league::FixtureCompetition;
    use domain::manager::Manager;
    use domain::player::{Player, PlayerAttributes, PlayerSeasonStats, Position};
    use domain::stats::{PlayerMatchStatsRecord, StatsState, TeamMatchStatsRecord};
    use domain::team::Team;
    use ofm_core::clock::GameClock;
    use ofm_core::game::Game;
    use ofm_core::state::StateManager;

    fn default_attrs() -> PlayerAttributes {
        PlayerAttributes {
            pace: 60,
            stamina: 60,
            strength: 60,
            agility: 60,
            passing: 60,
            shooting: 60,
            tackling: 60,
            dribbling: 60,
            defending: 60,
            positioning: 60,
            vision: 60,
            decisions: 60,
            composure: 60,
            aggression: 60,
            teamwork: 60,
            leadership: 60,
            handling: 60,
            reflexes: 60,
            aerial: 60,
        }
    }

    fn make_player(id: &str, team_id: &str, natural_position: Position) -> Player {
        let mut player = Player::new(
            id.to_string(),
            id.to_string(),
            id.to_string(),
            "2000-01-01".to_string(),
            "England".to_string(),
            natural_position.clone(),
            default_attrs(),
        );
        player.team_id = Some(team_id.to_string());
        player.natural_position = natural_position;
        player
    }

    fn make_game(players: Vec<Player>) -> Game {
        let clock = GameClock::new(Utc.with_ymd_and_hms(2025, 7, 1, 0, 0, 0).unwrap());
        let mut manager = Manager::new(
            "mgr-1".to_string(),
            "Alex".to_string(),
            "Manager".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        manager.hire("team-1".to_string());

        let mut team = Team::new(
            "team-1".to_string(),
            "Alpha FC".to_string(),
            "ALP".to_string(),
            "England".to_string(),
            "Alpha City".to_string(),
            "Alpha Ground".to_string(),
            20_000,
        );
        team.starting_xi_ids = players.iter().map(|player| player.id.clone()).collect();

        let opponent = Team::new(
            "team-2".to_string(),
            "Bravo FC".to_string(),
            "BRV".to_string(),
            "England".to_string(),
            "Bravo City".to_string(),
            "Bravo Ground".to_string(),
            18_000,
        );

        Game::new(clock, manager, vec![team, opponent], players, vec![], vec![])
    }

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

    fn sample_team_stats_state() -> StatsState {
        StatsState {
            player_matches: vec![],
            team_matches: vec![
                TeamMatchStatsRecord {
                    fixture_id: "fixture-1".to_string(),
                    season: 2025,
                    matchday: 1,
                    date: "2025-08-01".to_string(),
                    competition: FixtureCompetition::League,
                    team_id: "team-1".to_string(),
                    opponent_team_id: "team-2".to_string(),
                    home_team_id: "team-1".to_string(),
                    away_team_id: "team-2".to_string(),
                    goals_for: 2,
                    goals_against: 0,
                    possession_pct: 58,
                    shots: 14,
                    shots_on_target: 6,
                    passes_completed: 420,
                    passes_attempted: 500,
                    tackles_won: 18,
                    interceptions: 11,
                    fouls_committed: 9,
                    yellow_cards: 1,
                    red_cards: 0,
                },
                TeamMatchStatsRecord {
                    fixture_id: "fixture-2".to_string(),
                    season: 2026,
                    matchday: 1,
                    date: "2026-08-01".to_string(),
                    competition: FixtureCompetition::League,
                    team_id: "team-1".to_string(),
                    opponent_team_id: "team-2".to_string(),
                    home_team_id: "team-2".to_string(),
                    away_team_id: "team-1".to_string(),
                    goals_for: 3,
                    goals_against: 1,
                    possession_pct: 62,
                    shots: 16,
                    shots_on_target: 7,
                    passes_completed: 460,
                    passes_attempted: 540,
                    tackles_won: 20,
                    interceptions: 13,
                    fouls_committed: 10,
                    yellow_cards: 2,
                    red_cards: 0,
                },
            ],
        }
    }

    #[test]
    fn get_player_stats_overview_aggregates_history_and_uses_exact_position_cohorts() {
        let mut player = make_player("player-1", "team-1", Position::Striker);
        player.stats = PlayerSeasonStats {
            appearances: 1,
            goals: 1,
            assists: 1,
            clean_sheets: 0,
            yellow_cards: 0,
            red_cards: 0,
            avg_rating: 7.0,
            minutes_played: 90,
            shots: 2,
            shots_on_target: 1,
            passes_completed: 10,
            passes_attempted: 12,
            tackles_won: 1,
            interceptions: 0,
            fouls_committed: 1,
        };
        let peer_a = make_player("player-2", "team-1", Position::Striker);
        let peer_b = make_player("player-3", "team-1", Position::Striker);
        let broad_bucket_peer = make_player("player-4", "team-1", Position::Forward);

        let state = StateManager::new();
        state.set_game(make_game(vec![player, peer_a, peer_b, broad_bucket_peer]));
        state.set_stats_state(StatsState {
            player_matches: vec![
                PlayerMatchStatsRecord {
                    fixture_id: "fixture-a".to_string(),
                    season: 2025,
                    matchday: 1,
                    date: "2025-08-01".to_string(),
                    competition: FixtureCompetition::League,
                    player_id: "player-1".to_string(),
                    team_id: "team-1".to_string(),
                    opponent_team_id: "team-2".to_string(),
                    home_team_id: "team-1".to_string(),
                    away_team_id: "team-2".to_string(),
                    home_goals: 2,
                    away_goals: 0,
                    minutes_played: 90,
                    goals: 1,
                    assists: 1,
                    shots: 6,
                    shots_on_target: 3,
                    passes_completed: 25,
                    passes_attempted: 30,
                    tackles_won: 4,
                    interceptions: 2,
                    fouls_committed: 1,
                    yellow_cards: 0,
                    red_cards: 0,
                    rating: 8.1,
                },
                PlayerMatchStatsRecord {
                    fixture_id: "fixture-b".to_string(),
                    season: 2026,
                    matchday: 1,
                    date: "2026-08-01".to_string(),
                    competition: FixtureCompetition::League,
                    player_id: "player-1".to_string(),
                    team_id: "team-1".to_string(),
                    opponent_team_id: "team-2".to_string(),
                    home_team_id: "team-2".to_string(),
                    away_team_id: "team-1".to_string(),
                    home_goals: 1,
                    away_goals: 3,
                    minutes_played: 90,
                    goals: 2,
                    assists: 0,
                    shots: 4,
                    shots_on_target: 2,
                    passes_completed: 20,
                    passes_attempted: 25,
                    tackles_won: 2,
                    interceptions: 1,
                    fouls_committed: 2,
                    yellow_cards: 0,
                    red_cards: 0,
                    rating: 8.4,
                },
                PlayerMatchStatsRecord {
                    fixture_id: "fixture-peer-a-1".to_string(),
                    season: 2025,
                    matchday: 1,
                    date: "2025-08-01".to_string(),
                    competition: FixtureCompetition::League,
                    player_id: "player-2".to_string(),
                    team_id: "team-1".to_string(),
                    opponent_team_id: "team-2".to_string(),
                    home_team_id: "team-1".to_string(),
                    away_team_id: "team-2".to_string(),
                    home_goals: 1,
                    away_goals: 0,
                    minutes_played: 90,
                    goals: 0,
                    assists: 0,
                    shots: 2,
                    shots_on_target: 1,
                    passes_completed: 18,
                    passes_attempted: 24,
                    tackles_won: 1,
                    interceptions: 1,
                    fouls_committed: 1,
                    yellow_cards: 0,
                    red_cards: 0,
                    rating: 6.9,
                },
                PlayerMatchStatsRecord {
                    fixture_id: "fixture-peer-a-2".to_string(),
                    season: 2026,
                    matchday: 1,
                    date: "2026-08-01".to_string(),
                    competition: FixtureCompetition::League,
                    player_id: "player-2".to_string(),
                    team_id: "team-1".to_string(),
                    opponent_team_id: "team-2".to_string(),
                    home_team_id: "team-2".to_string(),
                    away_team_id: "team-1".to_string(),
                    home_goals: 1,
                    away_goals: 1,
                    minutes_played: 90,
                    goals: 1,
                    assists: 0,
                    shots: 3,
                    shots_on_target: 1,
                    passes_completed: 20,
                    passes_attempted: 28,
                    tackles_won: 2,
                    interceptions: 1,
                    fouls_committed: 2,
                    yellow_cards: 0,
                    red_cards: 0,
                    rating: 7.1,
                },
                PlayerMatchStatsRecord {
                    fixture_id: "fixture-peer-b-1".to_string(),
                    season: 2025,
                    matchday: 1,
                    date: "2025-08-01".to_string(),
                    competition: FixtureCompetition::League,
                    player_id: "player-3".to_string(),
                    team_id: "team-1".to_string(),
                    opponent_team_id: "team-2".to_string(),
                    home_team_id: "team-1".to_string(),
                    away_team_id: "team-2".to_string(),
                    home_goals: 0,
                    away_goals: 0,
                    minutes_played: 90,
                    goals: 0,
                    assists: 0,
                    shots: 3,
                    shots_on_target: 1,
                    passes_completed: 19,
                    passes_attempted: 24,
                    tackles_won: 2,
                    interceptions: 1,
                    fouls_committed: 1,
                    yellow_cards: 0,
                    red_cards: 0,
                    rating: 7.0,
                },
                PlayerMatchStatsRecord {
                    fixture_id: "fixture-peer-b-2".to_string(),
                    season: 2026,
                    matchday: 1,
                    date: "2026-08-01".to_string(),
                    competition: FixtureCompetition::League,
                    player_id: "player-3".to_string(),
                    team_id: "team-1".to_string(),
                    opponent_team_id: "team-2".to_string(),
                    home_team_id: "team-2".to_string(),
                    away_team_id: "team-1".to_string(),
                    home_goals: 0,
                    away_goals: 1,
                    minutes_played: 90,
                    goals: 0,
                    assists: 0,
                    shots: 4,
                    shots_on_target: 2,
                    passes_completed: 18,
                    passes_attempted: 22,
                    tackles_won: 1,
                    interceptions: 1,
                    fouls_committed: 1,
                    yellow_cards: 0,
                    red_cards: 0,
                    rating: 7.2,
                },
                PlayerMatchStatsRecord {
                    fixture_id: "fixture-forward-only-1".to_string(),
                    season: 2025,
                    matchday: 1,
                    date: "2025-08-01".to_string(),
                    competition: FixtureCompetition::League,
                    player_id: "player-4".to_string(),
                    team_id: "team-1".to_string(),
                    opponent_team_id: "team-2".to_string(),
                    home_team_id: "team-1".to_string(),
                    away_team_id: "team-2".to_string(),
                    home_goals: 1,
                    away_goals: 1,
                    minutes_played: 90,
                    goals: 0,
                    assists: 0,
                    shots: 30,
                    shots_on_target: 12,
                    passes_completed: 40,
                    passes_attempted: 45,
                    tackles_won: 1,
                    interceptions: 0,
                    fouls_committed: 2,
                    yellow_cards: 0,
                    red_cards: 0,
                    rating: 7.3,
                },
                PlayerMatchStatsRecord {
                    fixture_id: "fixture-forward-only-2".to_string(),
                    season: 2026,
                    matchday: 1,
                    date: "2026-08-01".to_string(),
                    competition: FixtureCompetition::League,
                    player_id: "player-4".to_string(),
                    team_id: "team-1".to_string(),
                    opponent_team_id: "team-2".to_string(),
                    home_team_id: "team-2".to_string(),
                    away_team_id: "team-1".to_string(),
                    home_goals: 0,
                    away_goals: 1,
                    minutes_played: 90,
                    goals: 0,
                    assists: 0,
                    shots: 30,
                    shots_on_target: 14,
                    passes_completed: 42,
                    passes_attempted: 48,
                    tackles_won: 1,
                    interceptions: 0,
                    fouls_committed: 2,
                    yellow_cards: 0,
                    red_cards: 0,
                    rating: 7.4,
                },
            ],
            team_matches: vec![],
        });

        let overview = get_player_stats_overview_internal(&state, "player-1").unwrap();

        assert!(overview.percentile_eligible);
        assert_eq!(overview.metrics.shots.total, 10);
        assert_eq!(overview.metrics.shots.per90, Some(5.0));
        assert_eq!(overview.metrics.shots.percentile, Some(100));
        assert_eq!(overview.metrics.passes.completed, 45);
        assert_eq!(overview.metrics.passes.attempted, 55);
        assert_eq!(overview.metrics.passes.accuracy, Some(81.8));
        assert_eq!(overview.metrics.passes.percentile, Some(100));
    }

    #[test]
    fn get_player_stats_overview_falls_back_to_current_season_totals_for_legacy_saves() {
        let mut player = make_player("player-1", "team-1", Position::Striker);
        player.stats = PlayerSeasonStats {
            appearances: 10,
            goals: 4,
            assists: 3,
            clean_sheets: 0,
            yellow_cards: 1,
            red_cards: 0,
            avg_rating: 7.2,
            minutes_played: 450,
            shots: 20,
            shots_on_target: 10,
            passes_completed: 80,
            passes_attempted: 100,
            tackles_won: 9,
            interceptions: 6,
            fouls_committed: 5,
        };
        let mut peer_a = make_player("player-2", "team-1", Position::Striker);
        peer_a.stats = PlayerSeasonStats {
            appearances: 10,
            goals: 2,
            assists: 2,
            clean_sheets: 0,
            yellow_cards: 0,
            red_cards: 0,
            avg_rating: 7.0,
            minutes_played: 450,
            shots: 10,
            shots_on_target: 5,
            passes_completed: 70,
            passes_attempted: 100,
            tackles_won: 6,
            interceptions: 4,
            fouls_committed: 3,
        };
        let mut peer_b = make_player("player-3", "team-1", Position::Striker);
        peer_b.stats = PlayerSeasonStats {
            appearances: 10,
            goals: 3,
            assists: 2,
            clean_sheets: 0,
            yellow_cards: 0,
            red_cards: 0,
            avg_rating: 7.0,
            minutes_played: 450,
            shots: 15,
            shots_on_target: 8,
            passes_completed: 75,
            passes_attempted: 100,
            tackles_won: 7,
            interceptions: 5,
            fouls_committed: 4,
        };

        let state = StateManager::new();
        state.set_game(make_game(vec![player, peer_a, peer_b]));

        let overview = get_player_stats_overview_internal(&state, "player-1").unwrap();

        assert!(overview.percentile_eligible);
        assert_eq!(overview.metrics.shots.total, 20);
        assert_eq!(overview.metrics.shots.per90, Some(4.0));
        assert_eq!(overview.metrics.passes.accuracy, Some(80.0));
        assert_eq!(overview.metrics.shots.percentile, Some(100));
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

    #[test]
    fn get_team_stats_overview_aggregates_totals_and_match_averages() {
        let state = StateManager::new();
        state.set_game(make_game(vec![make_player("player-1", "team-1", Position::Striker)]));
        state.set_stats_state(sample_team_stats_state());

        let overview = get_team_stats_overview_internal(&state, "team-1")
            .unwrap()
            .expect("expected team overview");

        assert_eq!(overview.matches_played, 2);
        assert_eq!(overview.goals_for, 5);
        assert_eq!(overview.goals_against, 1);
        assert_eq!(overview.goal_difference, 4);
        assert_eq!(overview.possession_average, Some(60.0));
        assert_eq!(overview.metrics.shots.total, 30);
        assert_eq!(overview.metrics.shots.per_match, Some(15.0));
        assert_eq!(overview.metrics.shots_on_target.total, 13);
        assert_eq!(overview.metrics.shots_on_target.per_match, Some(6.5));
        assert_eq!(overview.metrics.passes.completed, 880);
        assert_eq!(overview.metrics.passes.attempted, 1040);
        assert_eq!(overview.metrics.passes.accuracy, Some(84.6));
        assert_eq!(overview.metrics.tackles_won.per_match, Some(19.0));
    }

    #[test]
    fn get_team_stats_overview_returns_none_without_history() {
        let state = StateManager::new();
        state.set_game(make_game(vec![make_player("player-1", "team-1", Position::Striker)]));

        let overview = get_team_stats_overview_internal(&state, "team-1").unwrap();

        assert!(overview.is_none());
    }

    #[test]
    fn get_team_match_history_returns_latest_matches_first_with_limit() {
        let state = StateManager::new();
        state.set_game(make_game(vec![make_player("player-1", "team-1", Position::Striker)]));
        state.set_stats_state(sample_team_stats_state());

        let history = get_team_match_history_internal(&state, "team-1", Some(1)).unwrap();

        assert_eq!(history.len(), 1);
        assert_eq!(history[0].fixture_id, "fixture-2");
        assert_eq!(history[0].opponent_team_id, "team-2");
        assert_eq!(history[0].goals_for, 3);
        assert_eq!(history[0].goals_against, 1);
    }

    #[test]
    fn get_team_match_history_returns_empty_when_stats_state_is_missing() {
        let state = StateManager::new();
        state.set_game(make_game(vec![make_player("player-1", "team-1", Position::Striker)]));

        let history = get_team_match_history_internal(&state, "team-1", None).unwrap();

        assert!(history.is_empty());
    }
}