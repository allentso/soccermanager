use crate::game::Game;
use domain::message::*;
use rand::Rng;
use std::collections::HashMap;

fn params(pairs: &[(&str, &str)]) -> HashMap<String, String> {
    pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
}

fn action(id: &str, label: &str, label_key: &str, action_type: ActionType) -> MessageAction {
    MessageAction {
        id: id.to_string(),
        label: label.to_string(),
        action_type,
        resolved: false,
        label_key: Some(label_key.to_string()),
    }
}

/// Generate random daily events. Called from process_day().
/// Events have low probability each day so they don't spam the player.
pub fn check_random_events(game: &mut Game) {
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let user_team_id = match game.manager.team_id.clone() {
        Some(id) => id,
        None => return,
    };

    let existing_ids: std::collections::HashSet<String> =
        game.messages.iter().map(|m| m.id.clone()).collect();

    let mut rng = rand::thread_rng();
    let mut new_messages: Vec<InboxMessage> = Vec::new();

    // --- 1. Sponsor offer (1% chance per day) ---
    {
        let msg_id = format!("sponsor_{}", today);
        if !existing_ids.contains(&msg_id) && rng.gen_range(0..100) == 0 {
            let team_name = game.teams.iter().find(|t| t.id == user_team_id)
                .map(|t| t.name.as_str()).unwrap_or("Your Club");
            let amount = rng.gen_range(5..=30) * 10_000; // 50k - 300k
            let sponsor_names = [
                "GreenTech Industries", "Nova Sports", "Titan Energy",
                "BlueWave Solutions", "Summit Capital", "Apex Motors",
                "FreshBrew Co.", "CityLink Telecom",
            ];
            let sponsor = sponsor_names[rng.gen_range(0..sponsor_names.len())];

            new_messages.push(sponsor_offer_message(
                &msg_id, team_name, sponsor, amount, &today,
            ));
        }
    }

    // --- 2. Training ground injury (2% chance per day, non-match days) ---
    {
        let has_match = game.league.as_ref().map_or(false, |l| {
            l.fixtures.iter().any(|f| f.date == today && f.status == domain::league::FixtureStatus::Scheduled)
        });
        if !has_match && rng.gen_range(0..50) == 0 {
            // Pick a random non-injured player
            let eligible: Vec<&domain::player::Player> = game.players.iter()
                .filter(|p| p.team_id.as_deref() == Some(&user_team_id) && p.injury.is_none())
                .collect();
            if !eligible.is_empty() {
                let player = eligible[rng.gen_range(0..eligible.len())];
                let msg_id = format!("training_injury_{}_{}", player.id, today);
                if !existing_ids.contains(&msg_id) {
                    let days = rng.gen_range(3..=14);
                    let injury_names = ["Minor muscle strain", "Twisted ankle", "Knee bruise", "Hamstring tightness", "Calf strain"];
                    let injury_name = injury_names[rng.gen_range(0..injury_names.len())];

                    new_messages.push(training_injury_message(
                        &msg_id, &player.id, &player.match_name, injury_name, days, &today,
                    ));

                    // Apply the injury
                    let pid = player.id.clone();
                    if let Some(p) = game.players.iter_mut().find(|p| p.id == pid) {
                        p.injury = Some(domain::player::Injury {
                            name: injury_name.to_string(),
                            days_remaining: days,
                        });
                    }
                }
            }
        }
    }

    // --- 3. Media story (3% chance per day) ---
    {
        let msg_id = format!("media_{}", today);
        if !existing_ids.contains(&msg_id) && rng.gen_range(0..33) == 0 {
            let team_name = game.teams.iter().find(|t| t.id == user_team_id)
                .map(|t| t.name.as_str()).unwrap_or("Your Club");

            // Pick a random player for the story
            let team_players: Vec<&domain::player::Player> = game.players.iter()
                .filter(|p| p.team_id.as_deref() == Some(&user_team_id))
                .collect();
            if !team_players.is_empty() {
                let player = team_players[rng.gen_range(0..team_players.len())];
                let is_positive = rng.gen_bool(0.6); // 60% positive stories

                new_messages.push(media_story_message(
                    &msg_id, team_name, &player.id, &player.match_name, is_positive, &today,
                ));

                // Apply morale effect
                let pid = player.id.clone();
                if let Some(p) = game.players.iter_mut().find(|p| p.id == pid) {
                    let delta: i16 = if is_positive { rng.gen_range(2..=5) } else { rng.gen_range(-5..=-1) };
                    p.morale = ((p.morale as i16) + delta).clamp(10, 100) as u8;
                }
            }
        }
    }

    // --- 4. International call-up (5% chance per day, only if match in next 7 days) ---
    {
        let upcoming_match = game.league.as_ref().and_then(|l| {
            let current = game.clock.current_date;
            l.fixtures.iter().find(|f| {
                f.status == domain::league::FixtureStatus::Scheduled
                    && (f.home_team_id == user_team_id || f.away_team_id == user_team_id)
                    && {
                        if let Ok(d) = chrono::NaiveDate::parse_from_str(&f.date, "%Y-%m-%d") {
                            let diff = (d - current.date_naive()).num_days();
                            diff >= 1 && diff <= 7
                        } else {
                            false
                        }
                    }
            })
        });

        if upcoming_match.is_some() && rng.gen_range(0..20) == 0 {
            let eligible: Vec<&domain::player::Player> = game.players.iter()
                .filter(|p| p.team_id.as_deref() == Some(&user_team_id) && p.injury.is_none())
                .collect();
            if !eligible.is_empty() {
                let player = eligible[rng.gen_range(0..eligible.len())];
                let msg_id = format!("intl_callup_{}_{}", player.id, today);
                if !existing_ids.contains(&msg_id) {
                    new_messages.push(international_callup_message(
                        &msg_id, &player.match_name, &player.nationality, &today,
                    ));
                    // Morale boost for being called up
                    let pid = player.id.clone();
                    if let Some(p) = game.players.iter_mut().find(|p| p.id == pid) {
                        p.morale = (p.morale as i16 + rng.gen_range(3..=8)).clamp(10, 100) as u8;
                    }
                }
            }
        }
    }

    // --- 5. Community event / club milestone (1% chance per day) ---
    {
        let msg_id = format!("community_{}", today);
        if !existing_ids.contains(&msg_id) && rng.gen_range(0..100) == 0 {
            let team_name = game.teams.iter().find(|t| t.id == user_team_id)
                .map(|t| t.name.as_str()).unwrap_or("Your Club");
            new_messages.push(community_event_message(&msg_id, team_name, &today));
        }
    }

    // --- 6. Dressing room mood report (weekly, ~14% chance per day = roughly once a week) ---
    {
        let msg_id = format!("mood_report_{}", today);
        if !existing_ids.contains(&msg_id) && rng.gen_range(0..7) == 0 {
            let team_players: Vec<&domain::player::Player> = game.players.iter()
                .filter(|p| p.team_id.as_deref() == Some(&user_team_id))
                .collect();
            if !team_players.is_empty() {
                let avg_morale: f64 = team_players.iter().map(|p| p.morale as f64).sum::<f64>() / team_players.len() as f64;
                let low_morale_count = team_players.iter().filter(|p| p.morale < 40).count();
                let high_morale_count = team_players.iter().filter(|p| p.morale >= 80).count();

                new_messages.push(mood_report_message(
                    &msg_id, avg_morale, low_morale_count, high_morale_count, team_players.len(), &today,
                ));
            }
        }
    }

    // --- 7. Board confidence check (after 3+ consecutive losses, 100% trigger once) ---
    {
        if let Some(league) = &game.league {
            let completed: Vec<_> = league.fixtures.iter()
                .filter(|f| f.status == domain::league::FixtureStatus::Completed
                    && (f.home_team_id == user_team_id || f.away_team_id == user_team_id))
                .collect();
            if completed.len() >= 3 {
                let last3 = &completed[completed.len()-3..];
                let losses = last3.iter().filter(|f| {
                    if let Some(r) = &f.result {
                        let user_goals = if f.home_team_id == user_team_id { r.home_goals } else { r.away_goals };
                        let opp_goals = if f.home_team_id == user_team_id { r.away_goals } else { r.home_goals };
                        user_goals < opp_goals
                    } else { false }
                }).count();
                let msg_id = format!("board_confidence_{}", today);
                if losses >= 3 && !existing_ids.contains(&msg_id) {
                    new_messages.push(board_confidence_message(&msg_id, &today));
                }
            }
        }
    }

    // --- 8. Fan petition (2% chance per day) ---
    {
        let msg_id = format!("fan_petition_{}", today);
        if !existing_ids.contains(&msg_id) && rng.gen_range(0..50) == 0 {
            let team_name = game.teams.iter().find(|t| t.id == user_team_id)
                .map(|t| t.name.as_str()).unwrap_or("Your Club");
            new_messages.push(fan_petition_message(&msg_id, team_name, &today));
        }
    }

    // --- 9. Rival interest in player (2% chance per day) ---
    {
        let msg_id = format!("rival_interest_{}", today);
        if !existing_ids.contains(&msg_id) && rng.gen_range(0..50) == 0 {
            let eligible: Vec<&domain::player::Player> = game.players.iter()
                .filter(|p| p.team_id.as_deref() == Some(&user_team_id) && p.injury.is_none())
                .collect();
            if !eligible.is_empty() {
                let player = eligible[rng.gen_range(0..eligible.len())];
                let rival_names = ["FC Rival", "Sporting Ambition", "United Prestige", "Real Progress", "Bayern Elite"];
                let rival = rival_names[rng.gen_range(0..rival_names.len())];
                new_messages.push(rival_interest_message(
                    &msg_id, &player.id, &player.match_name, rival, &today,
                ));
            }
        }
    }

    game.messages.extend(new_messages);
}

/// Apply the effect of a sponsor offer choice.
pub fn apply_event_response(
    game: &mut Game,
    message_id: &str,
    _action_id: &str,
    option_id: &str,
) -> Option<String> {
    if message_id.starts_with("sponsor_") {
        let user_team_id = game.manager.team_id.clone()?;
        match option_id {
            "accept" => {
                // Extract amount from message body (stored in i18n_params)
                let amount = game.messages.iter()
                    .find(|m| m.id == message_id)
                    .and_then(|m| m.i18n_params.get("amount"))
                    .and_then(|a| a.parse::<u64>().ok())
                    .unwrap_or(100_000);
                if let Some(team) = game.teams.iter_mut().find(|t| t.id == user_team_id) {
                    team.finance += amount as i64;
                    team.season_income += amount as i64;
                }
                // Mark resolved
                if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
                    for a in msg.actions.iter_mut() { a.resolved = true; }
                }
                Some(format!("Sponsorship accepted! +€{}", format_money(amount)))
            }
            "decline" => {
                if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
                    for a in msg.actions.iter_mut() { a.resolved = true; }
                }
                Some("Sponsorship declined.".to_string())
            }
            _ => None,
        }
    } else if message_id.starts_with("board_confidence_") {
        match option_id {
            "reassure_board" => {
                if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
                    for a in msg.actions.iter_mut() { a.resolved = true; }
                }
                Some("You reassured the board. They'll give you more time — for now.".to_string())
            }
            "accept_pressure" => {
                if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
                    for a in msg.actions.iter_mut() { a.resolved = true; }
                }
                Some("You acknowledged the pressure. The board appreciates your honesty.".to_string())
            }
            "blame_circumstances" => {
                if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
                    for a in msg.actions.iter_mut() { a.resolved = true; }
                }
                Some("The board isn't entirely convinced by excuses, but they'll wait and see.".to_string())
            }
            _ => None,
        }
    } else if message_id.starts_with("fan_petition_") {
        match option_id {
            "listen_fans" => {
                // Small morale boost across squad
                let user_team_id = game.manager.team_id.clone().unwrap_or_default();
                let mut rng = rand::thread_rng();
                for p in game.players.iter_mut() {
                    if p.team_id.as_deref() == Some(&user_team_id) {
                        p.morale = (p.morale as i16 + rng.gen_range(1..=3)).clamp(10, 100) as u8;
                    }
                }
                if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
                    for a in msg.actions.iter_mut() { a.resolved = true; }
                }
                Some("You engaged with the fans. Squad morale improved slightly.".to_string())
            }
            "ignore_fans" => {
                if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
                    for a in msg.actions.iter_mut() { a.resolved = true; }
                }
                Some("You decided to focus on football matters. The fans are a little disappointed.".to_string())
            }
            "address_publicly" => {
                if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
                    for a in msg.actions.iter_mut() { a.resolved = true; }
                }
                Some("Your public address was well received. Fan confidence is up.".to_string())
            }
            _ => None,
        }
    } else if message_id.starts_with("rival_interest_") {
        let player_id = game.messages.iter()
            .find(|m| m.id == message_id)
            .and_then(|m| m.context.player_id.clone());
        match option_id {
            "not_for_sale" => {
                // Player morale boost — they feel valued
                if let Some(pid) = &player_id {
                    if let Some(p) = game.players.iter_mut().find(|p| p.id == *pid) {
                        let mut rng = rand::thread_rng();
                        p.morale = (p.morale as i16 + rng.gen_range(3..=8)).clamp(10, 100) as u8;
                    }
                }
                if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
                    for a in msg.actions.iter_mut() { a.resolved = true; }
                }
                Some("You made it clear the player is not for sale. They're feeling valued.".to_string())
            }
            "open_to_offers" => {
                // Player morale drop — they feel uncertain
                if let Some(pid) = &player_id {
                    if let Some(p) = game.players.iter_mut().find(|p| p.id == *pid) {
                        let mut rng = rand::thread_rng();
                        p.morale = (p.morale as i16 - rng.gen_range(3..=8)).clamp(10, 100) as u8;
                    }
                }
                if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
                    for a in msg.actions.iter_mut() { a.resolved = true; }
                }
                Some("You indicated you'd listen to offers. The player is unsettled.".to_string())
            }
            "no_comment" => {
                if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
                    for a in msg.actions.iter_mut() { a.resolved = true; }
                }
                Some("No comment. The rumour mill continues...".to_string())
            }
            _ => None,
        }
    } else {
        None
    }
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

// ---------------------------------------------------------------------------
// Message builders
// ---------------------------------------------------------------------------

fn sponsor_offer_message(
    msg_id: &str, team_name: &str, sponsor: &str, amount: u64, date: &str,
) -> InboxMessage {
    InboxMessage::new(
        msg_id.to_string(),
        format!("Sponsorship Offer — {}", sponsor),
        format!(
            "Good news, boss! {} has expressed interest in becoming a sponsor of {}.\n\n\
            They're offering a one-time payment of €{} in exchange for advertising space at the training ground.\n\n\
            This seems like a reasonable deal, but it's your call.",
            sponsor, team_name, format_money(amount)
        ),
        "Commercial Director".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::Finance)
    .with_priority(MessagePriority::Normal)
    .with_sender_role("Commercial Director")
    .with_action(action(
        "respond", "Respond", "be.msg.event.respond",
        ActionType::ChooseOption {
            options: vec![
                ActionOption {
                    id: "accept".to_string(),
                    label: "Accept the deal".to_string(),
                    description: format!("Receive €{} in sponsorship income.", format_money(amount)),
                },
                ActionOption {
                    id: "decline".to_string(),
                    label: "Decline politely".to_string(),
                    description: "Turn down the offer. No financial impact.".to_string(),
                },
            ],
        },
    ))
    .with_i18n(
        "be.msg.sponsor.subject",
        "be.msg.sponsor.body",
        params(&[("sponsor", sponsor), ("team", team_name), ("amount", &format_money(amount))]),
    )
    .with_sender_i18n("be.sender.commercialDirector", "be.role.commercialDirector")
}

fn training_injury_message(
    msg_id: &str, player_id: &str, player_name: &str, injury_name: &str, days: u32, date: &str,
) -> InboxMessage {
    let mut rng = rand::thread_rng();
    let variations = [
        format!(
            "Bad news from the training ground. {} has picked up a {} during today's session.\n\n\
            The medical team estimates {} days on the sidelines. We'll monitor the recovery closely.",
            player_name, injury_name.to_lowercase(), days
        ),
        format!(
            "Unfortunately, {} went down in training today with a {}.\n\n\
            Initial assessment: out for approximately {} days. We'll keep you updated on their progress.",
            player_name, injury_name.to_lowercase(), days
        ),
    ];
    let idx = rng.gen_range(0..variations.len());

    InboxMessage::new(
        msg_id.to_string(),
        format!("Injury — {} ({})", player_name, injury_name),
        variations[idx].clone(),
        "Head Physio".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::Injury)
    .with_priority(MessagePriority::High)
    .with_sender_role("Head Physio")
    .with_action(action("ack", "Understood", "be.msg.event.ack", ActionType::Acknowledge))
    .with_context(MessageContext {
        player_id: Some(player_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        "be.msg.trainingInjury.subject",
        &format!("be.msg.trainingInjury.body{}", idx),
        params(&[("player", player_name), ("injury", injury_name), ("days", &days.to_string())]),
    )
    .with_sender_i18n("be.sender.headPhysio", "be.role.headPhysio")
}

fn media_story_message(
    msg_id: &str, team_name: &str, player_id: &str, player_name: &str, is_positive: bool, date: &str,
) -> InboxMessage {
    let mut rng = rand::thread_rng();

    let (subject, body) = if is_positive {
        let stories = [
            (
                format!("Positive Press — {}", player_name),
                format!(
                    "The local papers are running a very positive piece on {} today.\n\n\
                    They're highlighting their excellent recent form and commitment to {}. \
                    This kind of coverage is great for the player's confidence and the club's image.",
                    player_name, team_name
                ),
            ),
            (
                format!("Media Praise for {}", player_name),
                format!(
                    "Sports journalists have singled out {} for praise in their latest column.\n\n\
                    \"One of the standout performers at {} this season\" — great for morale.",
                    player_name, team_name
                ),
            ),
        ];
        stories[rng.gen_range(0..stories.len())].clone()
    } else {
        let stories = [
            (
                format!("Negative Press — {}", player_name),
                format!(
                    "Some unflattering coverage of {} appeared in the tabloids today.\n\n\
                    Journalists are questioning their form and commitment to {}. \
                    This could affect the player's morale — you might want to have a word.",
                    player_name, team_name
                ),
            ),
            (
                format!("Media Criticism — {}", player_name),
                format!(
                    "The press are being harsh on {} in today's papers.\n\n\
                    \"Is {} getting the best out of their squad?\" — the article questions your use of the player. \
                    Worth keeping an eye on how this affects the dressing room.",
                    player_name, team_name
                ),
            ),
        ];
        stories[rng.gen_range(0..stories.len())].clone()
    };

    InboxMessage::new(
        msg_id.to_string(),
        subject,
        body,
        "Press Officer".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::Media)
    .with_priority(if is_positive { MessagePriority::Low } else { MessagePriority::Normal })
    .with_sender_role("Press Officer")
    .with_action(action("ack", "Noted", "be.msg.event.ack", ActionType::Acknowledge))
    .with_context(MessageContext {
        player_id: Some(player_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        if is_positive { "be.msg.mediaPositive.subject" } else { "be.msg.mediaNegative.subject" },
        if is_positive { "be.msg.mediaPositive.body" } else { "be.msg.mediaNegative.body" },
        params(&[("player", player_name), ("team", team_name)]),
    )
    .with_sender_i18n("be.sender.pressOfficer", "be.role.pressOfficer")
}

fn international_callup_message(
    msg_id: &str, player_name: &str, nationality: &str, date: &str,
) -> InboxMessage {
    InboxMessage::new(
        msg_id.to_string(),
        format!("International Call-Up — {}", player_name),
        format!(
            "{} has been called up to the {} national team for an upcoming international window.\n\n\
            This is a great honor for the player and reflects well on the club. \
            They'll be in good spirits when they return, though keep an eye on their fatigue levels.",
            player_name, nationality
        ),
        "International Liaison".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::LeagueInfo)
    .with_priority(MessagePriority::Normal)
    .with_sender_role("International Liaison")
    .with_action(action("ack", "Acknowledged", "be.msg.event.ack", ActionType::Acknowledge))
    .with_i18n(
        "be.msg.intlCallup.subject",
        "be.msg.intlCallup.body",
        params(&[("player", player_name), ("nationality", nationality)]),
    )
    .with_sender_i18n("be.sender.intlLiaison", "be.role.intlLiaison")
}

fn community_event_message(msg_id: &str, team_name: &str, date: &str) -> InboxMessage {
    let mut rng = rand::thread_rng();
    let events = [
        (
            "Community Open Day",
            format!(
                "{} hosted a community open day at the training ground today.\n\n\
                Fans got to meet the players and watch a training session. \
                The atmosphere was fantastic and it's done wonders for team spirit.",
                team_name
            ),
        ),
        (
            "Youth Coaching Session",
            format!(
                "Several first-team players from {} volunteered for a youth coaching session at a local school.\n\n\
                Great PR for the club, and the players seem energized by the experience.",
                team_name
            ),
        ),
        (
            "Charity Match Announcement",
            format!(
                "The club has organized a charity initiative in partnership with a local foundation.\n\n\
                {} continues to build strong ties with the community. The board is pleased with the positive image.",
                team_name
            ),
        ),
    ];
    let idx = rng.gen_range(0..events.len());
    let (subject, body) = &events[idx];

    InboxMessage::new(
        msg_id.to_string(),
        subject.to_string(),
        body.clone(),
        "Community Manager".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::System)
    .with_priority(MessagePriority::Low)
    .with_sender_role("Community Manager")
    .with_action(action("ack", "Great", "be.msg.event.ack", ActionType::Acknowledge))
    .with_i18n(
        &format!("be.msg.community.subject{}", idx),
        &format!("be.msg.community.body{}", idx),
        params(&[("team", team_name)]),
    )
    .with_sender_i18n("be.sender.communityManager", "be.role.communityManager")
}

fn mood_report_message(
    msg_id: &str, avg_morale: f64, low_count: usize, high_count: usize, total: usize, date: &str,
) -> InboxMessage {
    let mood = if avg_morale >= 75.0 { "Excellent" }
        else if avg_morale >= 60.0 { "Good" }
        else if avg_morale >= 45.0 { "Mixed" }
        else { "Poor" };

    let body = format!(
        "Here's your weekly dressing room report:\n\n\
        • Overall mood: {} (avg morale: {:.0})\n\
        • Players in high spirits (80+): {}\n\
        • Players with low morale (<40): {}\n\
        • Total squad: {}\n\n\
        {}",
        mood, avg_morale, high_count, low_count, total,
        if low_count >= 3 {
            "Several players are unhappy. You should address individual concerns before it spreads."
        } else if avg_morale >= 75.0 {
            "The dressing room is buzzing. Keep up the good work!"
        } else if avg_morale < 45.0 {
            "Morale is worryingly low. Consider positive team talks and results to turn things around."
        } else {
            "Morale is stable. A few good results would really lift the mood."
        }
    );

    InboxMessage::new(
        msg_id.to_string(),
        format!("Dressing Room Report — Mood: {}", mood),
        body,
        "Assistant Manager".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::PlayerMorale)
    .with_priority(if low_count >= 3 || avg_morale < 40.0 { MessagePriority::High } else { MessagePriority::Low })
    .with_sender_role("Assistant Manager")
    .with_action(action("ack", "Thanks", "be.msg.event.ack", ActionType::Acknowledge))
    .with_i18n(
        "be.msg.moodReport.subject",
        "be.msg.moodReport.body",
        {
            let mut p = params(&[("mood", mood)]);
            p.insert("avgMorale".to_string(), format!("{:.0}", avg_morale));
            p.insert("highCount".to_string(), high_count.to_string());
            p.insert("lowCount".to_string(), low_count.to_string());
            p.insert("total".to_string(), total.to_string());
            p
        },
    )
    .with_sender_i18n("be.sender.assistantManager", "be.role.assistantManager")
}

fn board_confidence_message(msg_id: &str, date: &str) -> InboxMessage {
    let mut rng = rand::thread_rng();
    let variations = [
        "The board has called an urgent meeting. Three consecutive defeats have raised serious concerns about the team's direction.\n\n\
        \"We need to see improvement quickly. The fans are restless and results must change.\"\n\n\
        How do you respond?",
        "After a string of poor results, the chairman has summoned you for a difficult conversation.\n\n\
        \"We backed you with resources and time. The results simply aren't good enough. What's your plan?\"\n\n\
        Choose your response carefully.",
    ];
    let idx = rng.gen_range(0..variations.len());

    InboxMessage::new(
        msg_id.to_string(),
        "Board Meeting — Results Under Scrutiny".to_string(),
        variations[idx].to_string(),
        "Board of Directors".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::BoardDirective)
    .with_priority(MessagePriority::Urgent)
    .with_sender_role("Chairman")
    .with_action(action(
        "respond", "Respond", "be.msg.event.respond",
        ActionType::ChooseOption {
            options: vec![
                ActionOption {
                    id: "reassure_board".to_string(),
                    label: "Reassure them with a plan".to_string(),
                    description: "Present a clear strategy for turning things around. Buys you time.".to_string(),
                },
                ActionOption {
                    id: "accept_pressure".to_string(),
                    label: "Accept responsibility".to_string(),
                    description: "Own the poor results. The board respects honesty.".to_string(),
                },
                ActionOption {
                    id: "blame_circumstances".to_string(),
                    label: "Point to injuries and bad luck".to_string(),
                    description: "Deflect blame to external factors. May or may not convince them.".to_string(),
                },
            ],
        },
    ))
    .with_i18n(
        "be.msg.boardConfidence.subject",
        &format!("be.msg.boardConfidence.body{}", idx),
        params(&[]),
    )
    .with_sender_i18n("be.sender.boardOfDirectors", "be.role.chairman")
}

fn fan_petition_message(msg_id: &str, team_name: &str, date: &str) -> InboxMessage {
    let mut rng = rand::thread_rng();
    let petitions = [
        (
            "Fan Petition — More Attacking Football",
            format!(
                "A group of {} supporters has organized a petition calling for more attacking football.\n\n\
                \"We pay good money to watch exciting football. We want to see the team go forward and entertain us!\"\n\n\
                Over 500 signatures so far. How do you respond?",
                team_name
            ),
        ),
        (
            "Fan Petition — Give Youth a Chance",
            format!(
                "Supporters of {} have started a campaign urging you to give more opportunities to young players from the academy.\n\n\
                \"The future of our club depends on developing homegrown talent. Stop overlooking the kids!\"\n\n\
                It's getting traction on social media. What's your response?",
                team_name
            ),
        ),
        (
            "Fan Open Letter — Transparency",
            format!(
                "An open letter from the {} Supporters Trust has been published, asking for more transparency from the management.\n\n\
                \"We want to understand the club's vision. Where are we heading? What's the long-term plan?\"\n\n\
                The local press is covering it. How do you handle this?",
                team_name
            ),
        ),
    ];
    let idx = rng.gen_range(0..petitions.len());
    let (subject, body) = &petitions[idx];

    InboxMessage::new(
        msg_id.to_string(),
        subject.to_string(),
        body.clone(),
        "Community Manager".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::Media)
    .with_priority(MessagePriority::Normal)
    .with_sender_role("Community Manager")
    .with_action(action(
        "respond", "Respond", "be.msg.event.respond",
        ActionType::ChooseOption {
            options: vec![
                ActionOption {
                    id: "listen_fans".to_string(),
                    label: "Engage with the fans".to_string(),
                    description: "Meet with fan representatives and listen to their concerns. Good for morale.".to_string(),
                },
                ActionOption {
                    id: "ignore_fans".to_string(),
                    label: "Focus on football".to_string(),
                    description: "Politely decline — football decisions stay in the dressing room.".to_string(),
                },
                ActionOption {
                    id: "address_publicly".to_string(),
                    label: "Make a public statement".to_string(),
                    description: "Address the petition in a press conference. Transparent and proactive.".to_string(),
                },
            ],
        },
    ))
    .with_i18n(
        &format!("be.msg.fanPetition.subject{}", idx),
        &format!("be.msg.fanPetition.body{}", idx),
        params(&[("team", team_name)]),
    )
    .with_sender_i18n("be.sender.communityManager", "be.role.communityManager")
}

fn rival_interest_message(
    msg_id: &str, player_id: &str, player_name: &str, rival_name: &str, date: &str,
) -> InboxMessage {
    let mut rng = rand::thread_rng();
    let variations = [
        format!(
            "We've received word that {} have been making enquiries about {}.\n\n\
            Their scouts were spotted at our last few matches, and our sources suggest \
            they may approach with a formal offer soon.\n\n\
            How would you like us to respond if they make contact?",
            rival_name, player_name
        ),
        format!(
            "The press are reporting that {} is a target for {}.\n\n\
            According to sources, the player has attracted attention after their recent performances. \
            No formal bid yet, but it's only a matter of time.\n\n\
            What's your stance?",
            player_name, rival_name
        ),
    ];
    let idx = rng.gen_range(0..variations.len());

    InboxMessage::new(
        msg_id.to_string(),
        format!("Transfer Rumour — {} linked with {}", player_name, rival_name),
        variations[idx].clone(),
        "Director of Football".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::Transfer)
    .with_priority(MessagePriority::Normal)
    .with_sender_role("Director of Football")
    .with_action(action(
        "respond", "Respond", "be.msg.event.respond",
        ActionType::ChooseOption {
            options: vec![
                ActionOption {
                    id: "not_for_sale".to_string(),
                    label: "Not for sale".to_string(),
                    description: "Make it clear the player is going nowhere. Boosts their morale.".to_string(),
                },
                ActionOption {
                    id: "open_to_offers".to_string(),
                    label: "Open to offers".to_string(),
                    description: "Signal willingness to negotiate. Player may become unsettled.".to_string(),
                },
                ActionOption {
                    id: "no_comment".to_string(),
                    label: "No comment".to_string(),
                    description: "Stay quiet and let things play out. Neutral stance.".to_string(),
                },
            ],
        },
    ))
    .with_context(MessageContext {
        player_id: Some(player_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        "be.msg.rivalInterest.subject",
        &format!("be.msg.rivalInterest.body{}", idx),
        params(&[("player", player_name), ("rival", rival_name)]),
    )
    .with_sender_i18n("be.sender.directorOfFootball", "be.role.directorOfFootball")
}
