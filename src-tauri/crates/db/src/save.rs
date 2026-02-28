use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameSave {
    pub version: u32,
    pub name: String,
    pub created_at: String,
    pub last_played_at: String,
    // Add reference back to main struct wrapping domains
}
