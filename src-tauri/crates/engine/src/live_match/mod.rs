mod helpers;
mod penalty;
mod substitution;
mod zone_resolution;

use rand::Rng;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

use crate::event::{EventType, MatchEvent};
use crate::report::MatchReport;
use crate::types::{MatchConfig, PlayStyle, PlayerData, Side, TeamData, Zone};

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
    PreMatchSwap {
        side: Side,
        player_off_id: String,
        player_on_id: String,
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
    pub home_bench: Vec<PlayerData>,
    pub away_bench: Vec<PlayerData>,
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
            MatchCommand::Substitute {
                side,
                player_off_id,
                player_on_id,
            } => self.do_substitution(side, &player_off_id, &player_on_id),
            MatchCommand::ChangeFormation { side, formation } => {
                self.apply_formation(side, &formation);
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
            MatchCommand::PreMatchSwap {
                side,
                player_off_id,
                player_on_id,
            } => {
                if self.phase != MatchPhase::PreKickOff {
                    return Err("Pre-match swaps only allowed before kick-off".into());
                }
                self.do_pre_match_swap(side, &player_off_id, &player_on_id)
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

        // Clone teams and patch in live condition values from player_conditions map
        let mut home_team = self.home.clone();
        let mut away_team = self.away.clone();
        for p in home_team
            .players
            .iter_mut()
            .chain(away_team.players.iter_mut())
        {
            if let Some(&cond) = self.player_conditions.get(&p.id) {
                p.condition = cond.round() as u8;
            }
        }

        MatchSnapshot {
            phase: self.phase,
            current_minute: self.current_minute,
            home_score: self.home_score,
            away_score: self.away_score,
            possession: self.possession,
            ball_zone: self.ball_zone,
            home_team,
            away_team,
            home_bench: self.home_bench.clone(),
            away_bench: self.away_bench.clone(),
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

        let evt = MatchEvent::new(
            start_min,
            EventType::SecondHalfStart,
            Side::Away,
            Zone::Midfield,
        );
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

        let evt = MatchEvent::new(
            start_min,
            EventType::SecondHalfStart,
            Side::Home,
            Zone::Midfield,
        );
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
                    let evt =
                        MatchEvent::new(minute, EventType::HalfTime, Side::Home, Zone::Midfield);
                    self.events.push(evt.clone());
                    events.push(evt);
                }
            }
            MatchPhase::SecondHalf => {
                if minute >= 90 + self.second_half_stoppage {
                    self.phase = MatchPhase::FullTime;
                    let evt =
                        MatchEvent::new(minute, EventType::FullTime, Side::Home, Zone::Midfield);
                    self.events.push(evt.clone());
                    events.push(evt);
                }
            }
            MatchPhase::ExtraTimeFirstHalf => {
                if minute >= 105 + self.et_first_half_stoppage {
                    self.phase = MatchPhase::ExtraTimeHalfTime;
                    let evt =
                        MatchEvent::new(minute, EventType::HalfTime, Side::Home, Zone::Midfield);
                    self.events.push(evt.clone());
                    events.push(evt);
                }
            }
            MatchPhase::ExtraTimeSecondHalf => {
                if minute >= 120 + self.et_second_half_stoppage {
                    self.phase = MatchPhase::ExtraTimeEnd;
                    let evt =
                        MatchEvent::new(minute, EventType::FullTime, Side::Home, Zone::Midfield);
                    self.events.push(evt.clone());
                    events.push(evt);
                }
            }
            _ => {}
        }
        events
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
