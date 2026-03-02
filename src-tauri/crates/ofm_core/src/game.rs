use crate::clock::GameClock;
use domain::league::League;
use domain::manager::Manager;
use domain::message::InboxMessage;
use domain::news::NewsArticle;
use domain::player::Player;
use domain::staff::Staff;
use domain::team::Team;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BoardObjective {
    pub id: String,
    pub description: String,
    pub target: u32,
    pub objective_type: String, // "league_position", "wins", "goals_scored"
    pub met: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScoutingAssignment {
    pub id: String,
    pub scout_id: String,
    pub player_id: String,
    pub days_remaining: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Game {
    pub clock: GameClock,
    pub manager: Manager,
    pub teams: Vec<Team>,
    pub players: Vec<Player>,
    pub staff: Vec<Staff>,
    pub messages: Vec<InboxMessage>,
    #[serde(default)]
    pub news: Vec<NewsArticle>,
    pub league: Option<League>,
    #[serde(default)]
    pub scouting_assignments: Vec<ScoutingAssignment>,
    #[serde(default)]
    pub board_objectives: Vec<BoardObjective>,
}

impl Game {
    pub fn new(
        clock: GameClock,
        manager: Manager,
        teams: Vec<Team>,
        players: Vec<Player>,
        staff: Vec<Staff>,
        messages: Vec<InboxMessage>,
    ) -> Self {
        Self {
            clock,
            manager,
            teams,
            players,
            staff,
            messages,
            news: vec![],
            league: None,
            scouting_assignments: vec![],
            board_objectives: vec![],
        }
    }
}
