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

    // Club info
    pub founded_year: u32,
    pub colors: TeamColors,

    // History
    pub history: Vec<TeamSeasonRecord>,
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
            founded_year: 1900,
            colors: TeamColors {
                primary: "#10b981".to_string(),
                secondary: "#ffffff".to_string(),
            },
            history: Vec::new(),
        }
    }
}
