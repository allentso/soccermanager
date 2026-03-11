use crate::game::Game;
use domain::player::{Player, RecentTreatmentMemory};
use rand::Rng;
use serde::Serialize;
use std::collections::HashMap;

/// Personality factor derived from player attributes. Affects how they react.
/// Returns a value from -20 to +20, where positive = more receptive, negative = more volatile.
fn personality_factor(player: &domain::player::Player) -> i8 {
    let composure = player.attributes.composure as i16;
    let leadership = player.attributes.leadership as i16;
    let aggression = player.attributes.aggression as i16;
    // Composed leaders are receptive; aggressive low-composure players are volatile
    ((composure + leadership - aggression) / 6).clamp(-20, 20) as i8
}

#[derive(Debug, Clone, Serialize)]
pub struct PlayerResponseEffect {
    pub message: String,
    pub i18n_key: String,
    pub i18n_params: HashMap<String, String>,
}

struct ResponseOutcome {
    delta: i8,
    effect_key: String,
    description: String,
    i18n_params: HashMap<String, String>,
}

fn signed_delta(delta: i8) -> String {
    if delta >= 0 {
        format!("+{}", delta)
    } else {
        delta.to_string()
    }
}

fn base_effect_params(delta: i8) -> HashMap<String, String> {
    HashMap::from([("delta".to_string(), signed_delta(delta))])
}

fn outcome(delta: i8, effect_key: &str, description: String) -> ResponseOutcome {
    ResponseOutcome {
        delta,
        effect_key: effect_key.to_string(),
        description,
        i18n_params: base_effect_params(delta),
    }
}

fn treatment_key(message_id: &str, option_id: &str) -> String {
    let family = if message_id.starts_with("morale_talk_") {
        "morale_talk"
    } else if message_id.starts_with("bench_complaint_") {
        "bench_complaint"
    } else if message_id.starts_with("happy_player_") {
        "happy_player"
    } else if message_id.starts_with("contract_concern_") {
        "contract_concern"
    } else {
        "player_event"
    };

    format!("{}:{}", family, option_id)
}

fn base_trust_delta(message_id: &str, option_id: &str) -> i16 {
    if message_id.starts_with("morale_talk_") {
        return match option_id {
            "encourage" => 4,
            "promise_time" => 8,
            "work_harder" => -3,
            _ => 0,
        };
    }

    if message_id.starts_with("bench_complaint_") {
        return match option_id {
            "explain" => 3,
            "promise_chance" => 6,
            "prove_yourself" => -2,
            _ => 0,
        };
    }

    if message_id.starts_with("happy_player_") {
        return match option_id {
            "praise_back" => 2,
            "stay_professional" => 0,
            "higher_expectations" => -1,
            _ => 0,
        };
    }

    if message_id.starts_with("contract_concern_") {
        return match option_id {
            "reassure" => 5,
            "noncommittal" => -4,
            "no_renewal" => -8,
            _ => 0,
        };
    }

    0
}

fn reduced_by_recent_treatment(delta: i8, player: &Player, action_key: &str) -> i8 {
    let Some(memory) = player.morale_core.recent_treatment.as_ref() else {
        return delta;
    };

    if memory.action_key != action_key || delta <= 0 {
        return delta;
    }

    let reduced = i16::from(delta) - i16::from(memory.times_recently_used) * 4;
    reduced.max(0) as i8
}

fn capped_by_unresolved_issue(delta: i8, player: &Player) -> i8 {
    let Some(issue) = player.morale_core.unresolved_issue.as_ref() else {
        return delta;
    };

    if delta <= 0 {
        return delta;
    }

    if issue.severity >= 75 {
        return 0;
    }

    if issue.severity >= 50 {
        return ((i16::from(delta) + 1) / 2).max(1) as i8;
    }

    delta
}

fn trust_delta_with_memory(base_delta: i16, player: &Player, action_key: &str) -> i16 {
    let Some(memory) = player.morale_core.recent_treatment.as_ref() else {
        return base_delta;
    };

    if memory.action_key != action_key || base_delta <= 0 {
        return base_delta;
    }

    base_delta / (i16::from(memory.times_recently_used) + 1)
}

fn update_recent_treatment(player: &mut Player, action_key: &str) {
    match player.morale_core.recent_treatment.as_mut() {
        Some(memory) if memory.action_key == action_key => {
            memory.times_recently_used = memory.times_recently_used.saturating_add(1);
        }
        Some(memory) => {
            memory.action_key = action_key.to_string();
            memory.times_recently_used = 1;
        }
        None => {
            player.morale_core.recent_treatment = Some(RecentTreatmentMemory {
                action_key: action_key.to_string(),
                times_recently_used: 1,
            });
        }
    }
}

/// Apply the effect of a player conversation choice.
/// Returns a description of what happened, or None if the message wasn't a player event.
pub fn apply_player_response(
    game: &mut Game,
    message_id: &str,
    action_id: &str,
    option_id: &str,
) -> Option<PlayerResponseEffect> {
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
    let mut outcome = if message_id.starts_with("morale_talk_") {
        match option_id {
            "encourage" => {
                // Safe option but small boost; volatile players shrug it off
                let d = rng.gen_range(2..=8) + (pf / 4);
                if d > 0 {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.moraleCrisis.encourage.positive",
                        format!("Player feels a bit better. Morale +{}", d),
                    )
                } else {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.moraleCrisis.encourage.negative",
                        format!("Player doesn't buy it. Morale {}", d),
                    )
                }
            }
            "promise_time" => {
                // Big boost but sets a PROMISE — if not honored, bigger penalty later
                let d = rng.gen_range(10..=16);
                outcome(
                    d,
                    "be.msg.playerEvent.effects.moraleCrisis.promiseTime",
                    format!(
                        "Player is reassured by the promise. Morale +{}. They'll expect to start soon.",
                        d
                    ),
                )
            }
            "work_harder" => {
                // Risky: aggressive players hate this, composed ones respond well
                let d = rng.gen_range(-12..=4) + (pf / 3);
                if d >= 0 {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.moraleCrisis.workHarder.positive",
                        format!("Player accepts the challenge. Morale +{}", d),
                    )
                } else {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.moraleCrisis.workHarder.negative",
                        format!("Player is offended by the tough love. Morale {}", d),
                    )
                }
            }
            _ => return None,
        }
    } else if message_id.starts_with("bench_complaint_") {
        match option_id {
            "explain" => {
                // Moderate; only works on composed players
                let d = rng.gen_range(-2..=6) + (pf / 4);
                if d >= 0 {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.benchComplaint.explain.positive",
                        format!("Player grudgingly accepts. Morale +{}", d),
                    )
                } else {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.benchComplaint.explain.negative",
                        format!("Player isn't convinced. Morale {}", d),
                    )
                }
            }
            "promise_chance" => {
                // PROMISE — big boost now, tracked for consequences
                let d = rng.gen_range(8..=14);
                outcome(
                    d,
                    "be.msg.playerEvent.effects.benchComplaint.promiseChance",
                    format!(
                        "Player is excited about the opportunity. Morale +{}. They expect to start next match.",
                        d
                    ),
                )
            }
            "prove_yourself" => {
                // Very risky — high-aggression players rebel
                let d = rng.gen_range(-10..=6) + (pf / 3);
                if d >= 0 {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.benchComplaint.proveYourself.positive",
                        format!("Player is fired up to prove their worth. Morale +{}", d),
                    )
                } else {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.benchComplaint.proveYourself.negative",
                        format!("Player feels dismissed and insulted. Morale {}", d),
                    )
                }
            }
            _ => return None,
        }
    } else if message_id.starts_with("happy_player_") {
        match option_id {
            "praise_back" => {
                let d = rng.gen_range(2..=5);
                outcome(
                    d,
                    "be.msg.playerEvent.effects.happyPlayer.praiseBack",
                    format!("Player beams at the praise. Morale +{}", d),
                )
            }
            "stay_professional" => {
                // Neutral — can slightly drop morale on volatile players
                let d = rng.gen_range(-2..=3) + (pf / 6);
                if d >= 0 {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.happyPlayer.stayProfessional.positive",
                        format!("Player nods professionally. Morale +{}", d),
                    )
                } else {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.happyPlayer.stayProfessional.negative",
                        format!("Player wanted more warmth. Morale {}", d),
                    )
                }
            }
            "higher_expectations" => {
                // Risky: leaders respond well, others feel pressured
                let d = rng.gen_range(-6..=4) + (pf / 3);
                if d >= 0 {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.happyPlayer.higherExpectations.positive",
                        format!("Player rises to the challenge. Morale +{}", d),
                    )
                } else {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.happyPlayer.higherExpectations.negative",
                        format!("Player feels the pressure is unfair. Morale {}", d),
                    )
                }
            }
            _ => return None,
        }
    } else if message_id.starts_with("contract_concern_") {
        match option_id {
            "reassure" => {
                // Sets expectation of renewal — moderate boost
                let d = rng.gen_range(4..=10);
                outcome(
                    d,
                    "be.msg.playerEvent.effects.contractConcern.reassure",
                    format!("Player is reassured about their future. Morale +{}", d),
                )
            }
            "noncommittal" => {
                // Almost always negative — players hate uncertainty
                let d = rng.gen_range(-8..=0) + (pf / 5);
                if d >= 0 {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.contractConcern.noncommittal.positive",
                        format!("Player grudgingly accepts for now. Morale +{}", d),
                    )
                } else {
                    outcome(
                        d,
                        "be.msg.playerEvent.effects.contractConcern.noncommittal.negative",
                        format!("Player is unsettled and unhappy. Morale {}", d),
                    )
                }
            }
            "no_renewal" => {
                let d = rng.gen_range(-15..=-8);
                outcome(
                    d,
                    "be.msg.playerEvent.effects.contractConcern.noRenewal",
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
    outcome.delta = outcome.delta.clamp(-20, 20);

    // Apply morale change
    if let Some(player) = game.players.iter_mut().find(|p| p.id == player_id) {
        let action_key = treatment_key(message_id, option_id);
        let adjusted_delta = capped_by_unresolved_issue(
            reduced_by_recent_treatment(outcome.delta, player, &action_key),
            player,
        );
        let trust_delta =
            trust_delta_with_memory(base_trust_delta(message_id, option_id), player, &action_key);

        outcome.delta = adjusted_delta.clamp(-20, 20);
        outcome
            .i18n_params
            .insert("delta".to_string(), signed_delta(outcome.delta));

        let base = player.morale as i16;
        player.morale = (base + outcome.delta as i16).clamp(5, 100) as u8;

        let trust = (i16::from(player.morale_core.manager_trust) + trust_delta).clamp(0, 100) as u8;
        player.morale_core.manager_trust = trust;
        update_recent_treatment(player, &action_key);
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
            outcome.description = format!(
                "{} The dressing room mood dips — {} teammates lose morale.",
                outcome.description, affected
            );
            outcome.effect_key =
                "be.msg.playerEvent.effects.contractConcern.noRenewalWithDressingRoom".to_string();
            outcome
                .i18n_params
                .insert("affected".to_string(), affected.to_string());
        }
    }

    // Mark the action as resolved
    if let Some(msg) = game.messages.iter_mut().find(|m| m.id == message_id)
        && let Some(act) = msg.actions.iter_mut().find(|a| a.id == action_id)
    {
        act.resolved = true;
    }

    Some(PlayerResponseEffect {
        message: outcome.description,
        i18n_key: outcome.effect_key,
        i18n_params: outcome.i18n_params,
    })
}
