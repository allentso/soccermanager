mod match_report;
pub use match_report::match_report_article;

use domain::news::*;
use rand::Rng;
use std::collections::HashMap;

/// Helper to build a HashMap<String, String> from key-value pairs.
fn params(pairs: &[(&str, &str)]) -> HashMap<String, String> {
    pairs
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

fn result_lines(results: &[(String, u8, String, u8)]) -> Vec<String> {
    results
        .iter()
        .map(|(home, hg, away, ag)| format!("  {} {} - {} {}", home, hg, ag, away))
        .collect()
}

fn biggest_winner_name(results: &[(String, u8, String, u8)]) -> String {
    results
        .iter()
        .filter(|(_, hg, _, ag)| hg != ag)
        .max_by_key(|(_, hg, _, ag)| (*hg as i8 - *ag as i8).unsigned_abs())
        .map(
            |(home, hg, away, ag)| {
                if hg > ag { home.clone() } else { away.clone() }
            },
        )
        .unwrap_or_default()
}

/// Generate a league roundup article summarising all matchday results.
pub fn league_roundup_article(
    matchday: u32,
    results: &[(String, u8, String, u8)], // (home_name, home_goals, away_name, away_goals)
    date: &str,
) -> NewsArticle {
    let mut rng = rand::thread_rng();
    let results_text = result_lines(results);
    let biggest_winner = biggest_winner_name(results);

    let mut body = format!(
        "Matchday {} is in the books. Here are the full results:\n",
        matchday
    );
    for line in &results_text {
        body.push_str(&format!("\n{}", line));
    }

    let total_goals: u8 = results.iter().map(|(_, hg, _, ag)| hg + ag).sum();
    body.push_str(&format!(
        "\n\n{} goals scored across {} matches. ",
        total_goals,
        results.len()
    ));

    if !biggest_winner.is_empty() {
        body.push_str(&format!(
            "{} recorded the biggest win of the day.",
            biggest_winner
        ));
    }

    let headlines = [
        format!(
            "Matchday {} Round-Up: {} Goals in Action-Packed Day",
            matchday, total_goals
        ),
        format!("Premier Division Matchday {}: All the Results", matchday),
        format!("Goals Galore in Matchday {} Action", matchday),
    ];

    let source_keys = [
        "be.source.leagueWire",
        "be.source.footballHerald",
        "be.source.sportsGazette",
    ];
    let sources = ["League Wire", "The Football Herald", "Sports Gazette"];
    let src_idx = rng.gen_range(0..sources.len());
    let headline_idx = rng.gen_range(0..headlines.len());

    NewsArticle::new(
        format!("roundup_md{}", matchday),
        headlines[headline_idx].clone(),
        body,
        sources[src_idx].to_string(),
        date.to_string(),
        NewsCategory::LeagueRoundup,
    )
    .with_i18n(
        &format!("be.news.roundup.headline{}", headline_idx),
        "be.news.roundup.body",
        source_keys[src_idx],
        params(&[
            ("matchday", &matchday.to_string()),
            ("totalGoals", &total_goals.to_string()),
            ("matchCount", &results.len().to_string()),
            ("results", &results_text.join("\n")),
            ("biggestWinner", &biggest_winner),
        ]),
    )
}

/// Generate a standings update article after a matchday.
pub fn standings_update_article(
    matchday: u32,
    top_teams: &[(String, u32, i16)], // (team_name, points, goal_diff)
    date: &str,
) -> NewsArticle {
    let mut rng = rand::thread_rng();

    let leader = top_teams
        .first()
        .map(|(n, _, _)| n.as_str())
        .unwrap_or("Unknown");
    let mut body = format!(
        "After Matchday {}, {} sit at the top of the Premier Division table.\n\nStandings:",
        matchday, leader
    );

    for (i, (name, pts, gd)) in top_teams.iter().enumerate() {
        let gd_str = if *gd >= 0 {
            format!("+{}", gd)
        } else {
            format!("{}", gd)
        };
        body.push_str(&format!(
            "\n  {}. {} — {} pts (GD: {})",
            i + 1,
            name,
            pts,
            gd_str
        ));
    }

    let headlines = [
        format!("{} Lead the Way After Matchday {}", leader, matchday),
        format!("Premier Division Table: {} on Top", leader),
        format!("Standings Update — Matchday {}", matchday),
    ];

    let source_keys = [
        "be.source.leagueWire",
        "be.source.footballHerald",
        "be.source.leagueChronicle",
    ];
    let sources = ["League Wire", "The Football Herald", "League Chronicle"];
    let src_idx = rng.gen_range(0..sources.len());
    let headline_idx = rng.gen_range(0..headlines.len());

    // Build standings text for i18n
    let standings_text: Vec<String> = top_teams
        .iter()
        .enumerate()
        .map(|(i, (name, pts, gd))| {
            let gd_str = if *gd >= 0 {
                format!("+{}", gd)
            } else {
                format!("{}", gd)
            };
            format!("  {}. {} — {} pts (GD: {})", i + 1, name, pts, gd_str)
        })
        .collect();

    NewsArticle::new(
        format!("standings_md{}", matchday),
        headlines[headline_idx].clone(),
        body,
        sources[src_idx].to_string(),
        date.to_string(),
        NewsCategory::StandingsUpdate,
    )
    .with_i18n(
        &format!("be.news.standings.headline{}", headline_idx),
        "be.news.standings.body",
        source_keys[src_idx],
        params(&[
            ("matchday", &matchday.to_string()),
            ("leader", leader),
            ("standings", &standings_text.join("\n")),
        ]),
    )
}

/// Generate a season preview article at the start of the season.
pub fn season_preview_article(team_names: &[String], date: &str) -> NewsArticle {
    let mut rng = rand::thread_rng();

    let favourite = &team_names[rng.gen_range(0..team_names.len())];
    let dark_horse = loop {
        let pick = &team_names[rng.gen_range(0..team_names.len())];
        if pick != favourite {
            break pick;
        }
    };

    let body = format!(
        "The Premier Division is set to kick off with {} teams vying for the title.\n\n\
        Pre-season predictions have {} as the early favourites, but {} could be the dark horse \
        to watch this campaign.\n\n\
        With new managers taking the reins at some clubs, this season promises to be one of the \
        most competitive in recent memory. Every point will matter as the race for the title \
        heats up.\n\n\
        Teams: {}",
        team_names.len(),
        favourite,
        dark_horse,
        team_names.join(", ")
    );

    let headlines = [
        format!(
            "Season Preview: {} Teams Battle for Glory",
            team_names.len()
        ),
        "Premier Division Season Set to Begin".to_string(),
        format!("Can {} Claim the Title? Season Preview", favourite),
    ];

    let headline_idx = rng.gen_range(0..headlines.len());

    NewsArticle::new(
        "season_preview".to_string(),
        headlines[headline_idx].clone(),
        body,
        "The Football Herald".to_string(),
        date.to_string(),
        NewsCategory::SeasonPreview,
    )
    .with_i18n(
        &format!("be.news.seasonPreview.headline{}", headline_idx),
        "be.news.seasonPreview.body",
        "be.source.footballHerald",
        params(&[
            ("teamCount", &team_names.len().to_string()),
            ("favourite", favourite),
            ("darkHorse", dark_horse),
            ("teamList", &team_names.join(", ")),
        ]),
    )
}

#[cfg(test)]
mod tests {
    use super::league_roundup_article;
    use domain::news::NewsCategory;

    fn assert_valid_roundup_source_pair(source: &str, source_key: &str) {
        let valid = [
            ("League Wire", "be.source.leagueWire"),
            ("The Football Herald", "be.source.footballHerald"),
            ("Sports Gazette", "be.source.sportsGazette"),
        ];

        assert!(
            valid
                .iter()
                .any(|pair| pair.0 == source && pair.1 == source_key)
        );
    }

    #[test]
    fn league_roundup_article_includes_results_totals_and_biggest_winner() {
        let results = vec![
            ("Alpha FC".to_string(), 3, "Beta FC".to_string(), 0),
            ("Gamma FC".to_string(), 1, "Delta FC".to_string(), 1),
        ];

        let article = league_roundup_article(4, &results, "2025-08-12");

        assert_eq!(article.id, "roundup_md4");
        assert_eq!(article.category, NewsCategory::LeagueRoundup);
        assert!(article.body.contains("Matchday 4 is in the books."));
        assert!(article.body.contains("Alpha FC 3 - 0 Beta FC"));
        assert!(article.body.contains("Gamma FC 1 - 1 Delta FC"));
        assert!(article.body.contains("5 goals scored across 2 matches."));
        assert!(
            article
                .body
                .contains("Alpha FC recorded the biggest win of the day.")
        );
        assert!(
            [
                "be.news.roundup.headline0",
                "be.news.roundup.headline1",
                "be.news.roundup.headline2"
            ]
            .contains(&article.headline_key.as_deref().unwrap())
        );
        assert_eq!(article.body_key.as_deref(), Some("be.news.roundup.body"));
        assert_valid_roundup_source_pair(&article.source, article.source_key.as_deref().unwrap());
        assert_eq!(article.i18n_params.get("matchday"), Some(&"4".to_string()));
        assert_eq!(
            article.i18n_params.get("totalGoals"),
            Some(&"5".to_string())
        );
        assert_eq!(
            article.i18n_params.get("matchCount"),
            Some(&"2".to_string())
        );
        assert_eq!(
            article.i18n_params.get("results"),
            Some(&"  Alpha FC 3 - 0 Beta FC\n  Gamma FC 1 - 1 Delta FC".to_string())
        );
        assert_eq!(
            article.i18n_params.get("biggestWinner"),
            Some(&"Alpha FC".to_string())
        );
    }

    #[test]
    fn league_roundup_article_leaves_biggest_winner_empty_when_all_matches_are_draws() {
        let results = vec![
            ("Alpha FC".to_string(), 1, "Beta FC".to_string(), 1),
            ("Gamma FC".to_string(), 0, "Delta FC".to_string(), 0),
        ];

        let article = league_roundup_article(5, &results, "2025-08-19");

        assert!(!article.body.contains("recorded the biggest win of the day"));
        assert_eq!(
            article.i18n_params.get("biggestWinner"),
            Some(&String::new())
        );
    }
}
