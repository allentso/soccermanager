use crate::game::Game;
use crate::live_match_manager::LiveMatchSession;
use std::sync::Mutex;

pub struct StateManager {
    pub active_game: Mutex<Option<Game>>,
    pub live_match: Mutex<Option<LiveMatchSession>>,
}

impl StateManager {
    pub fn new() -> Self {
        Self {
            active_game: Mutex::new(None),
            live_match: Mutex::new(None),
        }
    }

    pub fn set_game(&self, game: Game) {
        let mut lock = self.active_game.lock().unwrap();
        *lock = Some(game);
    }

    pub fn get_game<F, R>(&self, f: F) -> Option<R>
    where
        F: FnOnce(&Game) -> R,
    {
        let lock = self.active_game.lock().unwrap();
        lock.as_ref().map(f)
    }

    pub fn set_live_match(&self, session: LiveMatchSession) {
        let mut lock = self.live_match.lock().unwrap();
        *lock = Some(session);
    }

    pub fn take_live_match(&self) -> Option<LiveMatchSession> {
        let mut lock = self.live_match.lock().unwrap();
        lock.take()
    }

    pub fn with_live_match<F, R>(&self, f: F) -> Option<R>
    where
        F: FnOnce(&mut LiveMatchSession) -> R,
    {
        let mut lock = self.live_match.lock().unwrap();
        lock.as_mut().map(f)
    }
}
