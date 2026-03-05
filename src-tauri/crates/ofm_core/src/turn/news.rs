use crate::game::Game;
use crate::messages;
use crate::news;
use domain::league::FixtureStatus;

/// Generate a match report news article for the completed fixture.
pub(super) fn generate_match_news(
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

    let home_name = game
        .teams
        .iter()
        .find(|t| t.id == home_team_id)
        .map(|t| t.name.as_str())
        .unwrap_or("Home");
    let away_name = game
        .teams
        .iter()
        .find(|t| t.id == away_team_id)
        .map(|t| t.name.as_str())
        .unwrap_or("Away");

    // Build scorer lists with player names
    let home_scorers: Vec<(String, u32)> = report
        .goals
        .iter()
        .filter(|g| g.side == engine::Side::Home)
        .map(|g| {
            let name = game
                .players
                .iter()
                .find(|p| p.id == g.scorer_id)
                .map(|p| p.match_name.clone())
                .unwrap_or_else(|| g.scorer_id.clone());
            (name, g.minute as u32)
        })
        .collect();
    let away_scorers: Vec<(String, u32)> = report
        .goals
        .iter()
        .filter(|g| g.side == engine::Side::Away)
        .map(|g| {
            let name = game
                .players
                .iter()
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
    let todays_fixtures: Vec<_> = league
        .fixtures
        .iter()
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
    let results: Vec<(String, u8, String, u8)> = todays_fixtures
        .iter()
        .map(|f| {
            let home_name = game
                .teams
                .iter()
                .find(|t| t.id == f.home_team_id)
                .map(|t| t.name.clone())
                .unwrap_or_default();
            let away_name = game
                .teams
                .iter()
                .find(|t| t.id == f.away_team_id)
                .map(|t| t.name.clone())
                .unwrap_or_default();
            let (hg, ag) = f
                .result
                .as_ref()
                .map(|r| (r.home_goals, r.away_goals))
                .unwrap_or((0, 0));
            (home_name, hg, away_name, ag)
        })
        .collect();

    let roundup = news::league_roundup_article(matchday, &results, &date_str);
    game.news.push(roundup);

    // Standings update
    let mut standings: Vec<(String, u32, i16)> = league
        .standings
        .iter()
        .map(|e| {
            let name = game
                .teams
                .iter()
                .find(|t| t.id == e.team_id)
                .map(|t| t.name.clone())
                .unwrap_or_default();
            (name, e.points, e.goal_difference() as i16)
        })
        .collect();
    standings.sort_by(|a, b| b.1.cmp(&a.1).then(b.2.cmp(&a.2)));

    let standings_article = news::standings_update_article(matchday, &standings, &date_str);
    game.news.push(standings_article);
}

pub(super) fn generate_pre_match_messages(game: &mut Game, today: &str) {
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
        let upcoming: Vec<_> = league
            .fixtures
            .iter()
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
            let opponent_name = game
                .teams
                .iter()
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
