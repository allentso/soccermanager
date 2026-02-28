use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Staff {
    pub id: String,
    pub first_name: String,
    pub last_name: String,
    pub date_of_birth: String,
    pub role: StaffRole,

    // Attributes 0-100
    pub attributes: StaffAttributes,
    pub team_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum StaffRole {
    AssistantManager,
    Coach,
    Scout,
    Physio,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StaffAttributes {
    pub coaching: u8,
    pub judging_ability: u8,
    pub judging_potential: u8,
    pub physiotherapy: u8,
}

impl Staff {
    pub fn new(
        id: String,
        first_name: String,
        last_name: String,
        date_of_birth: String,
        role: StaffRole,
        attributes: StaffAttributes,
    ) -> Self {
        Self {
            id,
            first_name,
            last_name,
            date_of_birth,
            role,
            attributes,
            team_id: None,
        }
    }
}
