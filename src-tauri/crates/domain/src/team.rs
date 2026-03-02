use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Team {
    pub id: String,
    pub name: String,
    pub short_name: String,
    pub country: String,
    pub city: String,
    pub stadium_name: String,
    pub stadium_capacity: u32,

    // Current state
    pub finance: i64,
    pub manager_id: Option<String>,
    pub reputation: u32,

    // Financial breakdown
    pub wage_budget: i64,
    pub transfer_budget: i64,
    pub season_income: i64,
    pub season_expenses: i64,

    // Tactical
    pub formation: String,
    pub play_style: PlayStyle,

    // Training
    #[serde(default)]
    pub training_focus: TrainingFocus,
    #[serde(default)]
    pub training_intensity: TrainingIntensity,
    #[serde(default)]
    pub training_schedule: TrainingSchedule,

    // Club info
    pub founded_year: u32,
    pub colors: TeamColors,

    // Recent form: last 5 results as "W", "D", "L" (most recent last)
    #[serde(default)]
    pub form: Vec<String>,

    // History
    pub history: Vec<TeamSeasonRecord>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum TrainingFocus {
    Physical,
    Technical,
    Tactical,
    Defending,
    Attacking,
    Recovery,
}

impl Default for TrainingFocus {
    fn default() -> Self {
        TrainingFocus::Physical
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum TrainingIntensity {
    Low,
    Medium,
    High,
}

impl Default for TrainingIntensity {
    fn default() -> Self {
        TrainingIntensity::Medium
    }
}

/// Weekly training schedule controlling how many days per week are training vs rest.
/// Rest days give full condition recovery with no training cost.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum TrainingSchedule {
    /// 6 training days, 1 rest (Sunday). Max growth, minimal recovery.
    Intense,
    /// 4 training days (Mon, Tue, Thu, Fri), 3 rest (Wed, Sat, Sun). Good balance.
    Balanced,
    /// 2 training days (Tue, Thu), 5 rest. Minimal growth, excellent recovery.
    Light,
}

impl Default for TrainingSchedule {
    fn default() -> Self {
        TrainingSchedule::Balanced
    }
}

impl TrainingSchedule {
    /// Returns true if the given weekday (chrono::Weekday) is a training day.
    /// Mon=0, Tue=1, Wed=2, Thu=3, Fri=4, Sat=5, Sun=6
    pub fn is_training_day(&self, weekday_num: u32) -> bool {
        match self {
            // Intense: rest only on Sunday (6)
            TrainingSchedule::Intense => weekday_num != 6,
            // Balanced: train Mon(0), Tue(1), Thu(3), Fri(4); rest Wed(2), Sat(5), Sun(6)
            TrainingSchedule::Balanced => matches!(weekday_num, 0 | 1 | 3 | 4),
            // Light: train Tue(1), Thu(3) only
            TrainingSchedule::Light => matches!(weekday_num, 1 | 3),
        }
    }

    /// Human-readable description of training days per week.
    pub fn training_days_per_week(&self) -> u8 {
        match self {
            TrainingSchedule::Intense => 6,
            TrainingSchedule::Balanced => 4,
            TrainingSchedule::Light => 2,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TeamColors {
    pub primary: String,
    pub secondary: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PlayStyle {
    Balanced,
    Attacking,
    Defensive,
    Possession,
    Counter,
    HighPress,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TeamSeasonRecord {
    pub season: u32,
    pub league_position: u32,
    pub played: u32,
    pub won: u32,
    pub drawn: u32,
    pub lost: u32,
    pub goals_for: u32,
    pub goals_against: u32,
}

impl Team {
    pub fn new(
        id: String,
        name: String,
        short_name: String,
        country: String,
        city: String,
        stadium_name: String,
        stadium_capacity: u32,
    ) -> Self {
        Self {
            id,
            name,
            short_name,
            country,
            city,
            stadium_name,
            stadium_capacity,
            finance: 1_000_000,
            manager_id: None,
            reputation: 500,
            wage_budget: 200_000,
            transfer_budget: 500_000,
            season_income: 0,
            season_expenses: 0,
            formation: "4-4-2".to_string(),
            play_style: PlayStyle::Balanced,
            training_focus: TrainingFocus::default(),
            training_intensity: TrainingIntensity::default(),
            training_schedule: TrainingSchedule::default(),
            founded_year: 1900,
            colors: TeamColors {
                primary: "#10b981".to_string(),
                secondary: "#ffffff".to_string(),
            },
            form: Vec::new(),
            history: Vec::new(),
        }
    }
}
