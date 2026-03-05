use crate::game::Game;
use rand::Rng;

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
    let pf = game
        .players
        .iter()
        .find(|p| p.id == player_id)
        .map(personality_factor)
        .unwrap_or(0);

    // Base deltas are now more punishing; personality modifies the outcome
    let (mut delta, mut description) = if message_id.starts_with("morale_talk_") {
        match option_id {
            "encourage" => {
                // Safe option but small boost; volatile players shrug it off
                let d = rng.gen_range(2..=8) + (pf / 4);
                (
                    d,
                    if d > 0 {
                        format!("Player feels a bit better. Morale +{}", d)
                    } else {
                        format!("Player doesn't buy it. Morale {}", d)
                    },
                )
            }
            "promise_time" => {
                // Big boost but sets a PROMISE — if not honored, bigger penalty later
                let d = rng.gen_range(10..=16);
                (
                    d,
                    format!(
                        "Player is reassured by the promise. Morale +{}. They'll expect to start soon.",
                        d
                    ),
                )
            }
            "work_harder" => {
                // Risky: aggressive players hate this, composed ones respond well
                let d = rng.gen_range(-12..=4) + (pf / 3);
                (
                    d,
                    if d >= 0 {
                        format!("Player accepts the challenge. Morale +{}", d)
                    } else {
                        format!("Player is offended by the tough love. Morale {}", d)
                    },
                )
            }
            _ => return None,
        }
    } else if message_id.starts_with("bench_complaint_") {
        match option_id {
            "explain" => {
                // Moderate; only works on composed players
                let d = rng.gen_range(-2..=6) + (pf / 4);
                (
                    d,
                    if d >= 0 {
                        format!("Player grudgingly accepts. Morale +{}", d)
                    } else {
                        format!("Player isn't convinced. Morale {}", d)
                    },
                )
            }
            "promise_chance" => {
                // PROMISE — big boost now, tracked for consequences
                let d = rng.gen_range(8..=14);
                (
                    d,
                    format!(
                        "Player is excited about the opportunity. Morale +{}. They expect to start next match.",
                        d
                    ),
                )
            }
            "prove_yourself" => {
                // Very risky — high-aggression players rebel
                let d = rng.gen_range(-10..=6) + (pf / 3);
                (
                    d,
                    if d >= 0 {
                        format!("Player is fired up to prove their worth. Morale +{}", d)
                    } else {
                        format!("Player feels dismissed and insulted. Morale {}", d)
                    },
                )
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
                (
                    d,
                    if d >= 0 {
                        format!("Player nods professionally. Morale +{}", d)
                    } else {
                        format!("Player wanted more warmth. Morale {}", d)
                    },
                )
            }
            "higher_expectations" => {
                // Risky: leaders respond well, others feel pressured
                let d = rng.gen_range(-6..=4) + (pf / 3);
                (
                    d,
                    if d >= 0 {
                        format!("Player rises to the challenge. Morale +{}", d)
                    } else {
                        format!("Player feels the pressure is unfair. Morale {}", d)
                    },
                )
            }
            _ => return None,
        }
    } else if message_id.starts_with("contract_concern_") {
        match option_id {
            "reassure" => {
                // Sets expectation of renewal — moderate boost
                let d = rng.gen_range(4..=10);
                (
                    d,
                    format!("Player is reassured about their future. Morale +{}", d),
                )
            }
            "noncommittal" => {
                // Almost always negative — players hate uncertainty
                let d = rng.gen_range(-8..=0) + (pf / 5);
                (
                    d,
                    if d >= 0 {
                        format!("Player grudgingly accepts for now. Morale +{}", d)
                    } else {
                        format!("Player is unsettled and unhappy. Morale {}", d)
                    },
                )
            }
            "no_renewal" => {
                let d = rng.gen_range(-15..=-8);
                (
                    d,
                    format!(
                        "Player is devastated. Morale {}. They may affect the dressing room.",
                        d
                    ),
                )
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
    if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id)
        && let Some(act) = msg.actions.iter_mut().find(|a| a.id == action_id)
    {
        act.resolved = true;
    }

    Some(description)
}
