use crate::game::Game;
use crate::messages;
use domain::league::{FixtureStatus, GoalEvent, MatchResult};
use domain::player::Position as DomainPosition;

/// Process a single day advance.
pub fn process_day(game: &mut Game) {
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();

    let has_match_today = game.league.as_ref().map_or(false, |league| {
        league.fixtures.iter().any(|f| f.date == today && f.status == FixtureStatus::Scheduled)
    });

    if has_match_today {
        simulate_matchday(game, &today);
    } else {
        apply_training_recovery(game);
    }

    generate_pre_match_messages(game, &today);
    game.clock.advance_days(1);
}

// ---------------------------------------------------------------------------
// Domain → Engine type conversion
// ---------------------------------------------------------------------------

fn build_engine_team(game: &Game, team_id: &str) -> engine::TeamData {
    let team = game.teams.iter().find(|t| t.id == team_id);
    let (name, formation, play_style) = match team {
        Some(t) => (
            t.name.clone(),
            t.formation.clone(),
            match t.play_style {
                domain::team::PlayStyle::Attacking  => engine::PlayStyle::Attacking,
                domain::team::PlayStyle::Defensive  => engine::PlayStyle::Defensive,
                domain::team::PlayStyle::Possession  => engine::PlayStyle::Possession,
                domain::team::PlayStyle::Counter     => engine::PlayStyle::Counter,
                domain::team::PlayStyle::HighPress   => engine::PlayStyle::HighPress,
                _                                    => engine::PlayStyle::Balanced,
            },
        ),
        None => ("Unknown".into(), "4-4-2".into(), engine::PlayStyle::Balanced),
    };

    let players: Vec<engine::PlayerData> = game
        .players
        .iter()
        .filter(|p| p.team_id.as_deref() == Some(team_id))
        .map(|p| {
            let pos = match p.position {
                DomainPosition::Goalkeeper => engine::Position::Goalkeeper,
                DomainPosition::Defender   => engine::Position::Defender,
                DomainPosition::Midfielder => engine::Position::Midfielder,
                DomainPosition::Forward    => engine::Position::Forward,
            };
            engine::PlayerData {
                id: p.id.clone(),
                name: p.match_name.clone(),
                position: pos,
                condition: p.condition,
                pace: p.attributes.pace,
                stamina: p.attributes.stamina,
                strength: p.attributes.strength,
                passing: p.attributes.passing,
                shooting: p.attributes.shooting,
                tackling: p.attributes.tackling,
                dribbling: p.attributes.dribbling,
                defending: p.attributes.defending,
                positioning: p.attributes.positioning,
                vision: p.attributes.vision,
                decisions: p.attributes.decisions,
            }
        })
        .collect();

    engine::TeamData {
        id: team_id.to_string(),
        name,
        formation,
        play_style,
        players,
    }
}

// ---------------------------------------------------------------------------
// Matchday simulation using the engine crate
// ---------------------------------------------------------------------------

fn simulate_matchday(game: &mut Game, today: &str) {
    simulate_other_matches(game, today, None);
}

/// Simulate all scheduled matches for `today`, optionally skipping one fixture
/// (the user's live match). Called by both process_day and advance_time_with_mode.
pub fn simulate_other_matches(game: &mut Game, today: &str, skip_fixture: Option<usize>) {
    let fixture_indices: Vec<usize> = game.league.as_ref().map_or(vec![], |league| {
        league
            .fixtures
            .iter()
            .enumerate()
            .filter(|(i, f)| {
                f.date == today
                    && f.status == FixtureStatus::Scheduled
                    && skip_fixture.map_or(true, |skip| *i != skip)
            })
            .map(|(i, _)| i)
            .collect()
    });

    for idx in fixture_indices {
        simulate_single_match(game, idx);
    }
}

/// Simulate a single fixture by index using the engine and update game state.
fn simulate_single_match(game: &mut Game, idx: usize) {
    let (home_team_id, away_team_id) = {
        let f = &game.league.as_ref().unwrap().fixtures[idx];
        (f.home_team_id.clone(), f.away_team_id.clone())
    };

    let home_data = build_engine_team(game, &home_team_id);
    let away_data = build_engine_team(game, &away_team_id);
    let config = engine::MatchConfig::default();
    let report = engine::simulate(&home_data, &away_data, &config);

    apply_match_report(game, idx, &home_team_id, &away_team_id, &report);
}

/// Apply a completed match report to the game state: update fixture, standings,
/// player stats, stamina, and generate messages. Public so Tauri can call it
/// after a live match finishes.
pub fn apply_match_report(
    game: &mut Game,
    fixture_index: usize,
    home_team_id: &str,
    away_team_id: &str,
    report: &engine::MatchReport,
) {
    // Convert engine GoalDetails → domain GoalEvents
    let home_scorers: Vec<GoalEvent> = report
        .goals
        .iter()
        .filter(|g| g.side == engine::Side::Home)
        .map(|g| GoalEvent {
            player_id: g.scorer_id.clone(),
            minute: g.minute,
        })
        .collect();
    let away_scorers: Vec<GoalEvent> = report
        .goals
        .iter()
        .filter(|g| g.side == engine::Side::Away)
        .map(|g| GoalEvent {
            player_id: g.scorer_id.clone(),
            minute: g.minute,
        })
        .collect();

    let result = MatchResult {
        home_goals: report.home_goals,
        away_goals: report.away_goals,
        home_scorers,
        away_scorers,
    };

    // Update fixture status, standings
    if let Some(league) = game.league.as_mut() {
        let fixture = &mut league.fixtures[fixture_index];
        fixture.status = FixtureStatus::Completed;

        if let Some(entry) = league.standings.iter_mut().find(|e| e.team_id == home_team_id) {
            entry.record_result(result.home_goals, result.away_goals);
        }
        if let Some(entry) = league.standings.iter_mut().find(|e| e.team_id == away_team_id) {
            entry.record_result(result.away_goals, result.home_goals);
        }

        fixture.result = Some(result);
    }

    // Update player season stats from the engine report
    apply_player_stats(game, report, home_team_id, away_team_id);

    // Deplete stamina for players who played
    deplete_match_stamina(game, home_team_id);
    deplete_match_stamina(game, away_team_id);

    // Generate match result message for user's team
    if let Some(user_team_id) = &game.manager.team_id {
        if *user_team_id == home_team_id || *user_team_id == away_team_id {
            let fixture = &game.league.as_ref().unwrap().fixtures[fixture_index];
            let res = fixture.result.as_ref().unwrap();
            let home_name = game.teams.iter().find(|t| t.id == home_team_id).map(|t| t.name.as_str()).unwrap_or("Home");
            let away_name = game.teams.iter().find(|t| t.id == away_team_id).map(|t| t.name.as_str()).unwrap_or("Away");

            let msg = messages::match_result_message(
                &fixture.id,
                home_name,
                away_name,
                res.home_goals,
                res.away_goals,
                home_team_id,
                away_team_id,
                user_team_id,
                fixture.matchday,
                &game.clock.current_date.to_rfc3339(),
            );
            game.messages.push(msg);
        }
    }
}

// ---------------------------------------------------------------------------
// Post-match: feed engine report stats back into domain Player models
// ---------------------------------------------------------------------------

fn apply_player_stats(
    game: &mut Game,
    report: &engine::MatchReport,
    home_team_id: &str,
    away_team_id: &str,
) {
    for player in game.players.iter_mut() {
        if let Some(ps) = report.player_stats.get(&player.id) {
            player.stats.appearances += 1;
            player.stats.goals += ps.goals as u32;
            player.stats.assists += ps.assists as u32;
            player.stats.yellow_cards += ps.yellow_cards as u32;
            player.stats.red_cards += ps.red_cards as u32;
            player.stats.minutes_played += 90;

            // Update average rating (running average)
            if player.stats.appearances == 1 {
                player.stats.avg_rating = ps.rating;
            } else {
                let n = player.stats.appearances as f32;
                player.stats.avg_rating =
                    (player.stats.avg_rating * (n - 1.0) + ps.rating) / n;
            }

            // Clean sheet for goalkeepers
            if matches!(player.position, DomainPosition::Goalkeeper) {
                let tid = player.team_id.as_deref().unwrap_or("");
                let conceded_zero = if tid == home_team_id {
                    report.away_goals == 0
                } else if tid == away_team_id {
                    report.home_goals == 0
                } else {
                    false
                };
                if conceded_zero {
                    player.stats.clean_sheets += 1;
                }
            }
        }
    }
}

fn deplete_match_stamina(game: &mut Game, team_id: &str) {
    for player in game.players.iter_mut() {
        if player.team_id.as_deref() == Some(team_id) {
            let stamina_factor = player.attributes.stamina as f64 / 100.0;
            let depletion = (25.0 * (1.0 - stamina_factor * 0.5)) as u8;
            player.condition = player.condition.saturating_sub(depletion);
        }
    }
}

fn apply_training_recovery(game: &mut Game) {
    for player in game.players.iter_mut() {
        let recovery_factor = (player.attributes.stamina as f64 + player.attributes.strength as f64) / 200.0;
        let recovery = (3.0 + 5.0 * recovery_factor) as u8;
        player.condition = (player.condition + recovery).min(100);
    }
}

fn generate_pre_match_messages(game: &mut Game, today: &str) {
    let user_team_id = match &game.manager.team_id {
        Some(id) => id.clone(),
        None => return,
    };

    // Parse today's date to check 3 days ahead
    let today_date = match chrono::NaiveDate::parse_from_str(today, "%Y-%m-%d") {
        Ok(d) => d,
        Err(_) => return,
    };
    let target_date = today_date + chrono::Duration::days(3);
    let target_str = target_date.format("%Y-%m-%d").to_string();

    if let Some(league) = &game.league {
        let upcoming: Vec<_> = league.fixtures.iter()
            .filter(|f| {
                f.date == target_str
                    && f.status == FixtureStatus::Scheduled
                    && (f.home_team_id == user_team_id || f.away_team_id == user_team_id)
            })
            .collect();

        for fixture in upcoming {
            let opponent_id = if fixture.home_team_id == user_team_id {
                &fixture.away_team_id
            } else {
                &fixture.home_team_id
            };
            let opponent_name = game.teams.iter()
                .find(|t| t.id == *opponent_id)
                .map(|t| t.name.as_str())
                .unwrap_or("Unknown");
            let is_home = fixture.home_team_id == user_team_id;

            // Check if we already sent this message
            let msg_id = format!("prematch_{}", fixture.id);
            let already_sent = game.messages.iter().any(|m| m.id == msg_id);
            if already_sent {
                continue;
            }

            let msg = messages::pre_match_message(
                &fixture.id,
                opponent_name,
                is_home,
                fixture.matchday,
                &target_str,
                &game.clock.current_date.to_rfc3339(),
            );
            game.messages.push(msg);
        }
    }
}
