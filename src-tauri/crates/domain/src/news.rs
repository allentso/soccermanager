use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum NewsCategory {
    MatchReport,
    LeagueRoundup,
    StandingsUpdate,
    TransferRumour,
    InjuryNews,
    ManagerialChange,
    SeasonPreview,
    Editorial,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewsArticle {
    pub id: String,
    pub headline: String,
    pub body: String,
    pub source: String,
    pub date: String,
    pub category: NewsCategory,
    /// IDs of teams referenced in the article
    pub team_ids: Vec<String>,
    /// IDs of players referenced in the article
    pub player_ids: Vec<String>,
    /// Optional match score context
    pub match_score: Option<NewsMatchScore>,
    pub read: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewsMatchScore {
    pub home_team_id: String,
    pub away_team_id: String,
    pub home_goals: u8,
    pub away_goals: u8,
}

impl NewsArticle {
    pub fn new(id: String, headline: String, body: String, source: String, date: String, category: NewsCategory) -> Self {
        Self {
            id,
            headline,
            body,
            source,
            date,
            category,
            team_ids: vec![],
            player_ids: vec![],
            match_score: None,
            read: false,
        }
    }

    pub fn with_teams(mut self, ids: Vec<String>) -> Self {
        self.team_ids = ids;
        self
    }

    pub fn with_players(mut self, ids: Vec<String>) -> Self {
        self.player_ids = ids;
        self
    }

    pub fn with_score(mut self, score: NewsMatchScore) -> Self {
        self.match_score = Some(score);
        self
    }
}
