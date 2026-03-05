use super::{action, format_money, params};
use domain::message::*;
use rand::Rng;

// ---------------------------------------------------------------------------
// Message builders
// ---------------------------------------------------------------------------

pub(super) fn sponsor_offer_message(
    msg_id: &str,
    team_name: &str,
    sponsor: &str,
    amount: u64,
    date: &str,
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

pub(super) fn training_injury_message(
    msg_id: &str,
    player_id: &str,
    player_name: &str,
    injury_name: &str,
    days: u32,
    date: &str,
) -> InboxMessage {
    let mut rng = rand::thread_rng();
    let variations = [
        format!(
            "Bad news from the training ground. {} has picked up a {} during today's session.\n\n\
            The medical team estimates {} days on the sidelines. We'll monitor the recovery closely.",
            player_name,
            injury_name.to_lowercase(),
            days
        ),
        format!(
            "Unfortunately, {} went down in training today with a {}.\n\n\
            Initial assessment: out for approximately {} days. We'll keep you updated on their progress.",
            player_name,
            injury_name.to_lowercase(),
            days
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
    .with_action(action(
        "ack",
        "Understood",
        "be.msg.event.ack",
        ActionType::Acknowledge,
    ))
    .with_context(MessageContext {
        player_id: Some(player_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        "be.msg.trainingInjury.subject",
        &format!("be.msg.trainingInjury.body{}", idx),
        params(&[
            ("player", player_name),
            ("injury", injury_name),
            ("days", &days.to_string()),
        ]),
    )
    .with_sender_i18n("be.sender.headPhysio", "be.role.headPhysio")
}

pub(super) fn media_story_message(
    msg_id: &str,
    team_name: &str,
    player_id: &str,
    player_name: &str,
    is_positive: bool,
    date: &str,
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
    .with_priority(if is_positive {
        MessagePriority::Low
    } else {
        MessagePriority::Normal
    })
    .with_sender_role("Press Officer")
    .with_action(action(
        "ack",
        "Noted",
        "be.msg.event.ack",
        ActionType::Acknowledge,
    ))
    .with_context(MessageContext {
        player_id: Some(player_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        if is_positive {
            "be.msg.mediaPositive.subject"
        } else {
            "be.msg.mediaNegative.subject"
        },
        if is_positive {
            "be.msg.mediaPositive.body"
        } else {
            "be.msg.mediaNegative.body"
        },
        params(&[("player", player_name), ("team", team_name)]),
    )
    .with_sender_i18n("be.sender.pressOfficer", "be.role.pressOfficer")
}

pub(super) fn international_callup_message(
    msg_id: &str,
    player_name: &str,
    nationality: &str,
    date: &str,
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

pub(super) fn community_event_message(msg_id: &str, team_name: &str, date: &str) -> InboxMessage {
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
    .with_action(action(
        "ack",
        "Great",
        "be.msg.event.ack",
        ActionType::Acknowledge,
    ))
    .with_i18n(
        &format!("be.msg.community.subject{}", idx),
        &format!("be.msg.community.body{}", idx),
        params(&[("team", team_name)]),
    )
    .with_sender_i18n("be.sender.communityManager", "be.role.communityManager")
}

pub(super) fn mood_report_message(
    msg_id: &str,
    avg_morale: f64,
    low_count: usize,
    high_count: usize,
    total: usize,
    date: &str,
) -> InboxMessage {
    let mood = if avg_morale >= 75.0 {
        "Excellent"
    } else if avg_morale >= 60.0 {
        "Good"
    } else if avg_morale >= 45.0 {
        "Mixed"
    } else {
        "Poor"
    };

    let body = format!(
        "Here's your weekly dressing room report:\n\n\
        • Overall mood: {} (avg morale: {:.0})\n\
        • Players in high spirits (80+): {}\n\
        • Players with low morale (<40): {}\n\
        • Total squad: {}\n\n\
        {}",
        mood,
        avg_morale,
        high_count,
        low_count,
        total,
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
    .with_priority(if low_count >= 3 || avg_morale < 40.0 {
        MessagePriority::High
    } else {
        MessagePriority::Low
    })
    .with_sender_role("Assistant Manager")
    .with_action(action(
        "ack",
        "Thanks",
        "be.msg.event.ack",
        ActionType::Acknowledge,
    ))
    .with_i18n("be.msg.moodReport.subject", "be.msg.moodReport.body", {
        let mut p = params(&[("mood", mood)]);
        p.insert("avgMorale".to_string(), format!("{:.0}", avg_morale));
        p.insert("highCount".to_string(), high_count.to_string());
        p.insert("lowCount".to_string(), low_count.to_string());
        p.insert("total".to_string(), total.to_string());
        p
    })
    .with_sender_i18n("be.sender.assistantManager", "be.role.assistantManager")
}

pub(super) fn board_confidence_message(msg_id: &str, date: &str) -> InboxMessage {
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
        "respond",
        "Respond",
        "be.msg.event.respond",
        ActionType::ChooseOption {
            options: vec![
                ActionOption {
                    id: "reassure_board".to_string(),
                    label: "Reassure them with a plan".to_string(),
                    description:
                        "Present a clear strategy for turning things around. Buys you time."
                            .to_string(),
                },
                ActionOption {
                    id: "accept_pressure".to_string(),
                    label: "Accept responsibility".to_string(),
                    description: "Own the poor results. The board respects honesty.".to_string(),
                },
                ActionOption {
                    id: "blame_circumstances".to_string(),
                    label: "Point to injuries and bad luck".to_string(),
                    description: "Deflect blame to external factors. May or may not convince them."
                        .to_string(),
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

pub(super) fn fan_petition_message(msg_id: &str, team_name: &str, date: &str) -> InboxMessage {
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

pub(super) fn rival_interest_message(
    msg_id: &str,
    player_id: &str,
    player_name: &str,
    rival_name: &str,
    date: &str,
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
        format!(
            "Transfer Rumour — {} linked with {}",
            player_name, rival_name
        ),
        variations[idx].clone(),
        "Director of Football".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::Transfer)
    .with_priority(MessagePriority::Normal)
    .with_sender_role("Director of Football")
    .with_action(action(
        "respond",
        "Respond",
        "be.msg.event.respond",
        ActionType::ChooseOption {
            options: vec![
                ActionOption {
                    id: "not_for_sale".to_string(),
                    label: "Not for sale".to_string(),
                    description: "Make it clear the player is going nowhere. Boosts their morale."
                        .to_string(),
                },
                ActionOption {
                    id: "open_to_offers".to_string(),
                    label: "Open to offers".to_string(),
                    description: "Signal willingness to negotiate. Player may become unsettled."
                        .to_string(),
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
