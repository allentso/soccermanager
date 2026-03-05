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

    // Traits / flairs derived from attributes
    #[serde(default)]
    pub traits: Vec<PlayerTrait>,

    // Contract & value
    pub contract_end: Option<String>,
    pub wage: u32, // weekly wage
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

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Position {
    Goalkeeper,
    Defender,
    Midfielder,
    Forward,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PlayerTrait {
    // Physical
    Speedster, // pace >= 85
    Tank,      // strength >= 85 && stamina >= 75
    Agile,     // agility >= 85
    Tireless,  // stamina >= 90
    // Technical
    Playmaker,    // passing >= 80 && vision >= 80
    Sharpshooter, // shooting >= 85
    Dribbler,     // dribbling >= 85
    BallWinner,   // tackling >= 80 && aggression >= 70
    Rock,         // defending >= 85 && positioning >= 75
    // Mental
    Leader,     // leadership >= 85 && teamwork >= 75
    CoolHead,   // composure >= 85 && decisions >= 80
    Visionary,  // vision >= 85
    HotHead,    // aggression >= 85 && composure < 50
    TeamPlayer, // teamwork >= 85
    // Goalkeeper
    SafeHands,       // handling >= 85 (GK only)
    CatReflexes,     // reflexes >= 85 (GK only)
    AerialDominance, // aerial >= 85
    // Combo / Special
    CompleteForward, // FWD: shooting >= 75 && dribbling >= 75 && pace >= 70 && strength >= 70
    Engine,          // MID: stamina >= 85 && pace >= 70 && teamwork >= 75
    SetPieceSpecialist, // passing >= 80 && shooting >= 75 && vision >= 75
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerAttributes {
    // Physical
    pub pace: u8,
    pub stamina: u8,
    pub strength: u8,
    #[serde(default = "default_attr")]
    pub agility: u8,

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
    #[serde(default = "default_attr")]
    pub composure: u8,
    #[serde(default = "default_attr")]
    pub aggression: u8,
    #[serde(default = "default_attr")]
    pub teamwork: u8,
    #[serde(default = "default_attr")]
    pub leadership: u8,

    // Goalkeeper
    #[serde(default = "default_attr")]
    pub handling: u8,
    #[serde(default = "default_attr")]
    pub reflexes: u8,
    #[serde(default = "default_attr")]
    pub aerial: u8,
}

fn default_attr() -> u8 {
    50
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

/// Derive traits purely from a player's attributes (position-independent).
pub fn compute_traits(attrs: &PlayerAttributes, _position: &Position) -> Vec<PlayerTrait> {
    let mut traits = Vec::new();

    // Physical
    if attrs.pace >= 85 {
        traits.push(PlayerTrait::Speedster);
    }
    if attrs.strength >= 85 && attrs.stamina >= 75 {
        traits.push(PlayerTrait::Tank);
    }
    if attrs.agility >= 85 {
        traits.push(PlayerTrait::Agile);
    }
    if attrs.stamina >= 90 {
        traits.push(PlayerTrait::Tireless);
    }

    // Technical
    if attrs.passing >= 80 && attrs.vision >= 80 {
        traits.push(PlayerTrait::Playmaker);
    }
    if attrs.shooting >= 85 {
        traits.push(PlayerTrait::Sharpshooter);
    }
    if attrs.dribbling >= 85 {
        traits.push(PlayerTrait::Dribbler);
    }
    if attrs.tackling >= 80 && attrs.aggression >= 70 {
        traits.push(PlayerTrait::BallWinner);
    }
    if attrs.defending >= 85 && attrs.positioning >= 75 {
        traits.push(PlayerTrait::Rock);
    }

    // Mental
    if attrs.leadership >= 85 && attrs.teamwork >= 75 {
        traits.push(PlayerTrait::Leader);
    }
    if attrs.composure >= 85 && attrs.decisions >= 80 {
        traits.push(PlayerTrait::CoolHead);
    }
    if attrs.vision >= 85 {
        traits.push(PlayerTrait::Visionary);
    }
    if attrs.aggression >= 85 && attrs.composure < 50 {
        traits.push(PlayerTrait::HotHead);
    }
    if attrs.teamwork >= 85 {
        traits.push(PlayerTrait::TeamPlayer);
    }

    // Goalkeeper-oriented (any player with high GK stats can earn these)
    if attrs.handling >= 85 {
        traits.push(PlayerTrait::SafeHands);
    }
    if attrs.reflexes >= 85 {
        traits.push(PlayerTrait::CatReflexes);
    }
    if attrs.aerial >= 85 {
        traits.push(PlayerTrait::AerialDominance);
    }

    // Combo / Special — purely attribute-based
    if attrs.shooting >= 75 && attrs.dribbling >= 75 && attrs.pace >= 70 && attrs.strength >= 70 {
        traits.push(PlayerTrait::CompleteForward);
    }
    if attrs.stamina >= 85 && attrs.pace >= 70 && attrs.teamwork >= 75 {
        traits.push(PlayerTrait::Engine);
    }
    if attrs.passing >= 80 && attrs.shooting >= 75 && attrs.vision >= 75 {
        traits.push(PlayerTrait::SetPieceSpecialist);
    }

    traits
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
        let traits = compute_traits(&attributes, &position);
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
            traits,
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
