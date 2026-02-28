use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum MessageCategory {
    Welcome,
    LeagueInfo,
    MatchPreview,
    MatchResult,
    Transfer,
    BoardDirective,
    PlayerMorale,
    Injury,
    Training,
    Finance,
    Contract,
    ScoutReport,
    Media,
    System,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum MessagePriority {
    Low,
    Normal,
    High,
    Urgent,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageAction {
    pub id: String,
    pub label: String,
    pub action_type: ActionType,
    pub resolved: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ActionType {
    Acknowledge,
    NavigateTo { route: String },
    ChooseOption { options: Vec<ActionOption> },
    Dismiss,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionOption {
    pub id: String,
    pub label: String,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InboxMessage {
    pub id: String,
    pub subject: String,
    pub body: String,
    pub sender: String,
    pub sender_role: String,
    pub date: String,
    pub read: bool,
    pub category: MessageCategory,
    pub priority: MessagePriority,
    pub actions: Vec<MessageAction>,
    /// Optional references to entities relevant to this message
    pub context: MessageContext,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct MessageContext {
    pub team_id: Option<String>,
    pub player_id: Option<String>,
    pub fixture_id: Option<String>,
    pub match_result: Option<ContextMatchResult>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextMatchResult {
    pub home_team_id: String,
    pub away_team_id: String,
    pub home_goals: u8,
    pub away_goals: u8,
}

impl InboxMessage {
    pub fn new(id: String, subject: String, body: String, sender: String, date: String) -> Self {
        Self {
            id,
            subject,
            body,
            sender,
            sender_role: String::new(),
            date,
            read: false,
            category: MessageCategory::System,
            priority: MessagePriority::Normal,
            actions: vec![],
            context: MessageContext::default(),
        }
    }

    pub fn with_category(mut self, category: MessageCategory) -> Self {
        self.category = category;
        self
    }

    pub fn with_priority(mut self, priority: MessagePriority) -> Self {
        self.priority = priority;
        self
    }

    pub fn with_sender_role(mut self, role: &str) -> Self {
        self.sender_role = role.to_string();
        self
    }

    pub fn with_action(mut self, action: MessageAction) -> Self {
        self.actions.push(action);
        self
    }

    pub fn with_context(mut self, context: MessageContext) -> Self {
        self.context = context;
        self
    }
}
