use crate::game::Game;
use chrono::Datelike;
use domain::message::*;
use rand::Rng;

fn action(id: &str, label: &str, label_key: &str, action_type: ActionType) -> MessageAction {
    MessageAction {
        id: id.to_string(),
        label: label.to_string(),
        action_type,
        resolved: false,
        label_key: Some(label_key.to_string()),
    }
}

/// Process weekly financial operations (called every Monday = weekday 0).
/// - Deduct player wages (weekly = annual / 52)
/// - Deduct staff wages
/// - Add matchday revenue for home matches played that week
/// - Check financial health and generate warnings
pub fn process_weekly_finances(game: &mut Game) {
    let weekday = game.clock.current_date.weekday().num_days_from_monday();
    if weekday != 0 {
        return; // Only process on Mondays
    }

    let today = game.clock.current_date.format("%Y-%m-%d").to_string();

    for team in game.teams.iter_mut() {
        // --- Player wages (weekly portion) ---
        let team_id = team.id.clone();
        let weekly_wages: i64 = game
            .players
            .iter()
            .filter(|p| p.team_id.as_deref() == Some(&team_id))
            .map(|p| p.wage as i64 / 52)
            .sum();

        // --- Staff wages (weekly portion) ---
        let staff_wages: i64 = game
            .staff
            .iter()
            .filter(|s| s.team_id.as_deref() == Some(&team_id))
            .map(|s| s.wage as i64 / 52)
            .sum();

        let total_wages = weekly_wages + staff_wages;
        team.finance -= total_wages;
        team.season_expenses += total_wages;
    }

    // --- Matchday income for home matches completed in last 7 days ---
    if let Some(league) = &game.league {
        let current = game.clock.current_date.date_naive();
        let week_ago = current - chrono::Duration::days(7);

        let home_matches: Vec<(String, u32)> = league
            .fixtures
            .iter()
            .filter(|f| f.status == domain::league::FixtureStatus::Completed && f.result.is_some())
            .filter_map(|f| {
                if let Ok(d) = chrono::NaiveDate::parse_from_str(&f.date, "%Y-%m-%d") {
                    if d > week_ago && d <= current {
                        // Find the home team's stadium capacity
                        Some((f.home_team_id.clone(), 0u32)) // placeholder
                    } else {
                        None
                    }
                } else {
                    None
                }
            })
            .collect();

        // For each home match, calculate revenue
        for team in game.teams.iter_mut() {
            let home_count = league
                .fixtures
                .iter()
                .filter(|f| {
                    f.status == domain::league::FixtureStatus::Completed
                        && f.home_team_id == team.id
                        && f.result.is_some()
                })
                .filter(|f| {
                    if let Ok(d) = chrono::NaiveDate::parse_from_str(&f.date, "%Y-%m-%d") {
                        d > week_ago && d <= current
                    } else {
                        false
                    }
                })
                .count() as i64;

            if home_count > 0 {
                // Revenue: ~60-90% attendance * ticket price (~€15-25 avg)
                let mut rng = rand::thread_rng();
                let attendance_pct = rng.gen_range(60..=92) as f64 / 100.0;
                let avg_ticket = rng.gen_range(15..=25) as f64;
                let revenue_per_match =
                    (team.stadium_capacity as f64 * attendance_pct * avg_ticket) as i64;
                let total_revenue = revenue_per_match * home_count;

                team.finance += total_revenue;
                team.season_income += total_revenue;
            }
        }

        // Drop the unused variable
        let _ = home_matches;
    }

    // --- Financial health warnings for user's team ---
    generate_financial_warnings(game, &today);
}

/// Generate inbox messages warning about financial issues.
fn generate_financial_warnings(game: &mut Game, today: &str) {
    let user_team_id = match &game.manager.team_id {
        Some(id) => id.clone(),
        None => return,
    };

    let team = match game.teams.iter().find(|t| t.id == user_team_id) {
        Some(t) => t,
        None => return,
    };

    let existing_ids: std::collections::HashSet<String> =
        game.messages.iter().map(|m| m.id.clone()).collect();

    let mut new_messages: Vec<InboxMessage> = Vec::new();

    // Calculate weekly wage bill
    let weekly_wages: i64 = game
        .players
        .iter()
        .filter(|p| p.team_id.as_deref() == Some(&user_team_id))
        .map(|p| p.wage as i64 / 52)
        .sum::<i64>()
        + game
            .staff
            .iter()
            .filter(|s| s.team_id.as_deref() == Some(&user_team_id))
            .map(|s| s.wage as i64 / 52)
            .sum::<i64>();

    // Weeks of runway
    let weeks_left = if weekly_wages > 0 {
        team.finance / weekly_wages
    } else {
        999
    };

    // Critical: finances negative
    if team.finance < 0 {
        let msg_id = format!("finance_critical_{}", today);
        if !existing_ids.contains(&msg_id) {
            new_messages.push(
                InboxMessage::new(
                    msg_id,
                    "URGENT: Club in Debt".to_string(),
                    format!(
                        "The club is currently €{} in debt. This is an unsustainable situation.\n\n\
                        The board demands immediate action to address the financial crisis. \
                        Consider selling players, reducing staff, or finding alternative income.\n\n\
                        Failure to resolve this may have serious consequences for your position.",
                        format_money((-team.finance) as u64)
                    ),
                    "Board of Directors".to_string(),
                    today.to_string(),
                )
                .with_category(MessageCategory::Finance)
                .with_priority(MessagePriority::Urgent)
                .with_sender_role("Chairman")
                .with_i18n(
                    "be.msg.financeCritical.subject",
                    "be.msg.financeCritical.body",
                    {
                        let mut p = std::collections::HashMap::new();
                        p.insert("amount".to_string(), format_money((-team.finance) as u64));
                        p
                    },
                )
                .with_sender_i18n("be.sender.boardOfDirectors", "be.role.chairman")
                .with_action(action("view_finances", "View Finances", "be.msg.event.ack",
                    ActionType::NavigateTo { route: "/dashboard?tab=Finances".to_string() }))
            );
        }
    }
    // Warning: less than 4 weeks of runway
    else if (0..4).contains(&weeks_left) {
        let msg_id = format!("finance_warning_{}", today);
        if !existing_ids.contains(&msg_id) {
            new_messages.push(
                InboxMessage::new(
                    msg_id,
                    "Financial Warning — Low Reserves".to_string(),
                    format!(
                        "Our financial reserves are running low. At the current burn rate (€{}/week in wages), \
                        we have approximately {} weeks of funding remaining.\n\n\
                        I'd recommend reviewing the wage bill and exploring ways to boost income.",
                        format_money(weekly_wages as u64), weeks_left
                    ),
                    "Financial Director".to_string(),
                    today.to_string(),
                )
                .with_category(MessageCategory::Finance)
                .with_priority(MessagePriority::High)
                .with_sender_role("Financial Director")
                .with_i18n(
                    "be.msg.financeWarning.subject",
                    "be.msg.financeWarning.body",
                    {
                        let mut p = std::collections::HashMap::new();
                        p.insert("weeklyWages".to_string(), format_money(weekly_wages as u64));
                        p.insert("weeksLeft".to_string(), weeks_left.to_string());
                        p
                    },
                )
                .with_sender_i18n("be.sender.financialDirector", "be.role.financialDirector")
                .with_action(action("view_finances", "View Finances", "be.msg.event.ack",
                    ActionType::NavigateTo { route: "/dashboard?tab=Finances".to_string() }))
            );
        }
    }
    // Over budget warning: wages exceed budget
    else if weekly_wages * 52 > team.wage_budget {
        let msg_id = format!("wage_over_budget_{}", today);
        if !existing_ids.contains(&msg_id) {
            let annual_wages = weekly_wages * 52;
            new_messages.push(
                InboxMessage::new(
                    msg_id,
                    "Wage Bill Exceeds Budget".to_string(),
                    format!(
                        "Our annual wage bill (€{}) currently exceeds the allocated wage budget (€{}).\n\n\
                        While we can sustain this in the short term, the board would prefer \
                        to see the wage bill brought under control.",
                        format_money(annual_wages as u64),
                        format_money(team.wage_budget as u64)
                    ),
                    "Financial Director".to_string(),
                    today.to_string(),
                )
                .with_category(MessageCategory::Finance)
                .with_priority(MessagePriority::Normal)
                .with_sender_role("Financial Director")
                .with_i18n(
                    "be.msg.wageOverBudget.subject",
                    "be.msg.wageOverBudget.body",
                    {
                        let mut p = std::collections::HashMap::new();
                        p.insert("annualWages".to_string(), format_money(annual_wages as u64));
                        p.insert("wageBudget".to_string(), format_money(team.wage_budget as u64));
                        p
                    },
                )
                .with_sender_i18n("be.sender.financialDirector", "be.role.financialDirector")
                .with_action(action("view_finances", "View Finances", "be.msg.event.ack",
                    ActionType::NavigateTo { route: "/dashboard?tab=Finances".to_string() }))
            );
        }
    }

    game.messages.extend(new_messages);
}

fn format_money(amount: u64) -> String {
    if amount >= 1_000_000 {
        format!("{:.1}M", amount as f64 / 1_000_000.0)
    } else if amount >= 1_000 {
        format!("{}K", amount / 1_000)
    } else {
        amount.to_string()
    }
}
