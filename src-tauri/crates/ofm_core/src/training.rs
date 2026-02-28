use crate::game::Game;
use domain::staff::{CoachingSpecialization, StaffRole};
use domain::team::{TrainingFocus, TrainingIntensity, TrainingSchedule};

/// Computed coaching quality for a team's staff.
pub struct TeamCoachingBonus {
    pub coaching_mult: f64,      // Overall coaching quality multiplier (1.0 = no staff)
    pub specialization_mult: f64, // Extra bonus if a coach specializes in the current focus
    pub physio_mult: f64,         // Recovery bonus from physio staff
}

/// Compute coaching bonuses from a team's staff.
fn compute_coaching_bonus(game: &Game, team_id: &str, focus: &TrainingFocus) -> TeamCoachingBonus {
    let team_staff: Vec<_> = game.staff.iter()
        .filter(|s| s.team_id.as_deref() == Some(team_id))
        .collect();

    // Average coaching rating of coaches + assistant managers
    let coaching_staff: Vec<_> = team_staff.iter()
        .filter(|s| matches!(s.role, StaffRole::Coach | StaffRole::AssistantManager))
        .collect();

    let coaching_mult = if coaching_staff.is_empty() {
        0.8 // Penalty for having no coaching staff
    } else {
        let avg_coaching: f64 = coaching_staff.iter()
            .map(|s| s.attributes.coaching as f64)
            .sum::<f64>() / coaching_staff.len() as f64;
        // Range: 0.85 (coaching=0) to 1.35 (coaching=100)
        0.85 + (avg_coaching / 100.0) * 0.5
    };

    // Check if any coach specializes in the current training focus
    let focus_spec = match focus {
        TrainingFocus::Physical => Some(CoachingSpecialization::Fitness),
        TrainingFocus::Technical => Some(CoachingSpecialization::Technique),
        TrainingFocus::Tactical => Some(CoachingSpecialization::Tactics),
        TrainingFocus::Defending => Some(CoachingSpecialization::Defending),
        TrainingFocus::Attacking => Some(CoachingSpecialization::Attacking),
        TrainingFocus::Recovery => None,
    };

    let specialization_mult = if let Some(target_spec) = focus_spec {
        let has_specialist = coaching_staff.iter().any(|s| {
            s.specialization.as_ref() == Some(&target_spec)
        });
        if has_specialist { 1.25 } else { 1.0 }
    } else {
        1.0
    };

    // Physio bonus for recovery
    let physio_staff: Vec<_> = team_staff.iter()
        .filter(|s| matches!(s.role, StaffRole::Physio))
        .collect();

    let physio_mult = if physio_staff.is_empty() {
        1.0
    } else {
        let avg_physio: f64 = physio_staff.iter()
            .map(|s| s.attributes.physiotherapy as f64)
            .sum::<f64>() / physio_staff.len() as f64;
        // Range: 1.0 (physio=0) to 1.4 (physio=100)
        1.0 + (avg_physio / 100.0) * 0.4
    };

    TeamCoachingBonus {
        coaching_mult,
        specialization_mult,
        physio_mult,
    }
}

/// Process daily training for all teams.
/// On non-match days each team's players train according to the team's
/// current focus, intensity, and schedule. Rest days (determined by the
/// weekly schedule) give full condition recovery with no training cost.
/// `weekday_num` is 0=Mon .. 6=Sun (chrono Weekday::num_days_from_monday()).
pub fn process_training(game: &mut Game, weekday_num: u32) {
    // Collect (team_id, focus, intensity, schedule, coaching_bonus) for all teams
    let team_plans: Vec<(String, TrainingFocus, TrainingIntensity, TrainingSchedule, TeamCoachingBonus)> = game
        .teams
        .iter()
        .map(|t| {
            let bonus = compute_coaching_bonus(game, &t.id, &t.training_focus);
            (
                t.id.clone(),
                t.training_focus.clone(),
                t.training_intensity.clone(),
                t.training_schedule.clone(),
                bonus,
            )
        })
        .collect();

    for (team_id, focus, intensity, schedule, bonus) in &team_plans {
        let is_training_day = schedule.is_training_day(weekday_num);

        let intensity_mult = match intensity {
            TrainingIntensity::Low => 0.5,
            TrainingIntensity::Medium => 1.0,
            TrainingIntensity::High => 1.5,
        };

        // On rest days or Recovery focus: no training cost
        let condition_cost: u8 = if !is_training_day {
            0
        } else {
            match (&focus, intensity) {
                (TrainingFocus::Recovery, _) => 0,
                (_, TrainingIntensity::Low) => 3,
                (_, TrainingIntensity::Medium) => 6,
                (_, TrainingIntensity::High) => 10,
            }
        };

        // Recovery amount: rest days get boosted recovery (like Recovery focus)
        let recovery_base: f64 = if !is_training_day {
            // Rest day: generous recovery, boosted by physio
            10.0 * bonus.physio_mult
        } else {
            match focus {
                TrainingFocus::Recovery => 12.0 * bonus.physio_mult,
                _ => 3.0 * bonus.physio_mult,
            }
        };

        for player in game.players.iter_mut() {
            if player.team_id.as_deref() != Some(team_id) {
                continue;
            }
            // Skip injured players
            if player.injury.is_some() {
                // Injured players just get base recovery (physio helps)
                let recovery = (recovery_base * 0.5) as u8;
                player.condition = (player.condition + recovery).min(100);
                continue;
            }

            // On rest days: only recovery, no attribute gains
            if !is_training_day {
                let stamina_factor = player.attributes.stamina as f64 / 100.0;
                let recovery = (recovery_base * (0.5 + stamina_factor * 0.5)) as u8;
                player.condition = (player.condition + recovery).min(100);
                continue;
            }

            // Age factor: younger players grow faster, older players slower
            let age = estimate_age(&player.date_of_birth);
            let age_factor = if age <= 21 {
                1.5
            } else if age <= 25 {
                1.2
            } else if age <= 29 {
                1.0
            } else if age <= 33 {
                0.6
            } else {
                0.3
            };

            // Base gain per attribute per session, boosted by coaching staff
            let gain = 0.15 * intensity_mult * age_factor * bonus.coaching_mult * bonus.specialization_mult;

            // Apply attribute gains based on focus
            apply_focus_gains(&mut player.attributes, focus, gain);

            // Apply condition: deplete from training, then recover
            player.condition = player.condition.saturating_sub(condition_cost);
            let stamina_factor = player.attributes.stamina as f64 / 100.0;
            let recovery = (recovery_base * (0.5 + stamina_factor * 0.5)) as u8;
            player.condition = (player.condition + recovery).min(100);
        }
    }
}

/// Check squad fitness and generate staff warning messages when players are exhausted.
/// Called after training processing on each day.
pub fn check_squad_fitness_warnings(game: &mut Game) {
    let user_team_id = match &game.manager.team_id {
        Some(id) => id.clone(),
        None => return,
    };

    let date = game.clock.current_date.to_rfc3339();
    let today_str = game.clock.current_date.format("%Y-%m-%d").to_string();

    // Collect fitness data for user's team
    let team_players: Vec<_> = game.players.iter()
        .filter(|p| p.team_id.as_deref() == Some(&user_team_id) && p.injury.is_none())
        .collect();

    if team_players.is_empty() {
        return;
    }

    let avg_condition = team_players.iter().map(|p| p.condition as f64).sum::<f64>() / team_players.len() as f64;
    let exhausted_count = team_players.iter().filter(|p| p.condition < 40).count();
    let critical_count = team_players.iter().filter(|p| p.condition < 25).count();

    // Deduplicate: only one warning per day
    let msg_id = format!("fitness_warn_{}", today_str);
    if game.messages.iter().any(|m| m.id == msg_id) {
        return;
    }

    // Get team schedule for context
    let schedule = game.teams.iter()
        .find(|t| t.id == user_team_id)
        .map(|t| t.training_schedule.clone())
        .unwrap_or_default();

    let intensity = game.teams.iter()
        .find(|t| t.id == user_team_id)
        .map(|t| t.training_intensity.clone())
        .unwrap_or_default();

    // Determine if we need a physio/staff role sender
    let has_physio = game.staff.iter().any(|s| {
        s.team_id.as_deref() == Some(&user_team_id)
            && matches!(s.role, domain::staff::StaffRole::Physio)
    });

    let sender = if has_physio { "Head Physio" } else { "Assistant Manager" };
    let sender_name = if has_physio {
        game.staff.iter()
            .find(|s| s.team_id.as_deref() == Some(&user_team_id) && matches!(s.role, domain::staff::StaffRole::Physio))
            .map(|s| format!("{} {}", s.first_name, s.last_name))
            .unwrap_or_else(|| "Medical Staff".to_string())
    } else {
        game.staff.iter()
            .find(|s| s.team_id.as_deref() == Some(&user_team_id) && matches!(s.role, domain::staff::StaffRole::AssistantManager))
            .map(|s| format!("{} {}", s.first_name, s.last_name))
            .unwrap_or_else(|| "Assistant Manager".to_string())
    };

    use domain::message::*;

    // Critical: multiple players below 25 condition
    if critical_count >= 3 {
        let exhausted_names: Vec<String> = team_players.iter()
            .filter(|p| p.condition < 25)
            .take(5)
            .map(|p| format!("{} ({}%)", p.match_name, p.condition))
            .collect();

        let schedule_advice = match schedule {
            TrainingSchedule::Intense => "I strongly recommend switching to a Balanced or Light training schedule immediately. \
                The Intense schedule is running the squad into the ground.",
            TrainingSchedule::Balanced => "Consider switching to a Light schedule or setting the focus to Recovery \
                until fitness levels improve.",
            TrainingSchedule::Light => "Even on the Light schedule, the squad is struggling. Please set the training focus \
                to Recovery — the lads need proper rest.",
        };

        let intensity_advice = match intensity {
            TrainingIntensity::High => " Also, reducing training intensity from High would help significantly.",
            TrainingIntensity::Medium => "",
            TrainingIntensity::Low => "",
        };

        let body = format!(
            "Boss, we have a serious fitness crisis. {} players are in critical condition and at risk of injury:\n\n\
            {}\n\n\
            Average squad fitness is at {:.0}%. {}{}\n\n\
            If we push them further without rest, injuries are inevitable.",
            critical_count,
            exhausted_names.join("\n"),
            avg_condition,
            schedule_advice,
            intensity_advice,
        );

        let msg = InboxMessage::new(
            msg_id,
            "URGENT: Squad Fitness Crisis".to_string(),
            body,
            sender_name,
            date,
        )
        .with_category(MessageCategory::Training)
        .with_priority(MessagePriority::Urgent)
        .with_sender_role(sender)
        .with_action(MessageAction {
            id: "go_training".to_string(),
            label: "Adjust Training".to_string(),
            action_type: ActionType::NavigateTo { route: "/dashboard?tab=Training".to_string() },
            resolved: false,
        })
        .with_context(MessageContext {
            team_id: Some(user_team_id),
            ..Default::default()
        });

        game.messages.push(msg);
        return;
    }

    // Warning: average condition below 50 or many exhausted players
    if avg_condition < 50.0 || exhausted_count >= 4 {
        let schedule_advice = match schedule {
            TrainingSchedule::Intense => "Switching to a Balanced schedule would give the squad more recovery time.",
            TrainingSchedule::Balanced => "A Light schedule for a few days could help the squad bounce back.",
            TrainingSchedule::Light => "Setting the training focus to Recovery would maximise fitness gains.",
        };

        let body = format!(
            "Boss, the squad is looking tired. Average fitness is {:.0}% and {} players are below 40% condition.\n\n\
            {}\n\n\
            We should consider giving the lads some rest before the next match.",
            avg_condition,
            exhausted_count,
            schedule_advice,
        );

        let msg = InboxMessage::new(
            msg_id,
            "Squad Fitness Warning".to_string(),
            body,
            sender_name,
            date,
        )
        .with_category(MessageCategory::Training)
        .with_priority(MessagePriority::High)
        .with_sender_role(sender)
        .with_action(MessageAction {
            id: "go_training".to_string(),
            label: "Adjust Training".to_string(),
            action_type: ActionType::NavigateTo { route: "/dashboard?tab=Training".to_string() },
            resolved: false,
        })
        .with_context(MessageContext {
            team_id: Some(user_team_id),
            ..Default::default()
        });

        game.messages.push(msg);
    }
}

/// Probabilistic attribute gain: gain=0.3 means 30% chance of +1, capped at 99.
fn try_gain(current: &mut u8, gain: f64) {
    use rand::Rng;
    if *current >= 99 {
        return;
    }
    let mut rng = rand::thread_rng();
    let roll: f64 = rng.gen_range(0.0..1.0);
    if roll < gain {
        *current = (*current + 1).min(99);
    }
}

/// Apply attribute gains based on training focus.
fn apply_focus_gains(
    attrs: &mut domain::player::PlayerAttributes,
    focus: &TrainingFocus,
    gain: f64,
) {
    match focus {
        TrainingFocus::Physical => {
            try_gain(&mut attrs.pace, gain);
            try_gain(&mut attrs.stamina, gain);
            try_gain(&mut attrs.strength, gain);
            try_gain(&mut attrs.agility, gain);
        }
        TrainingFocus::Technical => {
            try_gain(&mut attrs.passing, gain);
            try_gain(&mut attrs.shooting, gain);
            try_gain(&mut attrs.dribbling, gain);
        }
        TrainingFocus::Tactical => {
            try_gain(&mut attrs.positioning, gain);
            try_gain(&mut attrs.vision, gain);
            try_gain(&mut attrs.decisions, gain);
            try_gain(&mut attrs.composure, gain);
        }
        TrainingFocus::Defending => {
            try_gain(&mut attrs.tackling, gain);
            try_gain(&mut attrs.defending, gain);
            try_gain(&mut attrs.strength, gain * 0.5);
            try_gain(&mut attrs.positioning, gain * 0.5);
        }
        TrainingFocus::Attacking => {
            try_gain(&mut attrs.shooting, gain);
            try_gain(&mut attrs.dribbling, gain);
            try_gain(&mut attrs.pace, gain * 0.5);
        }
        TrainingFocus::Recovery => {
            // No attribute gains on recovery days
        }
    }
}

/// Estimate player age from date_of_birth string ("YYYY-MM-DD").
fn estimate_age(dob: &str) -> u32 {
    let parts: Vec<&str> = dob.split('-').collect();
    if parts.len() < 1 {
        return 25; // fallback
    }
    let birth_year: u32 = parts[0].parse().unwrap_or(2000);
    // Use a rough estimate — the game clock year would be ideal but
    // this is close enough for growth factor purposes.
    let current_year: u32 = 2025;
    current_year.saturating_sub(birth_year)
}
