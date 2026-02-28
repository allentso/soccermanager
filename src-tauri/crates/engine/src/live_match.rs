use rand::Rng;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

use crate::event::{EventType, MatchEvent};
use crate::report::MatchReport;
use crate::types::{MatchConfig, PlayStyle, PlayerData, Position, Side, TeamData, Zone};

// ---------------------------------------------------------------------------
// MatchPhase — tracks where we are in the match lifecycle
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MatchPhase {
    PreKickOff,
    FirstHalf,
    HalfTime,
    SecondHalf,
    FullTime,
    ExtraTimeFirstHalf,
    ExtraTimeHalfTime,
    ExtraTimeSecondHalf,
    ExtraTimeEnd,
    PenaltyShootout,
    Finished,
}

// ---------------------------------------------------------------------------
// MatchCommand — actions injected by user or AI between minutes
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MatchCommand {
    Substitute {
        side: Side,
        player_off_id: String,
        player_on_id: String,
    },
    ChangeFormation {
        side: Side,
        formation: String,
    },
    ChangePlayStyle {
        side: Side,
        play_style: PlayStyle,
    },
    SetFreeKickTaker {
        side: Side,
        player_id: String,
    },
    SetCornerTaker {
        side: Side,
        player_id: String,
    },
    SetPenaltyTaker {
        side: Side,
        player_id: String,
    },
    SetCaptain {
        side: Side,
        player_id: String,
    },
}

// ---------------------------------------------------------------------------
// SubstitutionRecord — tracks a substitution that was made
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubstitutionRecord {
    pub minute: u8,
    pub side: Side,
    pub player_off_id: String,
    pub player_on_id: String,
}

// ---------------------------------------------------------------------------
// SetPieceTakers — designated set piece takers for a side
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SetPieceTakers {
    pub free_kick_taker: Option<String>,
    pub corner_taker: Option<String>,
    pub penalty_taker: Option<String>,
    pub captain: Option<String>,
}

// ---------------------------------------------------------------------------
// MinuteResult — what happened during one simulated minute
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MinuteResult {
    pub minute: u8,
    pub phase: MatchPhase,
    pub events: Vec<MatchEvent>,
    pub home_score: u8,
    pub away_score: u8,
    pub possession: Side,
    pub ball_zone: Zone,
    pub is_finished: bool,
}

// ---------------------------------------------------------------------------
// MatchSnapshot — full read-only view of the match for the UI
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchSnapshot {
    pub phase: MatchPhase,
    pub current_minute: u8,
    pub home_score: u8,
    pub away_score: u8,
    pub possession: Side,
    pub ball_zone: Zone,
    pub home_team: TeamData,
    pub away_team: TeamData,
    pub home_possession_pct: f64,
    pub away_possession_pct: f64,
    pub events: Vec<MatchEvent>,
    pub home_subs_made: u8,
    pub away_subs_made: u8,
    pub max_subs: u8,
    pub home_set_pieces: SetPieceTakers,
    pub away_set_pieces: SetPieceTakers,
    pub substitutions: Vec<SubstitutionRecord>,
    pub allows_extra_time: bool,
    pub home_yellows: HashMap<String, u8>,
    pub away_yellows: HashMap<String, u8>,
    pub sent_off: HashSet<String>,
}

// ---------------------------------------------------------------------------
// PenaltyShootoutState — tracks penalty shootout progress
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default)]
#[allow(dead_code)]
struct PenaltyShootoutState {
    round: u8,
    home_taken: u8,
    away_taken: u8,
    home_scored: u8,
    away_scored: u8,
    sudden_death: bool,
}

// ---------------------------------------------------------------------------
// LiveMatchState — the core step-by-step simulation engine
// ---------------------------------------------------------------------------

pub struct LiveMatchState {
    // Teams (owned — subs mutate the player list)
    home: TeamData,
    away: TeamData,
    config: MatchConfig,

    // Match progress
    phase: MatchPhase,
    current_minute: u8,

    // Score
    home_score: u8,
    away_score: u8,

    // Field state
    ball_zone: Zone,
    possession: Side,

    // Events log
    events: Vec<MatchEvent>,

    // Possession tracking
    home_possession_ticks: u32,
    away_possession_ticks: u32,

    // Discipline
    yellows: HashMap<String, u8>,
    sent_off: HashSet<String>,

    // Substitutions
    home_subs_made: u8,
    away_subs_made: u8,
    max_subs: u8,
    substitutions: Vec<SubstitutionRecord>,

    // Bench players (available for substitution)
    home_bench: Vec<PlayerData>,
    away_bench: Vec<PlayerData>,

    // Set piece takers
    home_set_pieces: SetPieceTakers,
    away_set_pieces: SetPieceTakers,

    // Extra time / knockout
    allows_extra_time: bool,

    // Stoppage time (pre-computed when each half starts)
    first_half_stoppage: u8,
    second_half_stoppage: u8,
    et_first_half_stoppage: u8,
    et_second_half_stoppage: u8,

    // Per-minute stamina depletion tracking (player_id → current effective condition)
    player_conditions: HashMap<String, f64>,

    // Penalty shootout state
    penalty_state: PenaltyShootoutState,
}

impl LiveMatchState {
    /// Create a new live match. `starting_xi` are already in `home.players` / `away.players`.
    /// Bench players are separate and available for substitution.
    pub fn new(
        home: TeamData,
        away: TeamData,
        config: MatchConfig,
        home_bench: Vec<PlayerData>,
        away_bench: Vec<PlayerData>,
        allows_extra_time: bool,
    ) -> Self {
        // Initialize player conditions from their condition attribute
        let mut player_conditions = HashMap::new();
        for p in home.players.iter().chain(away.players.iter()) {
            player_conditions.insert(p.id.clone(), p.condition as f64);
        }

        Self {
            home,
            away,
            config,
            phase: MatchPhase::PreKickOff,
            current_minute: 0,
            home_score: 0,
            away_score: 0,
            ball_zone: Zone::Midfield,
            possession: Side::Home,
            events: Vec::with_capacity(300),
            home_possession_ticks: 0,
            away_possession_ticks: 0,
            yellows: HashMap::new(),
            sent_off: HashSet::new(),
            home_subs_made: 0,
            away_subs_made: 0,
            max_subs: 5,
            substitutions: Vec::new(),
            home_bench,
            away_bench,
            home_set_pieces: SetPieceTakers::default(),
            away_set_pieces: SetPieceTakers::default(),
            allows_extra_time,
            first_half_stoppage: 0,
            second_half_stoppage: 0,
            et_first_half_stoppage: 0,
            et_second_half_stoppage: 0,
            player_conditions,
            penalty_state: PenaltyShootoutState::default(),
        }
    }

    /// Step one minute forward. Returns the events that occurred.
    pub fn step_minute<R: Rng>(&mut self, rng: &mut R) -> MinuteResult {
        match self.phase {
            MatchPhase::PreKickOff => self.start_match(rng),
            MatchPhase::FirstHalf => self.play_minute(rng),
            MatchPhase::HalfTime => self.start_second_half(rng),
            MatchPhase::SecondHalf => self.play_minute(rng),
            MatchPhase::FullTime => self.handle_full_time(rng),
            MatchPhase::ExtraTimeFirstHalf => self.play_minute(rng),
            MatchPhase::ExtraTimeHalfTime => self.start_et_second_half(rng),
            MatchPhase::ExtraTimeSecondHalf => self.play_minute(rng),
            MatchPhase::ExtraTimeEnd => self.handle_et_end(rng),
            MatchPhase::PenaltyShootout => self.play_penalty_round(rng),
            MatchPhase::Finished => self.make_result(true),
        }
    }

    /// Apply a command (substitution, tactic change, set piece assignment).
    pub fn apply_command(&mut self, cmd: MatchCommand) -> Result<(), String> {
        match cmd {
            MatchCommand::Substitute { side, player_off_id, player_on_id } => {
                self.do_substitution(side, &player_off_id, &player_on_id)
            }
            MatchCommand::ChangeFormation { side, formation } => {
                self.team_mut(side).formation = formation;
                Ok(())
            }
            MatchCommand::ChangePlayStyle { side, play_style } => {
                self.team_mut(side).play_style = play_style;
                Ok(())
            }
            MatchCommand::SetFreeKickTaker { side, player_id } => {
                self.set_pieces_mut(side).free_kick_taker = Some(player_id);
                Ok(())
            }
            MatchCommand::SetCornerTaker { side, player_id } => {
                self.set_pieces_mut(side).corner_taker = Some(player_id);
                Ok(())
            }
            MatchCommand::SetPenaltyTaker { side, player_id } => {
                self.set_pieces_mut(side).penalty_taker = Some(player_id);
                Ok(())
            }
            MatchCommand::SetCaptain { side, player_id } => {
                self.set_pieces_mut(side).captain = Some(player_id);
                Ok(())
            }
        }
    }

    /// Get a full snapshot of the current match state for the UI.
    pub fn snapshot(&self) -> MatchSnapshot {
        let total_poss = self.home_possession_ticks + self.away_possession_ticks;
        let home_pct = if total_poss > 0 {
            self.home_possession_ticks as f64 / total_poss as f64 * 100.0
        } else {
            50.0
        };

        // Separate yellows by side
        let mut home_yellows = HashMap::new();
        let mut away_yellows = HashMap::new();
        for (pid, count) in &self.yellows {
            if self.home.players.iter().any(|p| p.id == *pid) {
                home_yellows.insert(pid.clone(), *count);
            } else {
                away_yellows.insert(pid.clone(), *count);
            }
        }

        MatchSnapshot {
            phase: self.phase,
            current_minute: self.current_minute,
            home_score: self.home_score,
            away_score: self.away_score,
            possession: self.possession,
            ball_zone: self.ball_zone,
            home_team: self.home.clone(),
            away_team: self.away.clone(),
            home_possession_pct: home_pct,
            away_possession_pct: 100.0 - home_pct,
            events: self.events.clone(),
            home_subs_made: self.home_subs_made,
            away_subs_made: self.away_subs_made,
            max_subs: self.max_subs,
            home_set_pieces: self.home_set_pieces.clone(),
            away_set_pieces: self.away_set_pieces.clone(),
            substitutions: self.substitutions.clone(),
            allows_extra_time: self.allows_extra_time,
            home_yellows,
            away_yellows,
            sent_off: self.sent_off.clone(),
        }
    }

    /// Convert the finished match into a MatchReport.
    pub fn into_report(self) -> MatchReport {
        MatchReport::from_events(
            self.events,
            self.home_possession_ticks,
            self.away_possession_ticks,
            self.current_minute,
        )
    }

    /// Is the match finished?
    pub fn is_finished(&self) -> bool {
        self.phase == MatchPhase::Finished
    }

    /// Current phase
    pub fn phase(&self) -> MatchPhase {
        self.phase
    }

    /// Current minute
    pub fn minute(&self) -> u8 {
        self.current_minute
    }

    /// Get the bench for a side
    pub fn bench(&self, side: Side) -> &[PlayerData] {
        match side {
            Side::Home => &self.home_bench,
            Side::Away => &self.away_bench,
        }
    }

    // -----------------------------------------------------------------------
    // Phase transitions
    // -----------------------------------------------------------------------

    fn start_match<R: Rng>(&mut self, rng: &mut R) -> MinuteResult {
        self.phase = MatchPhase::FirstHalf;
        self.current_minute = 0;
        self.ball_zone = Zone::Midfield;
        self.possession = Side::Home;
        self.first_half_stoppage = rng.gen_range(0..=self.config.stoppage_time_max);

        let evt = MatchEvent::new(0, EventType::KickOff, Side::Home, Zone::Midfield);
        self.events.push(evt.clone());

        MinuteResult {
            minute: 0,
            phase: MatchPhase::FirstHalf,
            events: vec![evt],
            home_score: 0,
            away_score: 0,
            possession: Side::Home,
            ball_zone: Zone::Midfield,
            is_finished: false,
        }
    }

    fn start_second_half<R: Rng>(&mut self, rng: &mut R) -> MinuteResult {
        self.phase = MatchPhase::SecondHalf;
        // Second half starts after halftime; use at least minute 46 but never before current_minute
        let start_min = self.current_minute.max(46);
        self.current_minute = start_min;
        self.ball_zone = Zone::Midfield;
        self.possession = Side::Away;
        self.second_half_stoppage = rng.gen_range(0..=self.config.stoppage_time_max);

        let evt = MatchEvent::new(start_min, EventType::SecondHalfStart, Side::Away, Zone::Midfield);
        self.events.push(evt.clone());

        MinuteResult {
            minute: start_min,
            phase: MatchPhase::SecondHalf,
            events: vec![evt],
            home_score: self.home_score,
            away_score: self.away_score,
            possession: Side::Away,
            ball_zone: Zone::Midfield,
            is_finished: false,
        }
    }

    fn start_et_second_half<R: Rng>(&mut self, rng: &mut R) -> MinuteResult {
        self.phase = MatchPhase::ExtraTimeSecondHalf;
        let start_min = self.current_minute.max(106);
        self.current_minute = start_min;
        self.ball_zone = Zone::Midfield;
        self.possession = Side::Home;
        self.et_second_half_stoppage = rng.gen_range(0..=2); // short stoppage in ET

        let evt = MatchEvent::new(start_min, EventType::SecondHalfStart, Side::Home, Zone::Midfield);
        self.events.push(evt.clone());

        MinuteResult {
            minute: start_min,
            phase: MatchPhase::ExtraTimeSecondHalf,
            events: vec![evt],
            home_score: self.home_score,
            away_score: self.away_score,
            possession: Side::Home,
            ball_zone: Zone::Midfield,
            is_finished: false,
        }
    }

    fn handle_full_time<R: Rng>(&mut self, rng: &mut R) -> MinuteResult {
        if self.allows_extra_time && self.home_score == self.away_score {
            // Go to extra time
            self.phase = MatchPhase::ExtraTimeFirstHalf;
            self.current_minute = 91;
            self.ball_zone = Zone::Midfield;
            self.possession = Side::Home;
            self.et_first_half_stoppage = rng.gen_range(0..=2);

            let evt = MatchEvent::new(91, EventType::KickOff, Side::Home, Zone::Midfield);
            self.events.push(evt.clone());

            MinuteResult {
                minute: 91,
                phase: MatchPhase::ExtraTimeFirstHalf,
                events: vec![evt],
                home_score: self.home_score,
                away_score: self.away_score,
                possession: Side::Home,
                ball_zone: Zone::Midfield,
                is_finished: false,
            }
        } else {
            // Match decided in normal time
            self.phase = MatchPhase::Finished;
            self.make_result(true)
        }
    }

    fn handle_et_end<R: Rng>(&mut self, _rng: &mut R) -> MinuteResult {
        if self.home_score == self.away_score {
            // Go to penalty shootout
            self.phase = MatchPhase::PenaltyShootout;
            self.penalty_state = PenaltyShootoutState::default();

            let evt = MatchEvent::new(
                self.current_minute,
                EventType::PenaltyAwarded,
                Side::Home,
                Zone::Midfield,
            );
            self.events.push(evt.clone());

            MinuteResult {
                minute: self.current_minute,
                phase: MatchPhase::PenaltyShootout,
                events: vec![evt],
                home_score: self.home_score,
                away_score: self.away_score,
                possession: self.possession,
                ball_zone: Zone::Midfield,
                is_finished: false,
            }
        } else {
            self.phase = MatchPhase::Finished;
            self.make_result(true)
        }
    }

    // -----------------------------------------------------------------------
    // Core minute simulation
    // -----------------------------------------------------------------------

    fn play_minute<R: Rng>(&mut self, rng: &mut R) -> MinuteResult {
        self.current_minute += 1;
        let minute = self.current_minute;

        // Track possession
        match self.possession {
            Side::Home => self.home_possession_ticks += 1,
            Side::Away => self.away_possession_ticks += 1,
        }

        // Deplete stamina for all on-pitch players
        self.deplete_stamina_tick();

        // Simulate 1-3 actions per minute
        let mut minute_events = Vec::new();
        let actions = rng.gen_range(1..=3u8);
        for _ in 0..actions {
            let new_events = self.resolve_action(minute, rng);
            minute_events.extend(new_events);
        }

        // Possession contest
        let poss_side = self.possession;
        let def_side = poss_side.opposite();
        let mid_att = self.effective_midfield(poss_side);
        let mid_def = self.effective_midfield(def_side);
        let retain = mid_att / (mid_att + mid_def);
        if rng.gen_range(0.0..1.0f64) > retain {
            self.possession = def_side;
            self.ball_zone = Zone::Midfield;
        }

        // Check for phase transitions
        let transition_events = self.check_phase_end(minute, rng);
        minute_events.extend(transition_events);

        MinuteResult {
            minute,
            phase: self.phase,
            events: minute_events,
            home_score: self.home_score,
            away_score: self.away_score,
            possession: self.possession,
            ball_zone: self.ball_zone,
            is_finished: self.phase == MatchPhase::Finished,
        }
    }

    fn check_phase_end<R: Rng>(&mut self, minute: u8, _rng: &mut R) -> Vec<MatchEvent> {
        let mut events = Vec::new();
        match self.phase {
            MatchPhase::FirstHalf => {
                if minute >= 45 + self.first_half_stoppage {
                    self.phase = MatchPhase::HalfTime;
                    let evt = MatchEvent::new(minute, EventType::HalfTime, Side::Home, Zone::Midfield);
                    self.events.push(evt.clone());
                    events.push(evt);
                }
            }
            MatchPhase::SecondHalf => {
                if minute >= 90 + self.second_half_stoppage {
                    self.phase = MatchPhase::FullTime;
                    let evt = MatchEvent::new(minute, EventType::FullTime, Side::Home, Zone::Midfield);
                    self.events.push(evt.clone());
                    events.push(evt);
                }
            }
            MatchPhase::ExtraTimeFirstHalf => {
                if minute >= 105 + self.et_first_half_stoppage {
                    self.phase = MatchPhase::ExtraTimeHalfTime;
                    let evt = MatchEvent::new(minute, EventType::HalfTime, Side::Home, Zone::Midfield);
                    self.events.push(evt.clone());
                    events.push(evt);
                }
            }
            MatchPhase::ExtraTimeSecondHalf => {
                if minute >= 120 + self.et_second_half_stoppage {
                    self.phase = MatchPhase::ExtraTimeEnd;
                    let evt = MatchEvent::new(minute, EventType::FullTime, Side::Home, Zone::Midfield);
                    self.events.push(evt.clone());
                    events.push(evt);
                }
            }
            _ => {}
        }
        events
    }

    // -----------------------------------------------------------------------
    // Penalty shootout
    // -----------------------------------------------------------------------

    fn play_penalty_round<R: Rng>(&mut self, rng: &mut R) -> MinuteResult {
        let minute = self.current_minute;
        let mut events = Vec::new();

        // Determine which side kicks next (read-only access to penalty_state)
        let kicking_side = if self.penalty_state.home_taken <= self.penalty_state.away_taken {
            Side::Home
        } else {
            Side::Away
        };

        // Pick taker and goalkeeper (needs &self)
        let taker = self.pick_penalty_taker(kicking_side, rng);
        let gk = self.pick_goalkeeper(kicking_side.opposite());

        let shoot_skill = (taker.shooting as f64 + taker.decisions as f64) / 2.0;
        let gk_skill = (gk.positioning as f64 + gk.decisions as f64) / 2.0;

        // Fatigue affects penalty accuracy in shootout
        let taker_condition = self.player_conditions.get(&taker.id).copied().unwrap_or(50.0);
        let fatigue_factor = (taker_condition / 100.0).clamp(0.7, 1.0);

        let conversion = (0.75 + (shoot_skill - gk_skill) / 300.0) * fatigue_factor;
        let conversion = conversion.clamp(0.55, 0.92);

        let zone = Zone::attacking_box(kicking_side);

        // Now mutate penalty_state
        let scored = rng.gen_range(0.0..1.0f64) < conversion;
        if scored {
            let evt = MatchEvent::new(minute, EventType::PenaltyGoal, kicking_side, zone)
                .with_player(&taker.id);
            self.events.push(evt.clone());
            events.push(evt);
            match kicking_side {
                Side::Home => self.penalty_state.home_scored += 1,
                Side::Away => self.penalty_state.away_scored += 1,
            }
        } else {
            let evt = MatchEvent::new(minute, EventType::PenaltyMiss, kicking_side, zone)
                .with_player(&taker.id);
            self.events.push(evt.clone());
            events.push(evt);
        }

        match kicking_side {
            Side::Home => self.penalty_state.home_taken += 1,
            Side::Away => self.penalty_state.away_taken += 1,
        }

        // Check if shootout is decided
        let decided = self.check_penalty_decided();
        if decided {
            // Add penalty goals to score
            self.home_score += self.penalty_state.home_scored;
            self.away_score += self.penalty_state.away_scored;
            self.phase = MatchPhase::Finished;

            let evt = MatchEvent::new(minute, EventType::FullTime, Side::Home, Zone::Midfield);
            self.events.push(evt.clone());
            events.push(evt);
        }

        MinuteResult {
            minute,
            phase: self.phase,
            events,
            home_score: self.home_score,
            away_score: self.away_score,
            possession: kicking_side,
            ball_zone: Zone::Midfield,
            is_finished: self.phase == MatchPhase::Finished,
        }
    }

    fn check_penalty_decided(&self) -> bool {
        let ps = &self.penalty_state;

        if !ps.sudden_death {
            // Normal rounds (5 each)
            let home_remaining = 5u8.saturating_sub(ps.home_taken);
            let away_remaining = 5u8.saturating_sub(ps.away_taken);

            // Home can't catch up even if they score all remaining
            if ps.home_scored + home_remaining < ps.away_scored && ps.home_taken == ps.away_taken {
                return true;
            }
            if ps.away_scored + away_remaining < ps.home_scored && ps.away_taken == ps.home_taken {
                return true;
            }

            // After 5 rounds each
            if ps.home_taken >= 5 && ps.away_taken >= 5 {
                if ps.home_scored != ps.away_scored {
                    return true;
                }
                // If equal after 5 rounds, we enter sudden death on next step
                // (handled by setting sudden_death flag)
            }

            false
        } else {
            // Sudden death: after each pair, check if one side leads
            ps.home_taken == ps.away_taken && ps.home_scored != ps.away_scored
        }
    }

    // -----------------------------------------------------------------------
    // Substitution mechanics
    // -----------------------------------------------------------------------

    fn do_substitution(
        &mut self,
        side: Side,
        player_off_id: &str,
        player_on_id: &str,
    ) -> Result<(), String> {
        let subs_made = match side {
            Side::Home => &mut self.home_subs_made,
            Side::Away => &mut self.away_subs_made,
        };

        if *subs_made >= self.max_subs {
            return Err("Maximum substitutions reached".into());
        }

        let team = self.team_mut(side);
        let off_idx = team
            .players
            .iter()
            .position(|p| p.id == player_off_id)
            .ok_or("Player not on pitch")?;

        let bench = match side {
            Side::Home => &mut self.home_bench,
            Side::Away => &mut self.away_bench,
        };
        let on_idx = bench
            .iter()
            .position(|p| p.id == player_on_id)
            .ok_or("Player not on bench")?;

        let player_on = bench.remove(on_idx);
        let player_off = self.team_mut(side).players.remove(off_idx);

        // Initialize condition for incoming player
        self.player_conditions
            .insert(player_on.id.clone(), player_on.condition as f64);

        self.team_mut(side).players.push(player_on);

        // Move subbed-off player to bench (they can't come back, but we keep them)
        match side {
            Side::Home => self.home_bench.push(player_off),
            Side::Away => self.away_bench.push(player_off),
        }

        *match side {
            Side::Home => &mut self.home_subs_made,
            Side::Away => &mut self.away_subs_made,
        } += 1;

        // Record the substitution
        let evt = MatchEvent::new(
            self.current_minute,
            EventType::Substitution,
            side,
            Zone::Midfield,
        )
        .with_player(player_on_id)
        .with_secondary(player_off_id);
        self.events.push(evt);

        self.substitutions.push(SubstitutionRecord {
            minute: self.current_minute,
            side,
            player_off_id: player_off_id.to_string(),
            player_on_id: player_on_id.to_string(),
        });

        Ok(())
    }

    // -----------------------------------------------------------------------
    // Action resolution (reusing patterns from engine.rs)
    // -----------------------------------------------------------------------

    fn resolve_action<R: Rng>(&mut self, minute: u8, rng: &mut R) -> Vec<MatchEvent> {
        let att_side = self.possession;
        let def_side = att_side.opposite();
        let zone = self.ball_zone;

        if zone.is_box_for(att_side) {
            self.resolve_shot(minute, att_side, rng)
        } else if zone == Zone::attacking_third(att_side) {
            self.resolve_attacking_third(minute, att_side, def_side, rng)
        } else if zone == Zone::Midfield {
            self.resolve_midfield(minute, att_side, def_side, rng)
        } else {
            self.resolve_buildup(minute, att_side, def_side, rng)
        }
    }

    fn resolve_buildup<R: Rng>(
        &mut self,
        minute: u8,
        att_side: Side,
        def_side: Side,
        rng: &mut R,
    ) -> Vec<MatchEvent> {
        let mut events = Vec::new();
        let passer = self.snap_player(att_side, Position::Defender, rng);
        let pass_skill = self.condition_adjusted_skill(
            &passer.id,
            (passer.passing as f64 + passer.vision as f64 + passer.decisions as f64) / 3.0,
        );
        let press = self.effective_press(def_side);
        let ball_zone = self.ball_zone;

        let success_chance = (pass_skill * 1.3) / (pass_skill * 1.3 + press);
        if rng.gen_range(0.0..1.0f64) < success_chance {
            let evt = MatchEvent::new(minute, EventType::PassCompleted, att_side, ball_zone)
                .with_player(&passer.id);
            self.events.push(evt.clone());
            events.push(evt);
            self.ball_zone = Zone::Midfield;
        } else {
            let interceptor = self.snap_player(def_side, Position::Midfielder, rng);
            let evt1 = MatchEvent::new(minute, EventType::PassIntercepted, att_side, ball_zone)
                .with_player(&passer.id);
            let evt2 = MatchEvent::new(minute, EventType::Interception, def_side, ball_zone)
                .with_player(&interceptor.id);
            self.events.push(evt1.clone());
            self.events.push(evt2.clone());
            events.push(evt1);
            events.push(evt2);
            self.possession = def_side;
        }
        events
    }

    fn resolve_midfield<R: Rng>(
        &mut self,
        minute: u8,
        att_side: Side,
        def_side: Side,
        rng: &mut R,
    ) -> Vec<MatchEvent> {
        let mut events = Vec::new();
        let attacker = self.snap_player(att_side, Position::Midfielder, rng);
        let defender = self.snap_player(def_side, Position::Midfielder, rng);

        let att_raw = (attacker.dribbling as f64 + attacker.passing as f64 + attacker.vision as f64) / 3.0;
        let def_raw = (defender.tackling as f64 + defender.positioning as f64 + defender.decisions as f64) / 3.0;
        let att_rating = self.condition_adjusted_skill(&attacker.id, att_raw);
        let def_rating = self.condition_adjusted_skill(&defender.id, def_raw);

        let att_mod = play_style_modifier(self.team_ref(att_side).play_style, PlayStylePhase::Midfield, true);
        let def_mod = play_style_modifier(self.team_ref(def_side).play_style, PlayStylePhase::Midfield, false);
        let att_eff = att_rating * att_mod * home_mod(att_side, &self.config);
        let def_eff = def_rating * def_mod * home_mod(def_side, &self.config);
        let success = att_eff / (att_eff + def_eff);

        if rng.gen_range(0.0..1.0f64) < success {
            let evt = MatchEvent::new(minute, EventType::PassCompleted, att_side, Zone::Midfield)
                .with_player(&attacker.id);
            self.events.push(evt.clone());
            events.push(evt);
            self.ball_zone = Zone::attacking_third(att_side);
        } else {
            if rng.gen_range(0.0..1.0f64) < 0.6 {
                let evt = MatchEvent::new(minute, EventType::Tackle, def_side, Zone::Midfield)
                    .with_player(&defender.id);
                self.events.push(evt.clone());
                events.push(evt);
                let foul_events = self.maybe_foul(minute, def_side, &attacker, &defender, Zone::Midfield, rng);
                events.extend(foul_events);
            } else {
                let evt = MatchEvent::new(minute, EventType::Interception, def_side, Zone::Midfield)
                    .with_player(&defender.id);
                self.events.push(evt.clone());
                events.push(evt);
            }
            self.possession = def_side;
            self.ball_zone = Zone::Midfield;
        }
        events
    }

    fn resolve_attacking_third<R: Rng>(
        &mut self,
        minute: u8,
        att_side: Side,
        def_side: Side,
        rng: &mut R,
    ) -> Vec<MatchEvent> {
        let mut events = Vec::new();
        let attacker = self.snap_player(att_side, Position::Forward, rng);
        let defender = self.snap_player(def_side, Position::Defender, rng);

        let att_raw = (attacker.dribbling as f64 + attacker.pace as f64 + attacker.positioning as f64) / 3.0;
        let def_raw = (defender.defending as f64 + defender.tackling as f64 + defender.pace as f64) / 3.0;
        let att_rating = self.condition_adjusted_skill(&attacker.id, att_raw);
        let def_rating = self.condition_adjusted_skill(&defender.id, def_raw);

        let att_mod = play_style_modifier(self.team_ref(att_side).play_style, PlayStylePhase::Attack, true);
        let def_mod = play_style_modifier(self.team_ref(def_side).play_style, PlayStylePhase::Defense, false);
        let att_eff = att_rating * att_mod * home_mod(att_side, &self.config);
        let def_eff = def_rating * def_mod * home_mod(def_side, &self.config);
        let success = att_eff / (att_eff + def_eff);
        let zone = Zone::attacking_third(att_side);

        if rng.gen_range(0.0..1.0f64) < success {
            let evt = MatchEvent::new(minute, EventType::Dribble, att_side, zone)
                .with_player(&attacker.id);
            self.events.push(evt.clone());
            events.push(evt);
            self.ball_zone = Zone::attacking_box(att_side);
        } else {
            let is_tackle = rng.gen_range(0.0..1.0f64) < 0.5;
            if is_tackle {
                let evt1 = MatchEvent::new(minute, EventType::DribbleTackled, att_side, zone)
                    .with_player(&attacker.id)
                    .with_secondary(&defender.id);
                let evt2 = MatchEvent::new(minute, EventType::Tackle, def_side, zone)
                    .with_player(&defender.id);
                self.events.push(evt1.clone());
                self.events.push(evt2.clone());
                events.push(evt1);
                events.push(evt2);
                let foul_events = self.maybe_foul(minute, def_side, &attacker, &defender, zone, rng);
                events.extend(foul_events);
            } else {
                let evt = MatchEvent::new(minute, EventType::Clearance, def_side, zone)
                    .with_player(&defender.id);
                self.events.push(evt.clone());
                events.push(evt);
            }
            if rng.gen_range(0.0..1.0f64) < 0.25 {
                let evt = MatchEvent::new(minute, EventType::Corner, att_side, zone);
                self.events.push(evt.clone());
                events.push(evt);
                if rng.gen_range(0.0..1.0f64) < 0.30 {
                    self.ball_zone = Zone::attacking_box(att_side);
                    return events;
                }
            }
            self.possession = def_side;
            self.ball_zone = Zone::defensive_third(att_side);
        }
        events
    }

    fn resolve_shot<R: Rng>(
        &mut self,
        minute: u8,
        att_side: Side,
        rng: &mut R,
    ) -> Vec<MatchEvent> {
        let mut events = Vec::new();
        let def_side = att_side.opposite();
        let shooter = self.snap_player(att_side, Position::Forward, rng);
        let assister = self.snap_player(att_side, Position::Midfielder, rng);
        let goalkeeper = self.snap_player(def_side, Position::Goalkeeper, rng);

        let shoot_raw = (shooter.shooting as f64 + shooter.positioning as f64 + shooter.decisions as f64) / 3.0;
        let shoot_rating = self.condition_adjusted_skill(&shooter.id, shoot_raw);
        let gk_raw = (goalkeeper.positioning as f64 + goalkeeper.decisions as f64 + goalkeeper.pace as f64) / 3.0;
        let gk_rating = self.condition_adjusted_skill(&goalkeeper.id, gk_raw);

        let accuracy = (self.config.shot_accuracy_base + (shoot_rating - 50.0) / 200.0).clamp(0.15, 0.85);
        let zone = Zone::attacking_box(att_side);

        if rng.gen_range(0.0..1.0f64) > accuracy {
            if rng.gen_range(0.0..1.0f64) < 0.4 {
                let evt = MatchEvent::new(minute, EventType::ShotBlocked, att_side, zone)
                    .with_player(&shooter.id);
                self.events.push(evt.clone());
                events.push(evt);
            } else {
                let evt = MatchEvent::new(minute, EventType::ShotOffTarget, att_side, zone)
                    .with_player(&shooter.id);
                self.events.push(evt.clone());
                events.push(evt);
            }
            self.ball_zone = Zone::Midfield;
            self.possession = def_side;
            return events;
        }

        let conversion = (self.config.goal_conversion_base + (shoot_rating - gk_rating) / 150.0).clamp(0.10, 0.70);

        if rng.gen_range(0.0..1.0f64) < conversion {
            let evt = MatchEvent::new(minute, EventType::Goal, att_side, zone)
                .with_player(&shooter.id)
                .with_secondary(&assister.id);
            self.events.push(evt.clone());
            events.push(evt);
            self.add_goal(att_side);
        } else {
            let evt = MatchEvent::new(minute, EventType::ShotSaved, att_side, zone)
                .with_player(&shooter.id);
            self.events.push(evt.clone());
            events.push(evt);
        }

        self.ball_zone = Zone::Midfield;
        self.possession = def_side;
        events
    }

    // -----------------------------------------------------------------------
    // Foul / card / penalty
    // -----------------------------------------------------------------------

    fn maybe_foul<R: Rng>(
        &mut self,
        minute: u8,
        fouling_side: Side,
        fouled: &PlayerSnap,
        fouler: &PlayerSnap,
        zone: Zone,
        rng: &mut R,
    ) -> Vec<MatchEvent> {
        let mut events = Vec::new();

        if rng.gen_range(0.0..1.0f64) >= self.config.foul_probability {
            return events;
        }

        let evt = MatchEvent::new(minute, EventType::Foul, fouling_side, zone)
            .with_player(&fouler.id)
            .with_secondary(&fouled.id);
        self.events.push(evt.clone());
        events.push(evt);

        let att_side = fouling_side.opposite();

        if zone.is_box_for(att_side) && rng.gen_range(0.0..1.0f64) < self.config.penalty_probability {
            let evt = MatchEvent::new(minute, EventType::PenaltyAwarded, att_side, zone);
            self.events.push(evt.clone());
            events.push(evt);
            let pen_events = self.resolve_in_match_penalty(minute, att_side, rng);
            events.extend(pen_events);
        } else {
            let evt = MatchEvent::new(minute, EventType::FreeKick, att_side, zone);
            self.events.push(evt.clone());
            events.push(evt);
        }

        let card_events = self.maybe_card(minute, fouling_side, &fouler.id, zone, rng);
        events.extend(card_events);

        if rng.gen_range(0.0..1.0f64) < self.config.injury_probability {
            let evt = MatchEvent::new(minute, EventType::Injury, att_side, zone)
                .with_player(&fouled.id);
            self.events.push(evt.clone());
            events.push(evt);
        }

        events
    }

    fn maybe_card<R: Rng>(
        &mut self,
        minute: u8,
        side: Side,
        fouler_id: &str,
        zone: Zone,
        rng: &mut R,
    ) -> Vec<MatchEvent> {
        let mut events = Vec::new();

        if rng.gen_range(0.0..1.0f64) >= self.config.yellow_card_probability {
            return events;
        }

        if rng.gen_range(0.0..1.0f64) < self.config.red_card_probability {
            let evt = MatchEvent::new(minute, EventType::RedCard, side, zone)
                .with_player(fouler_id);
            self.events.push(evt.clone());
            events.push(evt);
            self.sent_off.insert(fouler_id.to_string());
            return events;
        }

        let current_yellows = self.yellows.entry(fouler_id.to_string()).or_insert(0);
        *current_yellows += 1;

        if *current_yellows >= 2 {
            let evt = MatchEvent::new(minute, EventType::SecondYellow, side, zone)
                .with_player(fouler_id);
            self.events.push(evt.clone());
            events.push(evt);
            self.sent_off.insert(fouler_id.to_string());
        } else {
            let evt = MatchEvent::new(minute, EventType::YellowCard, side, zone)
                .with_player(fouler_id);
            self.events.push(evt.clone());
            events.push(evt);
        }

        events
    }

    fn resolve_in_match_penalty<R: Rng>(
        &mut self,
        minute: u8,
        att_side: Side,
        rng: &mut R,
    ) -> Vec<MatchEvent> {
        let mut events = Vec::new();

        // Use designated penalty taker if set
        let taker = match self.set_pieces_ref(att_side).penalty_taker.clone() {
            Some(id) => self.snap_player_by_id(&id, att_side),
            None => self.snap_player(att_side, Position::Forward, rng),
        };
        let gk = self.snap_player(att_side.opposite(), Position::Goalkeeper, rng);

        let shoot_skill = (taker.shooting as f64 + taker.decisions as f64) / 2.0;
        let gk_skill = (gk.positioning as f64 + gk.decisions as f64) / 2.0;
        let conversion = (0.75 + (shoot_skill - gk_skill) / 300.0).clamp(0.55, 0.92);
        let zone = Zone::attacking_box(att_side);

        if rng.gen_range(0.0..1.0f64) < conversion {
            let evt = MatchEvent::new(minute, EventType::PenaltyGoal, att_side, zone)
                .with_player(&taker.id);
            self.events.push(evt.clone());
            events.push(evt);
            self.add_goal(att_side);
        } else {
            let evt = MatchEvent::new(minute, EventType::PenaltyMiss, att_side, zone)
                .with_player(&taker.id);
            self.events.push(evt.clone());
            events.push(evt);
        }

        events
    }

    // -----------------------------------------------------------------------
    // Stamina system
    // -----------------------------------------------------------------------

    fn deplete_stamina_tick(&mut self) {
        let fatigue_rate = self.config.fatigue_per_minute;
        // Iterate over all on-pitch players
        for p in self.home.players.iter().chain(self.away.players.iter()) {
            if self.sent_off.contains(&p.id) {
                continue;
            }
            let stamina_factor = p.stamina as f64 / 100.0;
            // Higher stamina → less depletion per minute
            let depletion = fatigue_rate * (1.0 - stamina_factor * 0.6);
            if let Some(cond) = self.player_conditions.get_mut(&p.id) {
                *cond = (*cond - depletion).max(5.0);
            }
        }
    }

    /// Adjust a skill value based on the player's current in-match condition.
    fn condition_adjusted_skill(&self, player_id: &str, base_skill: f64) -> f64 {
        let condition = self.player_conditions.get(player_id).copied().unwrap_or(50.0);
        // At 100% condition: full skill. At 50%: ~80% skill. At 0%: ~60% skill.
        let factor = 0.6 + 0.4 * (condition / 100.0);
        base_skill * factor
    }

    // -----------------------------------------------------------------------
    // Player selection helpers
    // -----------------------------------------------------------------------

    fn snap_player<R: Rng>(&self, side: Side, preferred: Position, rng: &mut R) -> PlayerSnap {
        let team = self.team_ref(side);
        let available: Vec<&PlayerData> = team
            .players
            .iter()
            .filter(|p| !self.sent_off.contains(&p.id))
            .collect();

        let candidates: Vec<&PlayerData> = available
            .iter()
            .filter(|p| p.position == preferred)
            .copied()
            .collect();

        let pool = if candidates.is_empty() { &available } else { &candidates };
        if pool.is_empty() {
            return PlayerSnap::from(&team.players[0]);
        }
        PlayerSnap::from(pool[rng.gen_range(0..pool.len())])
    }

    fn snap_player_by_id(&self, player_id: &str, side: Side) -> PlayerSnap {
        let team = self.team_ref(side);
        if let Some(p) = team.players.iter().find(|p| p.id == player_id) {
            PlayerSnap::from(p)
        } else {
            PlayerSnap::from(&team.players[0])
        }
    }

    fn pick_penalty_taker<R: Rng>(&self, side: Side, rng: &mut R) -> PlayerSnap {
        // Use designated taker if set
        if let Some(ref id) = self.set_pieces_ref(side).penalty_taker {
            let team = self.team_ref(side);
            if let Some(p) = team.players.iter().find(|p| p.id == *id && !self.sent_off.contains(&p.id)) {
                return PlayerSnap::from(p);
            }
        }
        // Fallback: pick the forward with highest shooting
        let team = self.team_ref(side);
        let mut candidates: Vec<&PlayerData> = team
            .players
            .iter()
            .filter(|p| !self.sent_off.contains(&p.id))
            .collect();
        candidates.sort_by(|a, b| b.shooting.cmp(&a.shooting));
        if let Some(p) = candidates.first() {
            PlayerSnap::from(*p)
        } else {
            self.snap_player(side, Position::Forward, rng)
        }
    }

    fn pick_goalkeeper(&self, side: Side) -> PlayerSnap {
        let team = self.team_ref(side);
        for p in &team.players {
            if p.position == Position::Goalkeeper && !self.sent_off.contains(&p.id) {
                return PlayerSnap::from(p);
            }
        }
        // No goalkeeper available — pick first available
        for p in &team.players {
            if !self.sent_off.contains(&p.id) {
                return PlayerSnap::from(p);
            }
        }
        PlayerSnap::from(&team.players[0])
    }

    // -----------------------------------------------------------------------
    // Rating helpers
    // -----------------------------------------------------------------------

    fn effective_midfield(&self, side: Side) -> f64 {
        let base = self.team_ref(side).midfield_rating();
        let modifier = play_style_modifier(
            self.team_ref(side).play_style,
            PlayStylePhase::Midfield,
            true,
        );
        base * modifier * home_mod(side, &self.config)
    }

    fn effective_press(&self, pressing_side: Side) -> f64 {
        let team = self.team_ref(pressing_side);
        let base = team.position_attr_avg(Position::Midfielder, |p| {
            ((p.stamina as u16 + p.tackling as u16 + p.pace as u16) / 3) as u8
        });
        let modifier = play_style_modifier(team.play_style, PlayStylePhase::Press, true);
        base * modifier * home_mod(pressing_side, &self.config)
    }

    // -----------------------------------------------------------------------
    // Internal accessors
    // -----------------------------------------------------------------------

    fn team_ref(&self, side: Side) -> &TeamData {
        match side {
            Side::Home => &self.home,
            Side::Away => &self.away,
        }
    }

    fn team_mut(&mut self, side: Side) -> &mut TeamData {
        match side {
            Side::Home => &mut self.home,
            Side::Away => &mut self.away,
        }
    }

    fn set_pieces_ref(&self, side: Side) -> &SetPieceTakers {
        match side {
            Side::Home => &self.home_set_pieces,
            Side::Away => &self.away_set_pieces,
        }
    }

    fn set_pieces_mut(&mut self, side: Side) -> &mut SetPieceTakers {
        match side {
            Side::Home => &mut self.home_set_pieces,
            Side::Away => &mut self.away_set_pieces,
        }
    }

    fn add_goal(&mut self, side: Side) {
        match side {
            Side::Home => self.home_score += 1,
            Side::Away => self.away_score += 1,
        }
    }

    fn make_result(&self, _is_finished: bool) -> MinuteResult {
        MinuteResult {
            minute: self.current_minute,
            phase: self.phase,
            events: Vec::new(),
            home_score: self.home_score,
            away_score: self.away_score,
            possession: self.possession,
            ball_zone: self.ball_zone,
            is_finished: true,
        }
    }
}

// ---------------------------------------------------------------------------
// PlayerSnap (same pattern as engine.rs)
// ---------------------------------------------------------------------------

#[derive(Clone)]
#[allow(dead_code)]
struct PlayerSnap {
    id: String,
    pace: u8,
    stamina: u8,
    strength: u8,
    passing: u8,
    shooting: u8,
    tackling: u8,
    dribbling: u8,
    defending: u8,
    positioning: u8,
    vision: u8,
    decisions: u8,
}

impl PlayerSnap {
    fn from(p: &PlayerData) -> Self {
        Self {
            id: p.id.clone(),
            pace: p.pace,
            stamina: p.stamina,
            strength: p.strength,
            passing: p.passing,
            shooting: p.shooting,
            tackling: p.tackling,
            dribbling: p.dribbling,
            defending: p.defending,
            positioning: p.positioning,
            vision: p.vision,
            decisions: p.decisions,
        }
    }
}

// ---------------------------------------------------------------------------
// Play-style modifiers (same as engine.rs)
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

fn home_mod(side: Side, config: &MatchConfig) -> f64 {
    match side {
        Side::Home => config.home_advantage,
        Side::Away => 1.0,
    }
}
