use crate::game::Game;
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

fn action(id: &str, label: &str, label_key: &str, action_type: ActionType) -> MessageAction {
    MessageAction {
        id: id.to_string(),
        label: label.to_string(),
        action_type,
        resolved: false,
        label_key: Some(label_key.to_string()),
    }
}

/// Check all player-related events and generate inbox messages.
/// Called once per day from process_day().
pub fn check_player_events(game: &mut Game) {
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let user_team_id = match game.manager.team_id.clone() {
        Some(id) => id,
        None => return,
    };

    // Collect existing message IDs for deduplication
    let existing_ids: std::collections::HashSet<String> =
        game.messages.iter().map(|m| m.id.clone()).collect();

    let mut new_messages: Vec<InboxMessage> = Vec::new();

    // --- 1. Low morale meeting requests (morale < 30) ---
    for player in game.players.iter() {
        if player.team_id.as_deref() != Some(&user_team_id) {
            continue;
        }
        if player.injury.is_some() {
            continue;
        }

        let msg_id = format!("morale_talk_{}", player.id);
        if existing_ids.contains(&msg_id) {
            continue;
        }

        if player.morale < 30 {
            new_messages.push(low_morale_message(
                &msg_id,
                &player.id,
                &player.match_name,
                player.morale,
                &today,
            ));
        }
    }

    // --- 2. Benched player complaints ---
    // Count recent matches where user's team played, then check which players
    // didn't appear in any of the last 3 completed fixtures
    if let Some(league) = &game.league {
        let completed: Vec<&domain::league::Fixture> = league
            .fixtures
            .iter()
            .filter(|f| {
                f.status == domain::league::FixtureStatus::Completed
                    && (f.home_team_id == user_team_id || f.away_team_id == user_team_id)
            })
            .collect();

        let recent_count = completed.len().min(3);
        if recent_count >= 3 {
            let recent = &completed[completed.len() - 3..];

            // Collect player IDs who appeared in any of the last 3 matches
            // We use the player_stats from match results which contain player IDs
            let mut appeared: std::collections::HashSet<String> =
                std::collections::HashSet::new();
            for fixture in recent {
                if let Some(result) = &fixture.result {
                    for scorer in &result.home_scorers {
                        appeared.insert(scorer.player_id.clone());
                    }
                    for scorer in &result.away_scorers {
                        appeared.insert(scorer.player_id.clone());
                    }
                }
            }

            // Any non-GK, non-injured player with decent OVR who hasn't appeared
            for player in game.players.iter() {
                if player.team_id.as_deref() != Some(&user_team_id) {
                    continue;
                }
                if player.injury.is_some() {
                    continue;
                }
                if player.position == domain::player::Position::Goalkeeper {
                    continue;
                }

                let msg_id = format!("bench_complaint_{}", player.id);
                if existing_ids.contains(&msg_id) {
                    continue;
                }

                // Only complain if they have decent attributes (OVR >= 55) and morale is already dropping
                let attrs = &player.attributes;
                let ovr = (attrs.pace as u16
                    + attrs.stamina as u16
                    + attrs.strength as u16
                    + attrs.passing as u16
                    + attrs.shooting as u16
                    + attrs.tackling as u16
                    + attrs.dribbling as u16
                    + attrs.defending as u16
                    + attrs.positioning as u16
                    + attrs.vision as u16
                    + attrs.decisions as u16)
                    / 11;

                if ovr >= 55 && player.morale < 60 && !appeared.contains(&player.id) {
                    new_messages.push(bench_complaint_message(
                        &msg_id,
                        &player.id,
                        &player.match_name,
                        &today,
                    ));
                }
            }
        }
    }

    // --- 3. Happy player / high morale praise ---
    {
        let mut rng = rand::thread_rng();
        for player in game.players.iter() {
            if player.team_id.as_deref() != Some(&user_team_id) {
                continue;
            }

            let msg_id = format!("happy_player_{}", player.id);
            if existing_ids.contains(&msg_id) {
                continue;
            }

            // High morale player occasionally sends positive message (10% chance per day)
            if player.morale >= 90 && rng.gen_range(0..10) == 0 {
                new_messages.push(happy_player_message(
                    &msg_id,
                    &player.id,
                    &player.match_name,
                    &today,
                ));
            }
        }
    }

    // --- 4. Contract concern (< 90 days remaining) ---
    {
        let current_date = game.clock.current_date.date_naive();
        for player in game.players.iter() {
            if player.team_id.as_deref() != Some(&user_team_id) {
                continue;
            }

            let msg_id = format!("contract_concern_{}", player.id);
            if existing_ids.contains(&msg_id) {
                continue;
            }

            if let Some(end_str) = &player.contract_end {
                if let Ok(end_date) = chrono::NaiveDate::parse_from_str(end_str, "%Y-%m-%d") {
                    let days_remaining = (end_date - current_date).num_days();
                    if days_remaining > 0 && days_remaining <= 90 {
                        new_messages.push(contract_concern_message(
                            &msg_id,
                            &player.id,
                            &player.match_name,
                            days_remaining,
                            &today,
                        ));
                    }
                }
            }
        }
    }

    game.messages.extend(new_messages);
}

/// Personality factor derived from player attributes. Affects how they react.
/// Returns a value from -20 to +20, where positive = more receptive, negative = more volatile.
fn personality_factor(player: &domain::player::Player) -> i8 {
    let composure = player.attributes.composure as i16;
    let leadership = player.attributes.leadership as i16;
    let aggression = player.attributes.aggression as i16;
    // Composed leaders are receptive; aggressive low-composure players are volatile
    ((composure + leadership - aggression) / 6).clamp(-20, 20) as i8
}

/// Apply the effect of a player conversation choice.
/// Returns a description of what happened, or None if the message wasn't a player event.
pub fn apply_player_response(
    game: &mut Game,
    message_id: &str,
    action_id: &str,
    option_id: &str,
) -> Option<String> {
    // Find the message to get context
    let player_id = game
        .messages
        .iter()
        .find(|m| m.id == message_id)
        .and_then(|m| m.context.player_id.clone())?;

    let mut rng = rand::thread_rng();

    // Get personality factor for this player
    let pf = game.players.iter().find(|p| p.id == player_id)
        .map(|p| personality_factor(p))
        .unwrap_or(0);

    // Base deltas are now more punishing; personality modifies the outcome
    let (mut delta, mut description) = if message_id.starts_with("morale_talk_") {
        match option_id {
            "encourage" => {
                // Safe option but small boost; volatile players shrug it off
                let d = rng.gen_range(2..=8) + (pf / 4);
                (d, if d > 0 { format!("Player feels a bit better. Morale +{}", d) }
                     else { format!("Player doesn't buy it. Morale {}", d) })
            }
            "promise_time" => {
                // Big boost but sets a PROMISE — if not honored, bigger penalty later
                let d = rng.gen_range(10..=16);
                (d, format!("Player is reassured by the promise. Morale +{}. They'll expect to start soon.", d))
            }
            "work_harder" => {
                // Risky: aggressive players hate this, composed ones respond well
                let d = rng.gen_range(-12..=4) + (pf / 3);
                (d, if d >= 0 { format!("Player accepts the challenge. Morale +{}", d) }
                     else { format!("Player is offended by the tough love. Morale {}", d) })
            }
            _ => return None,
        }
    } else if message_id.starts_with("bench_complaint_") {
        match option_id {
            "explain" => {
                // Moderate; only works on composed players
                let d = rng.gen_range(-2..=6) + (pf / 4);
                (d, if d >= 0 { format!("Player grudgingly accepts. Morale +{}", d) }
                     else { format!("Player isn't convinced. Morale {}", d) })
            }
            "promise_chance" => {
                // PROMISE — big boost now, tracked for consequences
                let d = rng.gen_range(8..=14);
                (d, format!("Player is excited about the opportunity. Morale +{}. They expect to start next match.", d))
            }
            "prove_yourself" => {
                // Very risky — high-aggression players rebel
                let d = rng.gen_range(-10..=6) + (pf / 3);
                (d, if d >= 0 { format!("Player is fired up to prove their worth. Morale +{}", d) }
                     else { format!("Player feels dismissed and insulted. Morale {}", d) })
            }
            _ => return None,
        }
    } else if message_id.starts_with("happy_player_") {
        match option_id {
            "praise_back" => {
                let d = rng.gen_range(2..=5);
                (d, format!("Player beams at the praise. Morale +{}", d))
            }
            "stay_professional" => {
                // Neutral — can slightly drop morale on volatile players
                let d = rng.gen_range(-2..=3) + (pf / 6);
                (d, if d >= 0 { format!("Player nods professionally. Morale +{}", d) }
                     else { format!("Player wanted more warmth. Morale {}", d) })
            }
            "higher_expectations" => {
                // Risky: leaders respond well, others feel pressured
                let d = rng.gen_range(-6..=4) + (pf / 3);
                (d, if d >= 0 { format!("Player rises to the challenge. Morale +{}", d) }
                     else { format!("Player feels the pressure is unfair. Morale {}", d) })
            }
            _ => return None,
        }
    } else if message_id.starts_with("contract_concern_") {
        match option_id {
            "reassure" => {
                // Sets expectation of renewal — moderate boost
                let d = rng.gen_range(4..=10);
                (d, format!("Player is reassured about their future. Morale +{}", d))
            }
            "noncommittal" => {
                // Almost always negative — players hate uncertainty
                let d = rng.gen_range(-8..=0) + (pf / 5);
                (d, if d >= 0 { format!("Player grudgingly accepts for now. Morale +{}", d) }
                     else { format!("Player is unsettled and unhappy. Morale {}", d) })
            }
            "no_renewal" => {
                let d = rng.gen_range(-15..=-8);
                (d, format!("Player is devastated. Morale {}. They may affect the dressing room.", d))
            }
            _ => return None,
        }
    } else {
        return None;
    };

    // Clamp delta to prevent extreme swings
    delta = delta.clamp(-20, 20);

    // Apply morale change
    if let Some(player) = game.players.iter_mut().find(|p| p.id == player_id) {
        let base = player.morale as i16;
        player.morale = (base + delta as i16).clamp(5, 100) as u8;
    }

    // "No renewal" tanks morale of nearby players too (dressing room effect)
    if message_id.starts_with("contract_concern_") && option_id == "no_renewal" {
        let user_team_id = game.manager.team_id.clone().unwrap_or_default();
        // Teammates lose 2-5 morale
        let mut affected = 0u8;
        for p in game.players.iter_mut() {
            if p.id != player_id && p.team_id.as_deref() == Some(&user_team_id) {
                let loss = rng.gen_range(2..=5);
                p.morale = (p.morale as i16 - loss as i16).clamp(10, 100) as u8;
                affected += 1;
            }
        }
        if affected > 0 {
            description = format!(
                "{} The dressing room mood dips — {} teammates lose morale.",
                description, affected
            );
        }
    }

    // Mark the action as resolved
    if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id) {
        if let Some(act) = msg.actions.iter_mut().find(|a| a.id == action_id) {
            act.resolved = true;
        }
    }

    Some(description)
}

// ---------------------------------------------------------------------------
// Message builders
// ---------------------------------------------------------------------------

fn low_morale_message(
    msg_id: &str,
    player_id: &str,
    player_name: &str,
    morale: u8,
    date: &str,
) -> InboxMessage {
    let mut rng = rand::thread_rng();
    let variations = [
        format!(
            "Boss, {} has asked for a private meeting. They seem really down lately and want to talk about their situation at the club.\n\n\
            Their morale is at {} — you should address this before it affects the dressing room.",
            player_name, morale
        ),
        format!(
            "{} has been looking dejected in training. They've requested a chat with you about their current state of mind.\n\n\
            Morale: {}. How you handle this could make or break their confidence.",
            player_name, morale
        ),
    ];
    let idx = rng.gen_range(0..variations.len());

    InboxMessage::new(
        msg_id.to_string(),
        format!("{} — Morale Crisis", player_name),
        variations[idx].clone(),
        player_name.to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::PlayerMorale)
    .with_priority(MessagePriority::High)
    .with_sender_role("Player")
    .with_action(action(
        "respond",
        "Respond",
        "be.msg.playerEvent.respond",
        ActionType::ChooseOption {
            options: vec![
                ActionOption {
                    id: "encourage".to_string(),
                    label: "Encourage them".to_string(),
                    description: "Show empathy and encourage the player to keep working hard.".to_string(),
                },
                ActionOption {
                    id: "promise_time".to_string(),
                    label: "Promise more playing time".to_string(),
                    description: "Tell them they'll get their chance — bigger morale boost but sets expectations.".to_string(),
                },
                ActionOption {
                    id: "work_harder".to_string(),
                    label: "Tell them to work harder".to_string(),
                    description: "Tough love approach — could backfire or motivate them.".to_string(),
                },
            ],
        },
    ))
    .with_context(MessageContext {
        player_id: Some(player_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        "be.msg.moraleCrisis.subject",
        &format!("be.msg.moraleCrisis.body{}", idx),
        params(&[("player", player_name), ("morale", &morale.to_string())]),
    )
    .with_sender_i18n("be.sender.player", "be.role.player")
}

fn bench_complaint_message(
    msg_id: &str,
    player_id: &str,
    player_name: &str,
    date: &str,
) -> InboxMessage {
    let mut rng = rand::thread_rng();
    let variations = [
        format!(
            "Boss, {} has come to see you. They're frustrated about their lack of game time in recent matches and want to know what they need to do to get back in the team.\n\n\
            \"I feel like I've been training well, but I'm not getting a chance to show it on the pitch.\"",
            player_name
        ),
        format!(
            "{} knocked on your office door looking unhappy. They haven't featured in the last few matches and want answers.\n\n\
            \"I came to this club to play football. If I'm not in your plans, I'd rather you tell me straight.\"",
            player_name
        ),
    ];
    let idx = rng.gen_range(0..variations.len());

    InboxMessage::new(
        msg_id.to_string(),
        format!("{} — Wants More Game Time", player_name),
        variations[idx].clone(),
        player_name.to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::PlayerMorale)
    .with_priority(MessagePriority::Normal)
    .with_sender_role("Player")
    .with_action(action(
        "respond",
        "Respond",
        "be.msg.playerEvent.respond",
        ActionType::ChooseOption {
            options: vec![
                ActionOption {
                    id: "explain".to_string(),
                    label: "Explain the situation".to_string(),
                    description: "Calmly explain squad competition and rotation. Steady morale boost.".to_string(),
                },
                ActionOption {
                    id: "promise_chance".to_string(),
                    label: "Promise them a chance soon".to_string(),
                    description: "They'll be happier but will expect to start in upcoming matches.".to_string(),
                },
                ActionOption {
                    id: "prove_yourself".to_string(),
                    label: "Tell them to prove themselves".to_string(),
                    description: "Challenge them to earn their place. Risky — could motivate or frustrate.".to_string(),
                },
            ],
        },
    ))
    .with_context(MessageContext {
        player_id: Some(player_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        "be.msg.benchComplaint.subject",
        &format!("be.msg.benchComplaint.body{}", idx),
        params(&[("player", player_name)]),
    )
    .with_sender_i18n("be.sender.player", "be.role.player")
}

fn happy_player_message(
    msg_id: &str,
    player_id: &str,
    player_name: &str,
    date: &str,
) -> InboxMessage {
    let mut rng = rand::thread_rng();
    let variations = [
        format!(
            "{} stopped by your office with a big smile. They're feeling great about their form and the team's direction.\n\n\
            \"Just wanted to say I'm really enjoying my football right now, boss. The mood in the dressing room is fantastic.\"",
            player_name
        ),
        format!(
            "Your assistant mentions that {} has been in excellent spirits lately. They approached you after training.\n\n\
            \"Boss, I'm loving every minute here. Keep things going like this and I'll run through walls for you.\"",
            player_name
        ),
    ];
    let idx = rng.gen_range(0..variations.len());

    InboxMessage::new(
        msg_id.to_string(),
        format!("{} — Feeling Great", player_name),
        variations[idx].clone(),
        player_name.to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::PlayerMorale)
    .with_priority(MessagePriority::Low)
    .with_sender_role("Player")
    .with_action(action(
        "respond",
        "Respond",
        "be.msg.playerEvent.respond",
        ActionType::ChooseOption {
            options: vec![
                ActionOption {
                    id: "praise_back".to_string(),
                    label: "Return the praise".to_string(),
                    description: "Tell them how much you value their contribution.".to_string(),
                },
                ActionOption {
                    id: "stay_professional".to_string(),
                    label: "Stay professional".to_string(),
                    description: "Acknowledge their form but keep things measured.".to_string(),
                },
                ActionOption {
                    id: "higher_expectations".to_string(),
                    label: "Set higher expectations".to_string(),
                    description: "Challenge them to reach an even higher level. Could push or pressure.".to_string(),
                },
            ],
        },
    ))
    .with_context(MessageContext {
        player_id: Some(player_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        "be.msg.happyPlayer.subject",
        &format!("be.msg.happyPlayer.body{}", idx),
        params(&[("player", player_name)]),
    )
    .with_sender_i18n("be.sender.player", "be.role.player")
}

fn contract_concern_message(
    msg_id: &str,
    player_id: &str,
    player_name: &str,
    days_remaining: i64,
    date: &str,
) -> InboxMessage {
    let months = (days_remaining as f64 / 30.0).ceil() as u32;
    let mut rng = rand::thread_rng();
    let variations = [
        format!(
            "{} has approached you regarding their contract situation. With only {} days remaining on their deal, they want to know where they stand.\n\n\
            \"Boss, my contract is running down. I need to know if I'm part of your plans going forward or if I should start looking elsewhere.\"",
            player_name, days_remaining
        ),
        format!(
            "Your assistant flags that {}'s contract expires in roughly {} month(s). The player has been asking around the dressing room about their future.\n\n\
            It might be wise to have a conversation before they become unsettled — or before other clubs start circling.",
            player_name, months
        ),
    ];
    let idx = rng.gen_range(0..variations.len());

    InboxMessage::new(
        msg_id.to_string(),
        format!("{} — Contract Running Down", player_name),
        variations[idx].clone(),
        "Assistant Manager".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::Contract)
    .with_priority(MessagePriority::High)
    .with_sender_role("Assistant Manager")
    .with_action(action(
        "respond",
        "Respond",
        "be.msg.playerEvent.respond",
        ActionType::ChooseOption {
            options: vec![
                ActionOption {
                    id: "reassure".to_string(),
                    label: "Reassure them about renewal".to_string(),
                    description: "Tell them you want them to stay. Big morale boost.".to_string(),
                },
                ActionOption {
                    id: "noncommittal".to_string(),
                    label: "Be noncommittal".to_string(),
                    description: "Keep your options open. Player may become unsettled.".to_string(),
                },
                ActionOption {
                    id: "no_renewal".to_string(),
                    label: "Tell them you won't renew".to_string(),
                    description: "Honest but brutal. Morale will tank.".to_string(),
                },
            ],
        },
    ))
    .with_context(MessageContext {
        player_id: Some(player_id.to_string()),
        ..Default::default()
    })
    .with_i18n(
        "be.msg.contractConcern.subject",
        &format!("be.msg.contractConcern.body{}", idx),
        params(&[
            ("player", player_name),
            ("days", &days_remaining.to_string()),
            ("months", &months.to_string()),
        ]),
    )
    .with_sender_i18n("be.sender.assistantManager", "be.role.assistantManager")
}
