pub mod types;
pub mod event;
pub mod report;
pub mod engine;
pub mod live_match;
pub mod ai;

// Re-export key types for convenience
pub use engine::simulate;
pub use engine::simulate_with_rng;
pub use event::{EventType, MatchEvent};
pub use live_match::{
    LiveMatchState, MatchCommand, MatchPhase, MatchSnapshot, MinuteResult,
    SetPieceTakers, SubstitutionRecord,
};
pub use report::{GoalDetail, MatchReport, PlayerMatchStats, TeamStats};
pub use types::{MatchConfig, PlayStyle, PlayerData, Position, Side, TeamData, Zone};
