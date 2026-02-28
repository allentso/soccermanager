use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Player {
    pub id: String,
    pub match_name: String,
    pub full_name: String,
    pub date_of_birth: String,
    pub nationality: String,

    pub position: Position,

    // Core attributes 0-100
    pub attributes: PlayerAttributes,

    // Dynamic match/season values
    pub condition: u8, // 0-100 (stamina/match fitness)
    pub morale: u8,    // 0-100

    pub injury: Option<Injury>,
    pub team_id: Option<String>,

    // Contract & value
    pub contract_end: Option<String>,
    pub wage: u32,           // weekly wage
    pub market_value: u64,

    // Season stats
    pub stats: PlayerSeasonStats,

    // Career history
    pub career: Vec<CareerEntry>,

    // Transfer status
    #[serde(default)]
    pub transfer_listed: bool,
    #[serde(default)]
    pub loan_listed: bool,
    #[serde(default)]
    pub transfer_offers: Vec<TransferOffer>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Position {
    Goalkeeper,
    Defender,
    Midfielder,
    Forward,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerAttributes {
    // Physical
    pub pace: u8,
    pub stamina: u8,
    pub strength: u8,

    // Technical
    pub passing: u8,
    pub shooting: u8,
    pub tackling: u8,
    pub dribbling: u8,
    pub defending: u8,

    // Mental
    pub positioning: u8,
    pub vision: u8,
    pub decisions: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Injury {
    pub name: String,
    pub days_remaining: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PlayerSeasonStats {
    pub appearances: u32,
    pub goals: u32,
    pub assists: u32,
    pub clean_sheets: u32,
    pub yellow_cards: u32,
    pub red_cards: u32,
    pub avg_rating: f32,
    pub minutes_played: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CareerEntry {
    pub season: u32,
    pub team_id: String,
    pub team_name: String,
    pub appearances: u32,
    pub goals: u32,
    pub assists: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferOffer {
    pub id: String,
    pub from_team_id: String,
    pub fee: u64,
    pub wage_offered: u32,
    pub status: TransferOfferStatus,
    pub date: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TransferOfferStatus {
    Pending,
    Accepted,
    Rejected,
    Withdrawn,
}

impl Player {
    pub fn new(
        id: String,
        match_name: String,
        full_name: String,
        date_of_birth: String,
        nationality: String,
        position: Position,
        attributes: PlayerAttributes,
    ) -> Self {
        Self {
            id,
            match_name,
            full_name,
            date_of_birth,
            nationality,
            position,
            attributes,
            condition: 100,
            morale: 100,
            injury: None,
            team_id: None,
            contract_end: None,
            wage: 0,
            market_value: 0,
            stats: PlayerSeasonStats::default(),
            career: Vec::new(),
            transfer_listed: false,
            loan_listed: false,
            transfer_offers: Vec::new(),
        }
    }
}
