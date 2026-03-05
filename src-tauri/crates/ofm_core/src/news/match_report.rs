use domain::news::*;
use rand::Rng;
use super::params;

/// Generate a match report news article for a completed fixture.
pub fn match_report_article(
    fixture_id: &str,
    home_name: &str,
    away_name: &str,
    home_goals: u8,
    away_goals: u8,
    home_team_id: &str,
    away_team_id: &str,
    matchday: u32,
    home_scorers: &[(String, u32)], // (player_name, minute)
    away_scorers: &[(String, u32)],
    date: &str,
) -> NewsArticle {
    let mut rng = rand::thread_rng();

    let result_text = if home_goals > away_goals {
        format!(
            "{} secured a {}-{} victory over {}",
            home_name, home_goals, away_goals, away_name
        )
    } else if away_goals > home_goals {
        format!(
            "{} claimed a {}-{} win against {}",
            away_name, away_goals, home_goals, home_name
        )
    } else {
        format!(
            "{} and {} played out a {}-{} draw",
            home_name, away_name, home_goals, away_goals
        )
    };

    let scorers_text = {
        let mut parts = Vec::new();
        for (name, min) in home_scorers {
            parts.push(format!("{} ({}', {})", name, min, home_name));
        }
        for (name, min) in away_scorers {
            parts.push(format!("{} ({}', {})", name, min, away_name));
        }
        if parts.is_empty() {
            String::new()
        } else {
            format!("\n\nGoals: {}", parts.join(", "))
        }
    };

    let commentary = [
        format!(
            "In Matchday {} action, {}. The result could have implications on the league standings as the season progresses.{}",
            matchday, result_text, scorers_text
        ),
        format!(
            "{} in a Matchday {} clash at {}. Both sides gave their all in an engaging contest.{}",
            result_text,
            matchday,
            if home_goals >= away_goals {
                format!("{}'s ground", home_name)
            } else {
                format!("{}'s ground", home_name)
            },
            scorers_text
        ),
        format!(
            "Matchday {} delivered another exciting encounter as {}. The fans were treated to a competitive fixture.{}",
            matchday, result_text, scorers_text
        ),
    ];

    let idx = rng.gen_range(0..commentary.len());

    let headline = if home_goals > away_goals {
        let headlines = [
            format!(
                "{} {} - {} {}: Hosts Triumph",
                home_name, home_goals, away_goals, away_name
            ),
            format!(
                "{} Edge Past {} in Matchday {}",
                home_name, away_name, matchday
            ),
            format!("Clinical {} See Off {}", home_name, away_name),
        ];
        headlines[rng.gen_range(0..headlines.len())].clone()
    } else if away_goals > home_goals {
        let headlines = [
            format!(
                "{} {} - {} {}: Visitors Strike",
                home_name, home_goals, away_goals, away_name
            ),
            format!("{} Stun {} on the Road", away_name, home_name),
            format!("Away Day Delight for {}", away_name),
        ];
        headlines[rng.gen_range(0..headlines.len())].clone()
    } else {
        let headlines = [
            format!(
                "{} {} - {} {}: Honours Even",
                home_name, home_goals, away_goals, away_name
            ),
            format!("{} and {} Share the Spoils", home_name, away_name),
            format!("Stalemate at {}'s Ground", home_name),
        ];
        headlines[rng.gen_range(0..headlines.len())].clone()
    };

    let source_keys = [
        "be.source.sportsGazette",
        "be.source.footballHerald",
        "be.source.matchDayPress",
        "be.source.leagueChronicle",
    ];
    let sources = [
        "Sports Gazette",
        "The Football Herald",
        "Match Day Press",
        "League Chronicle",
    ];
    let src_idx = rng.gen_range(0..sources.len());
    let source = sources[src_idx];
    let source_key = source_keys[src_idx];

    let mut player_ids: Vec<String> = Vec::new();
    for (name, _) in home_scorers.iter().chain(away_scorers.iter()) {
        player_ids.push(name.clone());
    }

    // Determine outcome for i18n key
    let outcome = if home_goals > away_goals {
        "homeWin"
    } else if away_goals > home_goals {
        "awayWin"
    } else {
        "draw"
    };
    let headline_variant = rng.gen_range(0..3u8);

    // Build scorers string for i18n
    let mut scorer_parts = Vec::new();
    for (name, min) in home_scorers {
        scorer_parts.push(format!("{} ({}', {})", name, min, home_name));
    }
    for (name, min) in away_scorers {
        scorer_parts.push(format!("{} ({}', {})", name, min, away_name));
    }

    NewsArticle::new(
        format!("report_{}", fixture_id),
        headline,
        commentary[idx].clone(),
        source.to_string(),
        date.to_string(),
        NewsCategory::MatchReport,
    )
    .with_teams(vec![home_team_id.to_string(), away_team_id.to_string()])
    .with_score(NewsMatchScore {
        home_team_id: home_team_id.to_string(),
        away_team_id: away_team_id.to_string(),
        home_goals,
        away_goals,
    })
    .with_i18n(
        &format!(
            "be.news.matchReport.headline.{}.{}",
            outcome, headline_variant
        ),
        &format!("be.news.matchReport.body{}", idx),
        source_key,
        {
            let mut p = params(&[
                ("home", home_name),
                ("away", away_name),
                ("homeGoals", &home_goals.to_string()),
                ("awayGoals", &away_goals.to_string()),
                ("matchday", &matchday.to_string()),
                ("scorers", &scorer_parts.join(", ")),
            ]);
            // For winner-specific headlines
            if home_goals > away_goals {
                p.insert("winner".to_string(), home_name.to_string());
                p.insert("loser".to_string(), away_name.to_string());
            } else if away_goals > home_goals {
                p.insert("winner".to_string(), away_name.to_string());
                p.insert("loser".to_string(), home_name.to_string());
            }
            p
        },
    )
}
