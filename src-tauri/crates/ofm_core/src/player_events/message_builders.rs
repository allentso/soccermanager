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

pub(crate) fn low_morale_message(
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

pub(crate) fn bench_complaint_message(
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
                    description:
                        "Calmly explain squad competition and rotation. Steady morale boost."
                            .to_string(),
                },
                ActionOption {
                    id: "promise_chance".to_string(),
                    label: "Promise them a chance soon".to_string(),
                    description: "They'll be happier but will expect to start in upcoming matches."
                        .to_string(),
                },
                ActionOption {
                    id: "prove_yourself".to_string(),
                    label: "Tell them to prove themselves".to_string(),
                    description:
                        "Challenge them to earn their place. Risky — could motivate or frustrate."
                            .to_string(),
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

pub(crate) fn happy_player_message(
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
                    description:
                        "Challenge them to reach an even higher level. Could push or pressure."
                            .to_string(),
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

pub(crate) fn contract_concern_message(
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
