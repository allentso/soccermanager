use crate::clock::GameClock;
use domain::league::League;
use domain::manager::Manager;
use domain::message::InboxMessage;
use domain::player::Player;
use domain::staff::Staff;
use domain::team::Team;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Game {
    pub clock: GameClock,
    pub manager: Manager,
    pub teams: Vec<Team>,
    pub players: Vec<Player>,
    pub staff: Vec<Staff>,
    pub messages: Vec<InboxMessage>,
    pub league: Option<League>,
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
            league: None,
        }
    }
}
