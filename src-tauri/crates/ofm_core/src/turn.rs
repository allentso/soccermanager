use crate::board_objectives;
use crate::game::Game;
use crate::messages;
use crate::news;
use crate::player_events;
use crate::random_events;
use crate::scouting;
use crate::training;
use chrono::Datelike;
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
        let weekday_num = game.clock.current_date.weekday().num_days_from_monday();
        training::process_training(game, weekday_num);
        training::check_squad_fitness_warnings(game);
    }

    // Weekly financial processing (wages, matchday income, warnings)
    crate::finances::process_weekly_finances(game);

    // Board objectives (generate if missing, update progress)
    board_objectives::generate_objectives(game);
    board_objectives::update_objective_progress(game);

    // Player conversations, random events, and scouting
    player_events::check_player_events(game);
    random_events::check_random_events(game);
    scouting::process_scouting(game);

    generate_pre_match_messages(game, &today);
    game.clock.advance_days(1);
}

/// Called after a live match finishes to complete the day:
/// generates matchday news, pre-match messages, and advances the clock by one day.
pub fn finish_live_match_day(game: &mut Game) {
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    generate_matchday_news(game, &today);

    board_objectives::generate_objectives(game);
    board_objectives::update_objective_progress(game);

    player_events::check_player_events(game);
    random_events::check_random_events(game);
    scouting::process_scouting(game);
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
                agility: p.attributes.agility,
                passing: p.attributes.passing,
                shooting: p.attributes.shooting,
                tackling: p.attributes.tackling,
                dribbling: p.attributes.dribbling,
                defending: p.attributes.defending,
                positioning: p.attributes.positioning,
                vision: p.attributes.vision,
                decisions: p.attributes.decisions,
                composure: p.attributes.composure,
                aggression: p.attributes.aggression,
                teamwork: p.attributes.teamwork,
                leadership: p.attributes.leadership,
                handling: p.attributes.handling,
                reflexes: p.attributes.reflexes,
                aerial: p.attributes.aerial,
                traits: p.traits.iter().map(|t| format!("{:?}", t)).collect(),
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
    generate_matchday_news(game, today);
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

    // Update morale based on result and individual performance
    update_post_match_morale(game, report, home_team_id, away_team_id);

    // Update team form (last 5 results)
    update_team_form(game, report, home_team_id, away_team_id);

    // Update board satisfaction based on match result
    if let Some(user_team_id) = &game.manager.team_id {
        if *user_team_id == home_team_id || *user_team_id == away_team_id {
            let user_goals = if *user_team_id == home_team_id { report.home_goals } else { report.away_goals };
            let opp_goals = if *user_team_id == home_team_id { report.away_goals } else { report.home_goals };
            let sat_delta: i8 = if user_goals > opp_goals { 2 }        // win: +2
                               else if user_goals == opp_goals { -1 }  // draw: -1
                               else { -3 };                            // loss: -3
            let new_sat = (game.manager.satisfaction as i16 + sat_delta as i16).clamp(0, 100) as u8;
            game.manager.satisfaction = new_sat;

            // Fan approval — fans react more emotionally
            let fan_delta: i8 = if user_goals > opp_goals { 5 }         // win: +5
                               else if user_goals == opp_goals { -2 }   // draw: -2
                               else { -8 };                             // loss: -8
            // Extra bonus for big wins, extra penalty for heavy losses
            let goal_diff = (user_goals as i8) - (opp_goals as i8);
            let fan_bonus: i8 = if goal_diff >= 3 { 3 } else if goal_diff <= -3 { -3 } else { 0 };
            let new_fan = (game.manager.fan_approval as i16 + fan_delta as i16 + fan_bonus as i16).clamp(0, 100) as u8;
            game.manager.fan_approval = new_fan;
        }
    }

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

    // Generate match report news article
    generate_match_news(game, fixture_index, home_team_id, away_team_id, report);
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

/// Update player morale based on match result and individual performance.
fn update_post_match_morale(
    game: &mut Game,
    report: &engine::MatchReport,
    home_team_id: &str,
    away_team_id: &str,
) {
    use rand::Rng;
    let mut rng = rand::thread_rng();

    let home_won = report.home_goals > report.away_goals;
    let away_won = report.away_goals > report.home_goals;
    let is_draw = report.home_goals == report.away_goals;

    for player in game.players.iter_mut() {
        let tid = match player.team_id.as_deref() {
            Some(t) if t == home_team_id || t == away_team_id => t.to_string(),
            _ => continue,
        };

        let is_home = tid == home_team_id;
        let base_morale = player.morale as i16;

        // Team result effect
        let result_delta: i16 = if (is_home && home_won) || (!is_home && away_won) {
            rng.gen_range(3..=8) // Win boost
        } else if is_draw {
            rng.gen_range(-2..=3) // Draw: mild
        } else {
            rng.gen_range(-8..=-2) // Loss drop
        };

        // Individual performance effect
        let mut individual_delta: i16 = 0;
        if let Some(ps) = report.player_stats.get(&player.id) {
            // Goals scored boost morale
            individual_delta += ps.goals as i16 * 3;
            // Assists boost morale
            individual_delta += ps.assists as i16 * 2;
            // Red card tanks morale
            if ps.red_cards > 0 {
                individual_delta -= 8;
            }
            // Poor rating lowers morale
            if ps.rating < 5.5 {
                individual_delta -= 3;
            } else if ps.rating > 7.5 {
                individual_delta += 2;
            }
        }

        let total_delta = result_delta + individual_delta;
        let new_morale = (base_morale + total_delta).clamp(10, 100) as u8;
        player.morale = new_morale;
    }
}

/// Update team form vectors after a match result. Keeps last 5 results.
/// Also applies streak-based morale bonus/penalty to all players on teams with streaks.
fn update_team_form(
    game: &mut Game,
    report: &engine::MatchReport,
    home_team_id: &str,
    away_team_id: &str,
) {
    use rand::Rng;
    let mut rng = rand::thread_rng();

    let home_result = if report.home_goals > report.away_goals { "W" }
        else if report.home_goals < report.away_goals { "L" }
        else { "D" };
    let away_result = if report.away_goals > report.home_goals { "W" }
        else if report.away_goals < report.home_goals { "L" }
        else { "D" };

    // Update form for both teams
    for (team_id_str, result) in [(home_team_id, home_result), (away_team_id, away_result)] {
        if let Some(team) = game.teams.iter_mut().find(|t| t.id == team_id_str) {
            team.form.push(result.to_string());
            if team.form.len() > 5 {
                team.form.remove(0);
            }
        }
    }

    // Apply streak-based morale bonus/penalty
    for team_id_str in [home_team_id, away_team_id] {
        let form = game.teams.iter().find(|t| t.id == team_id_str)
            .map(|t| t.form.clone())
            .unwrap_or_default();

        if form.len() >= 3 {
            let last3: Vec<&str> = form.iter().rev().take(3).map(|s| s.as_str()).collect();
            let streak_delta: i16 = if last3.iter().all(|r| *r == "W") {
                rng.gen_range(2..=5) // 3+ win streak: small global morale boost
            } else if last3.iter().all(|r| *r == "L") {
                rng.gen_range(-5..=-2) // 3+ loss streak: morale drop
            } else {
                0
            };

            if streak_delta != 0 {
                for player in game.players.iter_mut() {
                    if player.team_id.as_deref() == Some(team_id_str) {
                        let base = player.morale as i16;
                        player.morale = (base + streak_delta).clamp(10, 100) as u8;
                    }
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

/// Generate a match report news article for the completed fixture.
fn generate_match_news(
    game: &mut Game,
    fixture_index: usize,
    home_team_id: &str,
    away_team_id: &str,
    report: &engine::MatchReport,
) {
    let fixture = &game.league.as_ref().unwrap().fixtures[fixture_index];
    let article_id = format!("report_{}", fixture.id);
    if game.news.iter().any(|n| n.id == article_id) {
        return;
    }

    let home_name = game.teams.iter().find(|t| t.id == home_team_id).map(|t| t.name.as_str()).unwrap_or("Home");
    let away_name = game.teams.iter().find(|t| t.id == away_team_id).map(|t| t.name.as_str()).unwrap_or("Away");

    // Build scorer lists with player names
    let home_scorers: Vec<(String, u32)> = report.goals.iter()
        .filter(|g| g.side == engine::Side::Home)
        .map(|g| {
            let name = game.players.iter()
                .find(|p| p.id == g.scorer_id)
                .map(|p| p.match_name.clone())
                .unwrap_or_else(|| g.scorer_id.clone());
            (name, g.minute as u32)
        })
        .collect();
    let away_scorers: Vec<(String, u32)> = report.goals.iter()
        .filter(|g| g.side == engine::Side::Away)
        .map(|g| {
            let name = game.players.iter()
                .find(|p| p.id == g.scorer_id)
                .map(|p| p.match_name.clone())
                .unwrap_or_else(|| g.scorer_id.clone());
            (name, g.minute as u32)
        })
        .collect();

    let article = news::match_report_article(
        &fixture.id,
        home_name,
        away_name,
        report.home_goals,
        report.away_goals,
        home_team_id,
        away_team_id,
        fixture.matchday,
        &home_scorers,
        &away_scorers,
        &game.clock.current_date.to_rfc3339(),
    );
    game.news.push(article);
}

/// After all matches in a matchday are simulated, generate roundup + standings news.
pub fn generate_matchday_news(game: &mut Game, today: &str) {
    let league = match &game.league {
        Some(l) => l,
        None => return,
    };

    // Collect completed fixtures for today
    let todays_fixtures: Vec<_> = league.fixtures.iter()
        .filter(|f| f.date == today && f.status == FixtureStatus::Completed)
        .collect();

    if todays_fixtures.is_empty() {
        return;
    }

    let matchday = todays_fixtures[0].matchday;
    let date_str = game.clock.current_date.to_rfc3339();

    // Don't duplicate
    let roundup_id = format!("roundup_md{}", matchday);
    if game.news.iter().any(|n| n.id == roundup_id) {
        return;
    }

    // Build results list
    let results: Vec<(String, u8, String, u8)> = todays_fixtures.iter().map(|f| {
        let home_name = game.teams.iter().find(|t| t.id == f.home_team_id).map(|t| t.name.clone()).unwrap_or_default();
        let away_name = game.teams.iter().find(|t| t.id == f.away_team_id).map(|t| t.name.clone()).unwrap_or_default();
        let (hg, ag) = f.result.as_ref().map(|r| (r.home_goals, r.away_goals)).unwrap_or((0, 0));
        (home_name, hg, away_name, ag)
    }).collect();

    let roundup = news::league_roundup_article(matchday, &results, &date_str);
    game.news.push(roundup);

    // Standings update
    let mut standings: Vec<(String, u32, i16)> = league.standings.iter().map(|e| {
        let name = game.teams.iter().find(|t| t.id == e.team_id).map(|t| t.name.clone()).unwrap_or_default();
        (name, e.points, e.goal_difference() as i16)
    }).collect();
    standings.sort_by(|a, b| b.1.cmp(&a.1).then(b.2.cmp(&a.2)));

    let standings_article = news::standings_update_article(matchday, &standings, &date_str);
    game.news.push(standings_article);
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
                opponent_id,
                is_home,
                fixture.matchday,
                &target_str,
                &game.clock.current_date.to_rfc3339(),
            );
            game.messages.push(msg);
        }
    }
}
