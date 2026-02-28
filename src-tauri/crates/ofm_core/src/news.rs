use domain::news::*;
use rand::Rng;

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
    home_scorers: &[(String, u32)],   // (player_name, minute)
    away_scorers: &[(String, u32)],
    date: &str,
) -> NewsArticle {
    let mut rng = rand::thread_rng();

    let result_text = if home_goals > away_goals {
        format!("{} secured a {}-{} victory over {}", home_name, home_goals, away_goals, away_name)
    } else if away_goals > home_goals {
        format!("{} claimed a {}-{} win against {}", away_name, away_goals, home_goals, home_name)
    } else {
        format!("{} and {} played out a {}-{} draw", home_name, away_name, home_goals, away_goals)
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
            if home_goals > away_goals || home_goals == away_goals { format!("{}'s ground", home_name) } else { format!("{}'s ground", home_name) },
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
            format!("{} {} - {} {}: Hosts Triumph", home_name, home_goals, away_goals, away_name),
            format!("{} Edge Past {} in Matchday {}", home_name, away_name, matchday),
            format!("Clinical {} See Off {}", home_name, away_name),
        ];
        headlines[rng.gen_range(0..headlines.len())].clone()
    } else if away_goals > home_goals {
        let headlines = [
            format!("{} {} - {} {}: Visitors Strike", home_name, home_goals, away_goals, away_name),
            format!("{} Stun {} on the Road", away_name, home_name),
            format!("Away Day Delight for {}", away_name),
        ];
        headlines[rng.gen_range(0..headlines.len())].clone()
    } else {
        let headlines = [
            format!("{} {} - {} {}: Honours Even", home_name, home_goals, away_goals, away_name),
            format!("{} and {} Share the Spoils", home_name, away_name),
            format!("Stalemate at {}'s Ground", home_name),
        ];
        headlines[rng.gen_range(0..headlines.len())].clone()
    };

    let sources = ["Sports Gazette", "The Football Herald", "Match Day Press", "League Chronicle"];
    let source = sources[rng.gen_range(0..sources.len())];

    let mut player_ids: Vec<String> = Vec::new();
    for (name, _) in home_scorers.iter().chain(away_scorers.iter()) {
        player_ids.push(name.clone());
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
}

/// Generate a league roundup article summarising all matchday results.
pub fn league_roundup_article(
    matchday: u32,
    results: &[(String, u8, String, u8)],  // (home_name, home_goals, away_name, away_goals)
    date: &str,
) -> NewsArticle {
    let mut rng = rand::thread_rng();

    let mut body = format!("Matchday {} is in the books. Here are the full results:\n", matchday);
    for (home, hg, away, ag) in results {
        body.push_str(&format!("\n  {} {} - {} {}", home, hg, ag, away));
    }

    let total_goals: u8 = results.iter().map(|(_, hg, _, ag)| hg + ag).sum();
    body.push_str(&format!(
        "\n\n{} goals scored across {} matches. ",
        total_goals,
        results.len()
    ));

    let biggest_win = results.iter()
        .max_by_key(|(_, hg, _, ag)| (*hg as i8 - *ag as i8).unsigned_abs());
    if let Some((home, hg, away, ag)) = biggest_win {
        if hg != ag {
            let winner = if hg > ag { home } else { away };
            body.push_str(&format!("{} recorded the biggest win of the day.", winner));
        }
    }

    let headlines = [
        format!("Matchday {} Round-Up: {} Goals in Action-Packed Day", matchday, total_goals),
        format!("Premier Division Matchday {}: All the Results", matchday),
        format!("Goals Galore in Matchday {} Action", matchday),
    ];

    let sources = ["League Wire", "The Football Herald", "Sports Gazette"];

    NewsArticle::new(
        format!("roundup_md{}", matchday),
        headlines[rng.gen_range(0..headlines.len())].clone(),
        body,
        sources[rng.gen_range(0..sources.len())].to_string(),
        date.to_string(),
        NewsCategory::LeagueRoundup,
    )
}

/// Generate a standings update article after a matchday.
pub fn standings_update_article(
    matchday: u32,
    top_teams: &[(String, u32, i16)],  // (team_name, points, goal_diff)
    date: &str,
) -> NewsArticle {
    let mut rng = rand::thread_rng();

    let leader = top_teams.first().map(|(n, _, _)| n.as_str()).unwrap_or("Unknown");
    let mut body = format!("After Matchday {}, {} sit at the top of the Premier Division table.\n\nStandings:", matchday, leader);

    for (i, (name, pts, gd)) in top_teams.iter().enumerate() {
        let gd_str = if *gd >= 0 { format!("+{}", gd) } else { format!("{}", gd) };
        body.push_str(&format!("\n  {}. {} — {} pts (GD: {})", i + 1, name, pts, gd_str));
    }

    let headlines = [
        format!("{} Lead the Way After Matchday {}", leader, matchday),
        format!("Premier Division Table: {} on Top", leader),
        format!("Standings Update — Matchday {}", matchday),
    ];

    let sources = ["League Wire", "The Football Herald", "League Chronicle"];

    NewsArticle::new(
        format!("standings_md{}", matchday),
        headlines[rng.gen_range(0..headlines.len())].clone(),
        body,
        sources[rng.gen_range(0..sources.len())].to_string(),
        date.to_string(),
        NewsCategory::StandingsUpdate,
    )
}

/// Generate a season preview article at the start of the season.
pub fn season_preview_article(
    team_names: &[String],
    date: &str,
) -> NewsArticle {
    let mut rng = rand::thread_rng();

    let favourite = &team_names[rng.gen_range(0..team_names.len())];
    let dark_horse = loop {
        let pick = &team_names[rng.gen_range(0..team_names.len())];
        if pick != favourite { break pick; }
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
        format!("Season Preview: {} Teams Battle for Glory", team_names.len()),
        "Premier Division Season Set to Begin".to_string(),
        format!("Can {} Claim the Title? Season Preview", favourite),
    ];

    NewsArticle::new(
        "season_preview".to_string(),
        headlines[rng.gen_range(0..headlines.len())].clone(),
        body,
        "The Football Herald".to_string(),
        date.to_string(),
        NewsCategory::SeasonPreview,
    )
}
