use rand::Rng;

use crate::event::{EventType, MatchEvent};
use crate::report::MatchReport;
use crate::types::{MatchConfig, PlayStyle, PlayerData, Position, Side, TeamData, Zone};

// ---------------------------------------------------------------------------
// Snapshot — cloned player data to avoid borrow conflicts with MatchContext
// ---------------------------------------------------------------------------

/// Lightweight snapshot of a player (id + key ratings) so we can release
/// the immutable borrow on MatchContext before emitting events.
#[derive(Clone)]
#[allow(dead_code)]
struct PlayerSnap {
    id: String,
    pace: u8,
    stamina: u8,
    strength: u8,
    agility: u8,
    passing: u8,
    shooting: u8,
    tackling: u8,
    dribbling: u8,
    defending: u8,
    positioning: u8,
    vision: u8,
    decisions: u8,
    composure: u8,
    aggression: u8,
    teamwork: u8,
    leadership: u8,
    handling: u8,
    reflexes: u8,
    aerial: u8,
    traits: Vec<String>,
}

impl PlayerSnap {
    fn from(p: &PlayerData) -> Self {
        Self {
            id: p.id.clone(),
            pace: p.pace,
            stamina: p.stamina,
            strength: p.strength,
            agility: p.agility,
            passing: p.passing,
            shooting: p.shooting,
            tackling: p.tackling,
            dribbling: p.dribbling,
            defending: p.defending,
            positioning: p.positioning,
            vision: p.vision,
            decisions: p.decisions,
            composure: p.composure,
            aggression: p.aggression,
            teamwork: p.teamwork,
            leadership: p.leadership,
            handling: p.handling,
            reflexes: p.reflexes,
            aerial: p.aerial,
            traits: p.traits.clone(),
        }
    }

    fn has_trait(&self, name: &str) -> bool {
        self.traits.iter().any(|t| t == name)
    }
}

/// Compute a multiplicative trait bonus for a specific action context.
/// Returns a modifier >= 1.0 (bonus) based on relevant traits.
fn trait_bonus(snap: &PlayerSnap, context: TraitContext) -> f64 {
    let mut bonus = 1.0;
    match context {
        TraitContext::Shooting => {
            if snap.has_trait("Sharpshooter") {
                bonus *= 1.08;
            }
            if snap.has_trait("CoolHead") {
                bonus *= 1.04;
            }
            if snap.has_trait("CompleteForward") {
                bonus *= 1.05;
            }
        }
        TraitContext::Dribbling => {
            if snap.has_trait("Dribbler") {
                bonus *= 1.08;
            }
            if snap.has_trait("Speedster") {
                bonus *= 1.04;
            }
            if snap.has_trait("Agile") {
                bonus *= 1.04;
            }
        }
        TraitContext::Passing => {
            if snap.has_trait("Playmaker") {
                bonus *= 1.08;
            }
            if snap.has_trait("Visionary") {
                bonus *= 1.05;
            }
            if snap.has_trait("SetPieceSpecialist") {
                bonus *= 1.03;
            }
        }
        TraitContext::Tackling => {
            if snap.has_trait("BallWinner") {
                bonus *= 1.08;
            }
            if snap.has_trait("Rock") {
                bonus *= 1.05;
            }
            if snap.has_trait("Tank") {
                bonus *= 1.04;
            }
        }
        TraitContext::Goalkeeping => {
            if snap.has_trait("SafeHands") {
                bonus *= 1.08;
            }
            if snap.has_trait("CatReflexes") {
                bonus *= 1.06;
            }
            if snap.has_trait("AerialDominance") {
                bonus *= 1.04;
            }
        }
        TraitContext::Foul => {
            if snap.has_trait("HotHead") {
                bonus *= 1.25;
            }
            if snap.has_trait("CoolHead") {
                bonus *= 0.70;
            }
        }
        TraitContext::Midfield => {
            if snap.has_trait("Engine") {
                bonus *= 1.06;
            }
            if snap.has_trait("TeamPlayer") {
                bonus *= 1.04;
            }
            if snap.has_trait("Tireless") {
                bonus *= 1.03;
            }
        }
    }
    bonus
}

#[derive(Debug, Clone, Copy)]
enum TraitContext {
    Shooting,
    Dribbling,
    Passing,
    Tackling,
    Goalkeeping,
    Foul,
    Midfield,
}

// ---------------------------------------------------------------------------
// MatchEngine — the core minute-by-minute simulator
// ---------------------------------------------------------------------------

/// Simulate a full match between two teams and return a detailed report.
pub fn simulate(home: &TeamData, away: &TeamData, config: &MatchConfig) -> MatchReport {
    let mut rng = rand::thread_rng();
    simulate_with_rng(home, away, config, &mut rng)
}

/// Simulate with an explicit RNG (useful for deterministic tests).
pub fn simulate_with_rng<R: Rng>(
    home: &TeamData,
    away: &TeamData,
    config: &MatchConfig,
    rng: &mut R,
) -> MatchReport {
    let mut ctx = MatchContext::new(home, away, config);

    // Kick-off
    ctx.emit(MatchEvent::new(
        0,
        EventType::KickOff,
        Side::Home,
        Zone::Midfield,
    ));
    ctx.ball_zone = Zone::Midfield;
    ctx.possession = Side::Home;

    // --- First half (minutes 1–45 + stoppage) ---
    let first_half_stoppage = rng.gen_range(0..=config.stoppage_time_max);
    let first_half_end = 45 + first_half_stoppage;
    for minute in 1..=first_half_end {
        simulate_minute(&mut ctx, minute, rng);
    }
    ctx.emit(MatchEvent::new(
        first_half_end,
        EventType::HalfTime,
        Side::Home,
        Zone::Midfield,
    ));

    // Reset ball position for second half
    let second_half_start = first_half_end + 1;
    ctx.ball_zone = Zone::Midfield;
    ctx.possession = Side::Away;
    ctx.emit(MatchEvent::new(
        second_half_start,
        EventType::SecondHalfStart,
        Side::Away,
        Zone::Midfield,
    ));

    // --- Second half (minutes 46–90 + stoppage) ---
    let second_half_stoppage = rng.gen_range(0..=config.stoppage_time_max);
    let match_end = 90 + first_half_stoppage + second_half_stoppage;
    for minute in second_half_start..=match_end {
        simulate_minute(&mut ctx, minute, rng);
    }
    let total_minutes = match_end;
    ctx.emit(MatchEvent::new(
        match_end,
        EventType::FullTime,
        Side::Home,
        Zone::Midfield,
    ));

    MatchReport::from_events(
        ctx.events,
        ctx.home_possession_ticks,
        ctx.away_possession_ticks,
        total_minutes,
    )
}

// ---------------------------------------------------------------------------
// Internal context carried through the simulation
// ---------------------------------------------------------------------------

struct MatchContext<'a> {
    home: &'a TeamData,
    away: &'a TeamData,
    config: &'a MatchConfig,
    home_score: u8,
    away_score: u8,
    ball_zone: Zone,
    possession: Side,
    events: Vec<MatchEvent>,
    home_possession_ticks: u32,
    away_possession_ticks: u32,
    yellows: std::collections::HashMap<String, u8>,
    sent_off: std::collections::HashSet<String>,
}

impl<'a> MatchContext<'a> {
    fn new(home: &'a TeamData, away: &'a TeamData, config: &'a MatchConfig) -> Self {
        Self {
            home,
            away,
            config,
            home_score: 0,
            away_score: 0,
            ball_zone: Zone::Midfield,
            possession: Side::Home,
            events: Vec::with_capacity(200),
            home_possession_ticks: 0,
            away_possession_ticks: 0,
            yellows: std::collections::HashMap::new(),
            sent_off: std::collections::HashSet::new(),
        }
    }

    fn emit(&mut self, event: MatchEvent) {
        self.events.push(event);
    }

    fn team(&self, side: Side) -> &'a TeamData {
        match side {
            Side::Home => self.home,
            Side::Away => self.away,
        }
    }

    fn add_goal(&mut self, side: Side) {
        match side {
            Side::Home => self.home_score += 1,
            Side::Away => self.away_score += 1,
        }
    }
}

/// Pick a random player from a side, preferring a given position, and return
/// a snapshot so we don't hold a borrow on the context.
fn snap_player<R: Rng>(
    ctx: &MatchContext,
    side: Side,
    preferred: Position,
    rng: &mut R,
) -> PlayerSnap {
    let team = ctx.team(side);
    let available: Vec<&PlayerData> = team
        .players
        .iter()
        .filter(|p| !ctx.sent_off.contains(&p.id))
        .collect();

    let candidates: Vec<&PlayerData> = available
        .iter()
        .filter(|p| p.position == preferred)
        .copied()
        .collect();

    let pool = if candidates.is_empty() {
        &available
    } else {
        &candidates
    };

    if pool.is_empty() {
        return PlayerSnap::from(&team.players[0]);
    }
    PlayerSnap::from(pool[rng.gen_range(0..pool.len())])
}

// ---------------------------------------------------------------------------
// Minute simulation
// ---------------------------------------------------------------------------

fn simulate_minute<R: Rng>(ctx: &mut MatchContext, minute: u8, rng: &mut R) {
    match ctx.possession {
        Side::Home => ctx.home_possession_ticks += 1,
        Side::Away => ctx.away_possession_ticks += 1,
    }

    let actions = rng.gen_range(1..=3u8);
    for _ in 0..actions {
        resolve_action(ctx, minute, rng);
    }

    // Possession contest via midfield battle
    let poss_side = ctx.possession;
    let def_side = poss_side.opposite();
    let mid_att = effective_midfield(ctx, poss_side);
    let mid_def = effective_midfield(ctx, def_side);
    let retain = mid_att / (mid_att + mid_def);
    if rng.gen_range(0.0..1.0f64) > retain {
        ctx.possession = def_side;
        ctx.ball_zone = Zone::Midfield;
    }
}

// ---------------------------------------------------------------------------
// Action resolution per zone
// ---------------------------------------------------------------------------

fn resolve_action<R: Rng>(ctx: &mut MatchContext, minute: u8, rng: &mut R) {
    let att_side = ctx.possession;
    let def_side = att_side.opposite();
    let zone = ctx.ball_zone;

    if zone.is_box_for(att_side) {
        resolve_shot(ctx, minute, att_side, rng);
        ctx.ball_zone = Zone::Midfield;
        ctx.possession = def_side;
    } else if zone == Zone::attacking_third(att_side) {
        resolve_attacking_third(ctx, minute, att_side, def_side, rng);
    } else if zone == Zone::Midfield {
        resolve_midfield(ctx, minute, att_side, def_side, rng);
    } else {
        resolve_buildup(ctx, minute, att_side, def_side, rng);
    }
}

// ---------------------------------------------------------------------------
// Zone-specific resolution
// ---------------------------------------------------------------------------

fn resolve_buildup<R: Rng>(
    ctx: &mut MatchContext,
    minute: u8,
    att_side: Side,
    def_side: Side,
    rng: &mut R,
) {
    let passer = snap_player(ctx, att_side, Position::Defender, rng);
    let pass_skill = (passer.passing as f64
        + passer.vision as f64
        + passer.composure as f64
        + passer.teamwork as f64)
        / 4.0
        * trait_bonus(&passer, TraitContext::Passing);
    let press = effective_press(ctx, def_side);
    let ball_zone = ctx.ball_zone;

    let success_chance = (pass_skill * 1.3) / (pass_skill * 1.3 + press);
    if rng.gen_range(0.0..1.0f64) < success_chance {
        ctx.emit(
            MatchEvent::new(minute, EventType::PassCompleted, att_side, ball_zone)
                .with_player(&passer.id),
        );
        ctx.ball_zone = Zone::Midfield;
    } else {
        let interceptor = snap_player(ctx, def_side, Position::Midfielder, rng);
        ctx.emit(
            MatchEvent::new(minute, EventType::PassIntercepted, att_side, ball_zone)
                .with_player(&passer.id),
        );
        ctx.emit(
            MatchEvent::new(minute, EventType::Interception, def_side, ball_zone)
                .with_player(&interceptor.id),
        );
        ctx.possession = def_side;
    }
}

fn resolve_midfield<R: Rng>(
    ctx: &mut MatchContext,
    minute: u8,
    att_side: Side,
    def_side: Side,
    rng: &mut R,
) {
    let attacker = snap_player(ctx, att_side, Position::Midfielder, rng);
    let defender = snap_player(ctx, def_side, Position::Midfielder, rng);

    let att_rating = (attacker.dribbling as f64
        + attacker.passing as f64
        + attacker.vision as f64
        + attacker.teamwork as f64)
        / 4.0
        * trait_bonus(&attacker, TraitContext::Midfield);
    let def_rating = (defender.tackling as f64
        + defender.positioning as f64
        + defender.decisions as f64
        + defender.teamwork as f64)
        / 4.0
        * trait_bonus(&defender, TraitContext::Tackling);

    let att_mod = play_style_modifier(
        ctx.team(att_side).play_style,
        PlayStylePhase::Midfield,
        true,
    );
    let def_mod = play_style_modifier(
        ctx.team(def_side).play_style,
        PlayStylePhase::Midfield,
        false,
    );
    let att_eff = att_rating * att_mod * home_mod(att_side, ctx.config);
    let def_eff = def_rating * def_mod * home_mod(def_side, ctx.config);
    let success = att_eff / (att_eff + def_eff);

    if rng.gen_range(0.0..1.0f64) < success {
        ctx.emit(
            MatchEvent::new(minute, EventType::PassCompleted, att_side, Zone::Midfield)
                .with_player(&attacker.id),
        );
        ctx.ball_zone = Zone::attacking_third(att_side);
    } else {
        if rng.gen_range(0.0..1.0f64) < 0.6 {
            ctx.emit(
                MatchEvent::new(minute, EventType::Tackle, def_side, Zone::Midfield)
                    .with_player(&defender.id),
            );
            maybe_foul(
                ctx,
                minute,
                def_side,
                &attacker,
                &defender,
                Zone::Midfield,
                rng,
            );
        } else {
            ctx.emit(
                MatchEvent::new(minute, EventType::Interception, def_side, Zone::Midfield)
                    .with_player(&defender.id),
            );
        }
        ctx.possession = def_side;
        ctx.ball_zone = Zone::Midfield;
    }
}

fn resolve_attacking_third<R: Rng>(
    ctx: &mut MatchContext,
    minute: u8,
    att_side: Side,
    def_side: Side,
    rng: &mut R,
) {
    let attacker = snap_player(ctx, att_side, Position::Forward, rng);
    let defender = snap_player(ctx, def_side, Position::Defender, rng);

    let att_rating = (attacker.dribbling as f64
        + attacker.pace as f64
        + attacker.agility as f64
        + attacker.composure as f64)
        / 4.0
        * trait_bonus(&attacker, TraitContext::Dribbling);
    let def_rating = (defender.defending as f64
        + defender.tackling as f64
        + defender.positioning as f64
        + defender.aerial as f64)
        / 4.0
        * trait_bonus(&defender, TraitContext::Tackling);

    let att_mod = play_style_modifier(ctx.team(att_side).play_style, PlayStylePhase::Attack, true);
    let def_mod = play_style_modifier(
        ctx.team(def_side).play_style,
        PlayStylePhase::Defense,
        false,
    );
    let att_eff = att_rating * att_mod * home_mod(att_side, ctx.config);
    let def_eff = def_rating * def_mod * home_mod(def_side, ctx.config);
    let success = att_eff / (att_eff + def_eff);
    let zone = Zone::attacking_third(att_side);

    if rng.gen_range(0.0..1.0f64) < success {
        ctx.emit(
            MatchEvent::new(minute, EventType::Dribble, att_side, zone).with_player(&attacker.id),
        );
        ctx.ball_zone = Zone::attacking_box(att_side);
    } else {
        let is_tackle = rng.gen_range(0.0..1.0f64) < 0.5;
        if is_tackle {
            ctx.emit(
                MatchEvent::new(minute, EventType::DribbleTackled, att_side, zone)
                    .with_player(&attacker.id)
                    .with_secondary(&defender.id),
            );
            ctx.emit(
                MatchEvent::new(minute, EventType::Tackle, def_side, zone)
                    .with_player(&defender.id),
            );
            maybe_foul(ctx, minute, def_side, &attacker, &defender, zone, rng);
        } else {
            ctx.emit(
                MatchEvent::new(minute, EventType::Clearance, def_side, zone)
                    .with_player(&defender.id),
            );
        }
        if rng.gen_range(0.0..1.0f64) < 0.25 {
            ctx.emit(MatchEvent::new(minute, EventType::Corner, att_side, zone));
            if rng.gen_range(0.0..1.0f64) < 0.30 {
                ctx.ball_zone = Zone::attacking_box(att_side);
                return;
            }
        }
        ctx.possession = def_side;
        ctx.ball_zone = Zone::defensive_third(att_side);
    }
}

fn resolve_shot<R: Rng>(ctx: &mut MatchContext, minute: u8, att_side: Side, rng: &mut R) {
    let def_side = att_side.opposite();
    let shooter = snap_player(ctx, att_side, Position::Forward, rng);
    let assister = snap_player(ctx, att_side, Position::Midfielder, rng);
    let goalkeeper = snap_player(ctx, def_side, Position::Goalkeeper, rng);

    let shoot_rating =
        (shooter.shooting as f64 + shooter.composure as f64 + shooter.decisions as f64) / 3.0
            * trait_bonus(&shooter, TraitContext::Shooting);
    let gk_rating =
        (goalkeeper.handling as f64 + goalkeeper.reflexes as f64 + goalkeeper.positioning as f64)
            / 3.0
            * trait_bonus(&goalkeeper, TraitContext::Goalkeeping);

    let accuracy =
        (ctx.config.shot_accuracy_base + (shoot_rating - 50.0) / 200.0).clamp(0.15, 0.85);
    let zone = Zone::attacking_box(att_side);

    if rng.gen_range(0.0..1.0f64) > accuracy {
        if rng.gen_range(0.0..1.0f64) < 0.4 {
            ctx.emit(
                MatchEvent::new(minute, EventType::ShotBlocked, att_side, zone)
                    .with_player(&shooter.id),
            );
        } else {
            ctx.emit(
                MatchEvent::new(minute, EventType::ShotOffTarget, att_side, zone)
                    .with_player(&shooter.id),
            );
        }
        return;
    }

    let conversion =
        (ctx.config.goal_conversion_base + (shoot_rating - gk_rating) / 150.0).clamp(0.10, 0.70);

    if rng.gen_range(0.0..1.0f64) < conversion {
        ctx.emit(
            MatchEvent::new(minute, EventType::Goal, att_side, zone)
                .with_player(&shooter.id)
                .with_secondary(&assister.id),
        );
        ctx.add_goal(att_side);
    } else {
        ctx.emit(
            MatchEvent::new(minute, EventType::ShotSaved, att_side, zone).with_player(&shooter.id),
        );
    }
}

// ---------------------------------------------------------------------------
// Foul / card / penalty logic
// ---------------------------------------------------------------------------

/// `fouled_snap` is the player who was fouled; `fouler_snap` committed the foul.
/// `fouling_side` is the side that committed the foul.
fn maybe_foul<R: Rng>(
    ctx: &mut MatchContext,
    minute: u8,
    fouling_side: Side,
    fouled_snap: &PlayerSnap,
    fouler_snap: &PlayerSnap,
    zone: Zone,
    rng: &mut R,
) {
    let aggression_mod = fouler_snap.aggression as f64 / 100.0;
    let foul_chance = ctx.config.foul_probability
        * (0.6 + aggression_mod * 0.8)
        * trait_bonus(fouler_snap, TraitContext::Foul);
    if rng.gen_range(0.0..1.0f64) >= foul_chance {
        return;
    }

    ctx.emit(
        MatchEvent::new(minute, EventType::Foul, fouling_side, zone)
            .with_player(&fouler_snap.id)
            .with_secondary(&fouled_snap.id),
    );

    let att_side = fouling_side.opposite();

    if zone.is_box_for(att_side) && rng.gen_range(0.0..1.0f64) < ctx.config.penalty_probability {
        ctx.emit(MatchEvent::new(
            minute,
            EventType::PenaltyAwarded,
            att_side,
            zone,
        ));
        resolve_penalty(ctx, minute, att_side, rng);
    } else {
        ctx.emit(MatchEvent::new(minute, EventType::FreeKick, att_side, zone));
    }

    maybe_card(ctx, minute, fouling_side, &fouler_snap.id, zone, rng);

    if rng.gen_range(0.0..1.0f64) < ctx.config.injury_probability {
        ctx.emit(
            MatchEvent::new(minute, EventType::Injury, att_side, zone).with_player(&fouled_snap.id),
        );
    }
}

fn maybe_card<R: Rng>(
    ctx: &mut MatchContext,
    minute: u8,
    side: Side,
    fouler_id: &str,
    zone: Zone,
    rng: &mut R,
) {
    let aggression_factor = ctx
        .team(side)
        .players
        .iter()
        .find(|p| p.id == fouler_id)
        .map(|p| p.aggression as f64 / 100.0)
        .unwrap_or(0.5);
    let card_chance = ctx.config.yellow_card_probability * (0.5 + aggression_factor);
    if rng.gen_range(0.0..1.0f64) >= card_chance {
        return;
    }

    if rng.gen_range(0.0..1.0f64) < ctx.config.red_card_probability {
        ctx.emit(MatchEvent::new(minute, EventType::RedCard, side, zone).with_player(fouler_id));
        ctx.sent_off.insert(fouler_id.to_string());
        return;
    }

    let current_yellows = ctx.yellows.entry(fouler_id.to_string()).or_insert(0);
    *current_yellows += 1;

    if *current_yellows >= 2 {
        ctx.emit(
            MatchEvent::new(minute, EventType::SecondYellow, side, zone).with_player(fouler_id),
        );
        ctx.sent_off.insert(fouler_id.to_string());
    } else {
        ctx.emit(MatchEvent::new(minute, EventType::YellowCard, side, zone).with_player(fouler_id));
    }
}

fn resolve_penalty<R: Rng>(ctx: &mut MatchContext, minute: u8, att_side: Side, rng: &mut R) {
    let taker = snap_player(ctx, att_side, Position::Forward, rng);
    let gk = snap_player(ctx, att_side.opposite(), Position::Goalkeeper, rng);

    let shoot_skill = (taker.shooting as f64 + taker.decisions as f64) / 2.0;
    let gk_skill = (gk.positioning as f64 + gk.decisions as f64) / 2.0;
    let conversion = (0.75 + (shoot_skill - gk_skill) / 300.0).clamp(0.55, 0.92);
    let zone = Zone::attacking_box(att_side);

    if rng.gen_range(0.0..1.0f64) < conversion {
        ctx.emit(
            MatchEvent::new(minute, EventType::PenaltyGoal, att_side, zone).with_player(&taker.id),
        );
        ctx.add_goal(att_side);
    } else {
        ctx.emit(
            MatchEvent::new(minute, EventType::PenaltyMiss, att_side, zone).with_player(&taker.id),
        );
    }
}

// ---------------------------------------------------------------------------
// Rating helpers
// ---------------------------------------------------------------------------

fn effective_midfield(ctx: &MatchContext, side: Side) -> f64 {
    let base = ctx.team(side).midfield_rating();
    let modifier = play_style_modifier(ctx.team(side).play_style, PlayStylePhase::Midfield, true);
    base * modifier * home_mod(side, ctx.config)
}

fn effective_press(ctx: &MatchContext, pressing_side: Side) -> f64 {
    let team = ctx.team(pressing_side);
    let base = team.position_attr_avg(Position::Midfielder, |p| {
        ((p.stamina as u16 + p.tackling as u16 + p.pace as u16) / 3) as u8
    });
    let modifier = play_style_modifier(team.play_style, PlayStylePhase::Press, true);
    base * modifier * home_mod(pressing_side, ctx.config)
}

fn home_mod(side: Side, config: &MatchConfig) -> f64 {
    match side {
        Side::Home => config.home_advantage,
        Side::Away => 1.0,
    }
}

// ---------------------------------------------------------------------------
// Play-style modifiers
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy)]
enum PlayStylePhase {
    Midfield,
    Attack,
    Defense,
    Press,
}

fn play_style_modifier(style: PlayStyle, phase: PlayStylePhase, is_own_phase: bool) -> f64 {
    if !is_own_phase {
        return 1.0;
    }
    match (style, phase) {
        (PlayStyle::Attacking, PlayStylePhase::Attack) => 1.12,
        (PlayStyle::Attacking, PlayStylePhase::Defense) => 0.93,
        (PlayStyle::Defensive, PlayStylePhase::Defense) => 1.12,
        (PlayStyle::Defensive, PlayStylePhase::Attack) => 0.93,
        (PlayStyle::Possession, PlayStylePhase::Midfield) => 1.15,
        (PlayStyle::Possession, PlayStylePhase::Attack) => 0.97,
        (PlayStyle::Counter, PlayStylePhase::Attack) => 1.18,
        (PlayStyle::Counter, PlayStylePhase::Midfield) => 0.92,
        (PlayStyle::HighPress, PlayStylePhase::Press) => 1.20,
        (PlayStyle::HighPress, PlayStylePhase::Defense) => 0.95,
        _ => 1.0,
    }
}
