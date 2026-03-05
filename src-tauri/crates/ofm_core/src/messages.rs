use domain::message::*;
use rand::Rng;
use std::collections::HashMap;

/// Helper to build a HashMap<String, String> from key-value pairs.
fn params(pairs: &[(&str, &str)]) -> HashMap<String, String> {
    pairs
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

/// Helper to create a MessageAction with an i18n label key.
fn action(id: &str, label: &str, label_key: &str, action_type: ActionType) -> MessageAction {
    MessageAction {
        id: id.to_string(),
        label: label.to_string(),
        action_type,
        resolved: false,
        label_key: Some(label_key.to_string()),
    }
}

/// Message template system — generates rich messages with variations.

pub fn welcome_message(team_name: &str, team_id: &str, date: &str) -> InboxMessage {
    let mut rng = rand::thread_rng();
    let variations = [
        (
            format!("Welcome to {}", team_name),
            format!(
                "The board of directors at {} is delighted to welcome you as the new manager.\n\n\
                We have high hopes for your tenure and believe you can lead this club to glory. \
                Your first task will be to review the squad and prepare a tactical plan for the upcoming season.\n\n\
                We wish you the best of luck.",
                team_name
            ),
        ),
        (
            format!("New Era at {}", team_name),
            format!(
                "On behalf of the entire {} family, we are thrilled to announce your appointment as manager.\n\n\
                The fans are eager to see your vision for the team. Please take time to assess the squad, \
                review our financial position, and set your tactical approach.\n\n\
                The board stands behind you.",
                team_name
            ),
        ),
        (
            format!("{} Awaits Your Leadership", team_name),
            format!(
                "Welcome to {}! The supporters and staff are excited about the future under your guidance.\n\n\
                We recommend you start by reviewing your squad's strengths and weaknesses, \
                then set up your preferred formation and training regime.\n\n\
                The upcoming season will be a true test — make us proud.",
                team_name
            ),
        ),
    ];

    let idx = rng.gen_range(0..variations.len());
    let (subject, body) = &variations[idx];

    InboxMessage::new(
        "welcome_1".to_string(),
        subject.clone(),
        body.clone(),
        "Board of Directors".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::Welcome)
    .with_priority(MessagePriority::High)
    .with_sender_role("Chairman")
    .with_action(action(
        "review_squad",
        "Review Squad",
        "be.msg.welcome.actionReview",
        ActionType::NavigateTo {
            route: "/dashboard?tab=Squad".to_string(),
        },
    ))
    .with_action(action(
        "ack_welcome",
        "Thank the Board",
        "be.msg.welcome.actionThank",
        ActionType::Acknowledge,
    ))
    .with_context(MessageContext {
        team_id: Some(team_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        &format!("be.msg.welcome.subject{}", idx),
        &format!("be.msg.welcome.body{}", idx),
        params(&[("team", team_name)]),
    )
    .with_sender_i18n("be.sender.boardOfDirectors", "be.role.chairman")
}

pub fn season_schedule_message(league_name: &str, season_start: &str, date: &str) -> InboxMessage {
    let mut rng = rand::thread_rng();
    let variations = [
        format!(
            "The {} schedule has been released. The season kicks off on {}.\n\n\
            Review the fixture list and ensure your squad is ready for the challenges ahead. \
            Pre-season preparation will be crucial.",
            league_name, season_start
        ),
        format!(
            "Fixture list confirmed! The {} season begins on {}.\n\n\
            Study the opening fixtures carefully — a strong start can set the tone for the whole campaign. \
            Make sure your key players are match-fit.",
            league_name, season_start
        ),
    ];

    let idx = rng.gen_range(0..variations.len());

    InboxMessage::new(
        "season_1".to_string(),
        "Season Schedule Released".to_string(),
        variations[idx].clone(),
        "League Office".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::LeagueInfo)
    .with_priority(MessagePriority::Normal)
    .with_sender_role("Competition Secretary")
    .with_action(action(
        "view_schedule",
        "View Fixtures",
        "be.msg.schedule.actionView",
        ActionType::NavigateTo {
            route: "/dashboard?tab=Schedule".to_string(),
        },
    ))
    .with_i18n(
        "be.msg.schedule.subject",
        &format!("be.msg.schedule.body{}", idx),
        params(&[("league", league_name), ("start", season_start)]),
    )
    .with_sender_i18n("be.sender.leagueOffice", "be.role.competitionSecretary")
}

pub fn pre_match_message(
    fixture_id: &str,
    opponent_name: &str,
    opponent_id: &str,
    is_home: bool,
    matchday: u32,
    match_date: &str,
    date: &str,
) -> InboxMessage {
    let mut rng = rand::thread_rng();
    let venue = if is_home { "home" } else { "away" };

    let variations = [
        format!(
            "Your {} match against {} is coming up on {}.\n\n\
            Matchday {} of the Premier Division. Make sure your starting XI is in good shape and \
            your tactics are set.\n\n\
            {} advantage could be key in this one.",
            venue,
            opponent_name,
            match_date,
            matchday,
            if is_home {
                "Home"
            } else {
                "Matching their intensity away from home"
            }
        ),
        format!(
            "Reminder: you face {} {} in 3 days ({}).\n\n\
            This is Matchday {} — review your squad fitness and consider any tactical adjustments. \
            {}",
            opponent_name,
            venue,
            match_date,
            matchday,
            if is_home {
                "The fans will be behind you at home."
            } else {
                "Away form will be tested — pack your strongest lineup."
            }
        ),
    ];

    let idx = rng.gen_range(0..variations.len());

    InboxMessage::new(
        format!("prematch_{}", fixture_id),
        format!(
            "Upcoming: vs {} ({})",
            opponent_name,
            if is_home { "H" } else { "A" }
        ),
        variations[idx].clone(),
        "Assistant Manager".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::MatchPreview)
    .with_priority(MessagePriority::Normal)
    .with_sender_role("Assistant Manager")
    .with_action(action(
        "set_tactics",
        "Set Tactics",
        "be.msg.preMatch.actionTactics",
        ActionType::NavigateTo {
            route: "/dashboard?tab=Tactics".to_string(),
        },
    ))
    .with_action(action(
        "view_opponent",
        "Scout Opponent",
        "be.msg.preMatch.actionScout",
        ActionType::NavigateTo {
            route: format!("/team/{}", opponent_id),
        },
    ))
    .with_context(MessageContext {
        fixture_id: Some(fixture_id.to_string()),
        team_id: Some(opponent_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        "be.msg.preMatch.subject",
        &format!("be.msg.preMatch.body{}", idx),
        params(&[
            ("venue", venue),
            ("opponent", opponent_name),
            ("matchDate", match_date),
            ("matchday", &matchday.to_string()),
        ]),
    )
    .with_sender_i18n("be.sender.assistantManager", "be.role.assistantManager")
}

pub fn match_result_message(
    fixture_id: &str,
    home_name: &str,
    away_name: &str,
    home_goals: u8,
    away_goals: u8,
    home_team_id: &str,
    away_team_id: &str,
    user_team_id: &str,
    matchday: u32,
    date: &str,
) -> InboxMessage {
    let is_home = home_team_id == user_team_id;
    let user_goals = if is_home { home_goals } else { away_goals };
    let opp_goals = if is_home { away_goals } else { home_goals };

    let outcome = if user_goals > opp_goals {
        "Victory"
    } else if user_goals < opp_goals {
        "Defeat"
    } else {
        "Draw"
    };

    let mut rng = rand::thread_rng();
    let body = match outcome {
        "Victory" => {
            let v = [
                format!(
                    "Full time: {} {} - {} {}.\n\n\
                    An excellent result! The team put in a strong performance. \
                    Matchday {} — keep this momentum going.",
                    home_name, home_goals, away_goals, away_name, matchday
                ),
                format!(
                    "Final whistle: {} {} - {} {}.\n\n\
                    Three points in the bag! The lads showed great character out there. \
                    Matchday {} complete.",
                    home_name, home_goals, away_goals, away_name, matchday
                ),
            ];
            v[rng.gen_range(0..v.len())].clone()
        }
        "Defeat" => {
            let v = [
                format!(
                    "Full time: {} {} - {} {}.\n\n\
                    A disappointing result. We'll need to regroup and work on the areas that let us down. \
                    Matchday {} — there's still time to turn things around.",
                    home_name, home_goals, away_goals, away_name, matchday
                ),
                format!(
                    "Final score: {} {} - {} {}.\n\n\
                    Not the result we wanted. Matchday {} — the board will want to see improvement. \
                    Review what went wrong and prepare for the next challenge.",
                    home_name, home_goals, away_goals, away_name, matchday
                ),
            ];
            v[rng.gen_range(0..v.len())].clone()
        }
        _ => {
            format!(
                "Full time: {} {} - {} {}.\n\n\
                A point earned in Matchday {}. Depending on results elsewhere, this could be valuable. \
                The team fought hard but couldn't find a winner.",
                home_name, home_goals, away_goals, away_name, matchday
            )
        }
    };

    InboxMessage::new(
        format!("result_{}", fixture_id),
        format!(
            "{}: {} {} - {} {}",
            outcome, home_name, home_goals, away_goals, away_name
        ),
        body,
        "Match Reporter".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::MatchResult)
    .with_priority(if outcome == "Victory" {
        MessagePriority::Normal
    } else {
        MessagePriority::High
    })
    .with_sender_role("Press Officer")
    .with_action(action(
        "view_standings",
        "View Standings",
        "be.msg.matchResult.actionStandings",
        ActionType::NavigateTo {
            route: "/dashboard?tab=Schedule".to_string(),
        },
    ))
    .with_context(MessageContext {
        fixture_id: Some(fixture_id.to_string()),
        match_result: Some(ContextMatchResult {
            home_team_id: home_team_id.to_string(),
            away_team_id: away_team_id.to_string(),
            home_goals,
            away_goals,
        }),
        ..Default::default()
    })
    .with_i18n(
        &format!("be.msg.matchResult.subject.{}", outcome.to_lowercase()),
        &format!(
            "be.msg.matchResult.body.{}{}",
            outcome.to_lowercase(),
            if outcome == "Draw" {
                String::new()
            } else {
                rng.gen_range(0..2u8).to_string()
            }
        ),
        {
            let mut p = params(&[
                ("home", home_name),
                ("away", away_name),
                ("homeGoals", &home_goals.to_string()),
                ("awayGoals", &away_goals.to_string()),
                ("matchday", &matchday.to_string()),
            ]);
            p.insert("outcome".to_string(), outcome.to_string());
            p
        },
    )
    .with_sender_i18n("be.sender.matchReporter", "be.role.pressOfficer")
}

pub fn staff_advice_message(team_name: &str, team_id: &str, date: &str) -> InboxMessage {
    InboxMessage::new(
        "staff_advice_1".to_string(),
        "Staff Report — Coaching Vacancies".to_string(),
        format!(
            "Boss, I've had a look at the staff situation at {} and wanted to flag a few things:\n\n\
            • A good **Coach** will significantly improve training effectiveness — your players will develop faster.\n\
            • A qualified **Physio** helps with injury prevention and speeds up recovery between matches.\n\
            • Our **Scouts** can help identify transfer targets and assess opponents.\n\n\
            I'd strongly recommend filling any vacancies before the season starts. \
            You can find available staff in the Staff section.\n\n\
            Check it out when you get a chance.",
            team_name
        ),
        "Assistant Manager".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::Training)
    .with_priority(MessagePriority::High)
    .with_sender_role("Assistant Manager")
    .with_action(action("view_staff", "View Staff", "be.msg.staffAdvice.actionView", ActionType::NavigateTo { route: "/dashboard?tab=Staff".to_string() }))
    .with_context(MessageContext {
        team_id: Some(team_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        "be.msg.staffAdvice.subject",
        "be.msg.staffAdvice.body",
        params(&[("team", team_name)]),
    )
    .with_sender_i18n("be.sender.assistantManager", "be.role.assistantManager")
}

pub fn board_expectations_message(team_name: &str, team_id: &str, date: &str) -> InboxMessage {
    InboxMessage::new(
        "board_expect_1".to_string(),
        format!("{} — Season Objectives", team_name),
        "The board has set the following expectations for this season:\n\n\
            • Finish in the top half of the table\n\
            • Maintain financial stability\n\
            • Develop young talent from the academy\n\n\
            Meeting these objectives will strengthen your position. Failure to meet minimum \
            expectations may result in a review of your tenure.\n\n\
            We trust in your abilities.".to_string(),
        "Board of Directors".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::BoardDirective)
    .with_priority(MessagePriority::High)
    .with_sender_role("Chairman")
    .with_action(action(
        "ack_objectives",
        "Accept Objectives",
        "be.msg.boardExpect.actionAccept",
        ActionType::Acknowledge,
    ))
    .with_context(MessageContext {
        team_id: Some(team_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        "be.msg.boardExpect.subject",
        "be.msg.boardExpect.body",
        params(&[("team", team_name)]),
    )
    .with_sender_i18n("be.sender.boardOfDirectors", "be.role.chairman")
}

pub fn transfer_complete_message(player_name: &str, fee: u64, date: &str) -> InboxMessage {
    let fee_display = if fee >= 1_000_000 {
        format!("€{:.1}M", fee as f64 / 1_000_000.0)
    } else if fee >= 1_000 {
        format!("€{}K", fee / 1_000)
    } else {
        format!("€{}", fee)
    };

    let id = format!("transfer_{}", uuid::Uuid::new_v4());
    InboxMessage::new(
        id,
        format!("Transfer Complete: {}", player_name),
        format!(
            "The transfer of {} has been completed for a fee of {}.\n\n\
            The player has joined the squad and is available for selection.",
            player_name, fee_display
        ),
        "Transfer Committee".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::Transfer)
    .with_priority(MessagePriority::Normal)
    .with_sender_role("Director of Football")
}
