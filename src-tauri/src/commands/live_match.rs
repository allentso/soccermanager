use log::info;
use ofm_core::player_events::{pick_response_band, ResponseBandWeights, ResponseOutcomeBand};
use rand::rngs::StdRng;
use rand::{Rng, SeedableRng};
use tauri::State;

pub use crate::application::live_match::FinishLiveMatchResponse;
use crate::application::live_match::{
    apply_match_command as apply_match_command_service,
    finish_live_match as finish_live_match_service,
    get_match_snapshot as get_match_snapshot_service,
    start_live_match as start_live_match_service,
    step_live_match as step_live_match_service,
};
use ofm_core::game::Game;
use ofm_core::state::StateManager;

// ---------------------------------------------------------------------------
// Live Match Commands
// ---------------------------------------------------------------------------

fn finish_live_match_internal(state: &StateManager) -> Result<FinishLiveMatchResponse, String> {
    finish_live_match_service(state)
}

fn team_talk_action_key(tone: &str, context: &str) -> String {
    format!("team_talk:{}:{}", tone, context)
}

fn team_talk_personality_factor(player: &domain::player::Player) -> i32 {
    let composure = i32::from(player.attributes.composure);
    let leadership = i32::from(player.attributes.leadership);
    let aggression = i32::from(player.attributes.aggression);
    ((composure + leadership - aggression) / 6).clamp(-20, 20)
}

fn adjust_weight(weight: &mut u32, delta: i32) {
    *weight = (*weight as i32 + delta).max(0) as u32;
}

fn team_talk_weight_total(weights: &ResponseBandWeights) -> u32 {
    weights.strong_positive
        + weights.mild_positive
        + weights.neutral
        + weights.mild_negative
        + weights.strong_negative
}

fn build_team_talk_weights(
    player: &domain::player::Player,
    tone: &str,
    context: &str,
) -> ResponseBandWeights {
    let mut weights = match (tone, context) {
        ("calm", _) => ResponseBandWeights {
            strong_positive: 1,
            mild_positive: 4,
            neutral: 4,
            mild_negative: 1,
            strong_negative: 0,
        },
        ("motivational", "losing") => ResponseBandWeights {
            strong_positive: 4,
            mild_positive: 4,
            neutral: 1,
            mild_negative: 1,
            strong_negative: 0,
        },
        ("motivational", "drawing") => ResponseBandWeights {
            strong_positive: 2,
            mild_positive: 4,
            neutral: 2,
            mild_negative: 1,
            strong_negative: 0,
        },
        ("motivational", "winning") => ResponseBandWeights {
            strong_positive: 1,
            mild_positive: 3,
            neutral: 3,
            mild_negative: 1,
            strong_negative: 0,
        },
        ("assertive", "losing") => ResponseBandWeights {
            strong_positive: 2,
            mild_positive: 3,
            neutral: 2,
            mild_negative: 2,
            strong_negative: 1,
        },
        ("assertive", "drawing") => ResponseBandWeights {
            strong_positive: 1,
            mild_positive: 2,
            neutral: 3,
            mild_negative: 2,
            strong_negative: 1,
        },
        ("assertive", "winning") => ResponseBandWeights {
            strong_positive: 0,
            mild_positive: 2,
            neutral: 3,
            mild_negative: 3,
            strong_negative: 1,
        },
        ("aggressive", "losing") => ResponseBandWeights {
            strong_positive: 1,
            mild_positive: 3,
            neutral: 2,
            mild_negative: 2,
            strong_negative: 1,
        },
        ("aggressive", "drawing") => ResponseBandWeights {
            strong_positive: 0,
            mild_positive: 2,
            neutral: 2,
            mild_negative: 3,
            strong_negative: 2,
        },
        ("aggressive", "winning") => ResponseBandWeights {
            strong_positive: 0,
            mild_positive: 1,
            neutral: 2,
            mild_negative: 4,
            strong_negative: 3,
        },
        ("praise", "winning") => ResponseBandWeights {
            strong_positive: 4,
            mild_positive: 4,
            neutral: 1,
            mild_negative: 1,
            strong_negative: 0,
        },
        ("praise", "drawing") => ResponseBandWeights {
            strong_positive: 2,
            mild_positive: 3,
            neutral: 3,
            mild_negative: 1,
            strong_negative: 0,
        },
        ("praise", "losing") => ResponseBandWeights {
            strong_positive: 0,
            mild_positive: 1,
            neutral: 3,
            mild_negative: 3,
            strong_negative: 1,
        },
        ("disappointed", "losing") => ResponseBandWeights {
            strong_positive: 0,
            mild_positive: 1,
            neutral: 3,
            mild_negative: 3,
            strong_negative: 2,
        },
        ("disappointed", "drawing") => ResponseBandWeights {
            strong_positive: 0,
            mild_positive: 1,
            neutral: 2,
            mild_negative: 4,
            strong_negative: 2,
        },
        ("disappointed", "winning") => ResponseBandWeights {
            strong_positive: 0,
            mild_positive: 0,
            neutral: 2,
            mild_negative: 4,
            strong_negative: 3,
        },
        _ => ResponseBandWeights {
            strong_positive: 1,
            mild_positive: 2,
            neutral: 4,
            mild_negative: 1,
            strong_negative: 0,
        },
    };

    let trust = i32::from(player.morale_core.manager_trust);
    let leadership = i32::from(player.attributes.leadership);
    let personality = team_talk_personality_factor(player);
    let receptiveness = personality + (trust - 50) / 2 + (leadership - 50) / 3;
    let tone_bias = match tone {
        "aggressive" | "assertive" | "disappointed" => receptiveness - 20,
        "praise" | "motivational" | "calm" => receptiveness + 10,
        _ => receptiveness,
    };

    adjust_weight(&mut weights.strong_positive, tone_bias / 15);
    adjust_weight(&mut weights.mild_positive, tone_bias / 10);
    adjust_weight(&mut weights.mild_negative, -tone_bias / 12);
    adjust_weight(&mut weights.strong_negative, -tone_bias / 10);

    if let Some(issue) = player.morale_core.unresolved_issue.as_ref() {
        let severity = i32::from(issue.severity);
        if severity >= 50 {
            adjust_weight(&mut weights.strong_positive, -((severity - 40) / 15));
            adjust_weight(&mut weights.mild_positive, -((severity - 40) / 12));
            adjust_weight(&mut weights.neutral, 1);
        }
        if severity >= 70 {
            adjust_weight(&mut weights.mild_negative, 1);
            adjust_weight(&mut weights.strong_negative, 1);
        }
    }

    let action_key = team_talk_action_key(tone, context);
    if let Some(memory) = player.morale_core.recent_treatment.as_ref() {
        if memory.action_key == action_key {
            let penalty = i32::from(memory.times_recently_used) * 2;
            adjust_weight(&mut weights.strong_positive, -penalty);
            adjust_weight(&mut weights.mild_positive, -penalty);
            adjust_weight(&mut weights.neutral, i32::from(memory.times_recently_used));
            adjust_weight(
                &mut weights.mild_negative,
                i32::from(memory.times_recently_used),
            );
        }
    }

    if team_talk_weight_total(&weights) == 0 {
        weights.neutral = 1;
    }

    weights
}

fn team_talk_delta_for_band(tone: &str, band: ResponseOutcomeBand) -> i16 {
    match tone {
        "calm" => match band {
            ResponseOutcomeBand::StrongPositive => 5,
            ResponseOutcomeBand::MildPositive => 3,
            ResponseOutcomeBand::Neutral => 1,
            ResponseOutcomeBand::MildNegative => -1,
            ResponseOutcomeBand::StrongNegative => -3,
        },
        "motivational" => match band {
            ResponseOutcomeBand::StrongPositive => 9,
            ResponseOutcomeBand::MildPositive => 5,
            ResponseOutcomeBand::Neutral => 1,
            ResponseOutcomeBand::MildNegative => -2,
            ResponseOutcomeBand::StrongNegative => -5,
        },
        "assertive" => match band {
            ResponseOutcomeBand::StrongPositive => 6,
            ResponseOutcomeBand::MildPositive => 3,
            ResponseOutcomeBand::Neutral => 0,
            ResponseOutcomeBand::MildNegative => -3,
            ResponseOutcomeBand::StrongNegative => -6,
        },
        "aggressive" => match band {
            ResponseOutcomeBand::StrongPositive => 7,
            ResponseOutcomeBand::MildPositive => 2,
            ResponseOutcomeBand::Neutral => -1,
            ResponseOutcomeBand::MildNegative => -5,
            ResponseOutcomeBand::StrongNegative => -9,
        },
        "praise" => match band {
            ResponseOutcomeBand::StrongPositive => 8,
            ResponseOutcomeBand::MildPositive => 5,
            ResponseOutcomeBand::Neutral => 1,
            ResponseOutcomeBand::MildNegative => -2,
            ResponseOutcomeBand::StrongNegative => -4,
        },
        "disappointed" => match band {
            ResponseOutcomeBand::StrongPositive => 3,
            ResponseOutcomeBand::MildPositive => 1,
            ResponseOutcomeBand::Neutral => -2,
            ResponseOutcomeBand::MildNegative => -5,
            ResponseOutcomeBand::StrongNegative => -8,
        },
        _ => match band {
            ResponseOutcomeBand::StrongPositive => 4,
            ResponseOutcomeBand::MildPositive => 2,
            ResponseOutcomeBand::Neutral => 0,
            ResponseOutcomeBand::MildNegative => -2,
            ResponseOutcomeBand::StrongNegative => -4,
        },
    }
}

fn reduce_by_recent_team_talk(
    delta: i16,
    player: &domain::player::Player,
    action_key: &str,
) -> i16 {
    let Some(memory) = player.morale_core.recent_treatment.as_ref() else {
        return delta;
    };

    if memory.action_key != action_key || delta <= 0 {
        return delta;
    }

    delta - i16::from(memory.times_recently_used) * 3
}

fn cap_team_talk_delta(delta: i16, player: &domain::player::Player) -> i16 {
    let Some(issue) = player.morale_core.unresolved_issue.as_ref() else {
        return delta;
    };

    if delta <= 0 {
        return delta;
    }

    if issue.severity >= 75 {
        return 0;
    }

    if issue.severity >= 50 {
        return ((delta + 1) / 2).max(1);
    }

    delta
}

fn update_recent_team_talk(player: &mut domain::player::Player, action_key: &str) {
    match player.morale_core.recent_treatment.as_mut() {
        Some(memory) if memory.action_key == action_key => {
            memory.times_recently_used = memory.times_recently_used.saturating_add(1);
        }
        Some(memory) => {
            memory.action_key = action_key.to_string();
            memory.times_recently_used = 1;
        }
        None => {
            player.morale_core.recent_treatment = Some(domain::player::RecentTreatmentMemory {
                action_key: action_key.to_string(),
                times_recently_used: 1,
            });
        }
    }
}

fn apply_team_talk_internal(
    game: &mut Game,
    tone: &str,
    context: &str,
    seed: u64,
) -> Result<Vec<serde_json::Value>, String> {
    let user_team_id = game.manager.team_id.clone().ok_or("No team assigned")?;
    let mut rng = StdRng::seed_from_u64(seed);
    let action_key = team_talk_action_key(tone, context);
    let mut results: Vec<serde_json::Value> = Vec::new();

    for player in game.players.iter_mut() {
        if player.team_id.as_deref() != Some(&user_team_id) {
            continue;
        }

        let base_morale = i16::from(player.morale);
        let weights = build_team_talk_weights(player, tone, context);
        let roll = rng.gen_range(0..team_talk_weight_total(&weights));
        let band = pick_response_band(&weights, roll);
        let delta = cap_team_talk_delta(
            reduce_by_recent_team_talk(team_talk_delta_for_band(tone, band), player, &action_key),
            player,
        )
        .clamp(-12, 12);

        let new_morale = (base_morale + delta).clamp(10, 100) as u8;
        let actual_delta = i16::from(new_morale) - base_morale;
        player.morale = new_morale;
        update_recent_team_talk(player, &action_key);

        results.push(serde_json::json!({
            "player_id": player.id,
            "player_name": player.match_name,
            "old_morale": base_morale,
            "new_morale": new_morale,
            "delta": actual_delta
        }));
    }

    Ok(results)
}

/// Start a live match for a given fixture.
/// mode: "live" | "spectator" | "instant"
#[tauri::command]
pub fn start_live_match(
    state: State<'_, StateManager>,
    fixture_index: usize,
    mode: String,
    allows_extra_time: bool,
) -> Result<engine::MatchSnapshot, String> {
    start_live_match_service(&state, fixture_index, &mode, allows_extra_time)
}

/// Step the live match forward by N minutes. Returns the events from each minute.
#[tauri::command]
pub fn step_live_match(
    state: State<'_, StateManager>,
    minutes: u16,
) -> Result<Vec<engine::MinuteResult>, String> {
    step_live_match_service(&state, minutes)
}

/// Apply a match command (substitution, tactic change, set piece taker, etc.)
#[tauri::command]
pub fn apply_match_command(
    state: State<'_, StateManager>,
    command: engine::MatchCommand,
) -> Result<engine::MatchSnapshot, String> {
    apply_match_command_service(&state, command)
}

/// Get current match snapshot without advancing time.
#[tauri::command]
pub fn get_match_snapshot(state: State<'_, StateManager>) -> Result<engine::MatchSnapshot, String> {
    get_match_snapshot_service(&state)
}

/// Finish the live match: generate report, update game state, clean up.
#[tauri::command]
pub fn finish_live_match(
    state: State<'_, StateManager>,
) -> Result<FinishLiveMatchResponse, String> {
    finish_live_match_internal(&state)
}

/// Apply a team talk and return per-player morale changes.
/// tone: "calm" | "motivational" | "assertive" | "aggressive" | "praise" | "disappointed"
/// context: "winning" | "losing" | "drawing"
#[tauri::command]
pub fn apply_team_talk(
    state: State<'_, StateManager>,
    tone: String,
    context: String,
) -> Result<Vec<serde_json::Value>, String> {
    info!("[cmd] apply_team_talk: tone={}, context={}", tone, context);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;
    let seed = rand::thread_rng().gen::<u64>();
    let results = apply_team_talk_internal(&mut game, &tone, &context, seed)?;

    state.set_game(game);
    Ok(results)
}

/// Process press conference answers: generate news article, affect squad morale.
/// answers: array of { question_id, response_id, response_tone, response_text, question_text }
#[tauri::command]
pub fn submit_press_conference(
    state: State<'_, StateManager>,
    answers: Vec<serde_json::Value>,
    home_team: String,
    away_team: String,
    home_score: u8,
    away_score: u8,
    user_team_name: String,
    user_team_id: String,
    prerendered_body: Option<String>,
    prerendered_headline: Option<String>,
) -> Result<serde_json::Value, String> {
    info!(
        "[cmd] submit_press_conference: {} {} - {} {}",
        home_team, home_score, away_score, away_team
    );
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session")?;

    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let mut rng = rand::thread_rng();

    // Build news article from press conference answers
    let mut quotes: Vec<String> = Vec::new();
    let mut morale_delta: i16 = 0;
    let mut mentioned_player_ids: Vec<String> = Vec::new();

    for answer in &answers {
        let tone = answer
            .get("response_tone")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let text = answer
            .get("response_text")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let qid = answer
            .get("question_id")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        if !text.is_empty() {
            quotes.push(format!("\"{}\"", text));
        }

        // Track player mentions
        if let Some(pid) = answer.get("player_id").and_then(|v| v.as_str()) {
            if !pid.is_empty() {
                mentioned_player_ids.push(pid.to_string());
            }
        }

        // Morale effects based on tone
        match tone {
            "Humble" | "Fair" | "Positive" | "Focused" => morale_delta += rng.gen_range(1..=3),
            "Confident" | "Ambitious" => morale_delta += rng.gen_range(2..=5),
            "Defiant" | "Frustrated" => morale_delta += rng.gen_range(-2..=2),
            "Curt" | "Evasive" => morale_delta += rng.gen_range(-3..=0),
            "Accept" | "Detailed" => morale_delta += rng.gen_range(0..=2),
            "Deflect" => morale_delta += rng.gen_range(-1..=1),
            "Praise" => morale_delta += rng.gen_range(3..=6),
            "Demanding" => morale_delta += rng.gen_range(-2..=3),
            _ => {}
        }

        // Player-focused question effects
        if qid == "player_focus" {
            if let Some(pid) = answer.get("player_id").and_then(|v| v.as_str()) {
                if !pid.is_empty() {
                    let player_delta: i16 = match tone {
                        "Praise" => rng.gen_range(4..=8),
                        "Demanding" => rng.gen_range(-3..=4),
                        "Deflect" => rng.gen_range(-2..=1),
                        _ => rng.gen_range(0..=3),
                    };
                    if let Some(p) = game.players.iter_mut().find(|p| p.id == pid) {
                        p.morale = ((p.morale as i16) + player_delta).clamp(10, 100) as u8;
                    }
                }
            }
        }
    }

    // Apply squad-wide morale effect
    morale_delta = morale_delta.clamp(-8, 8);
    if morale_delta != 0 {
        for p in game.players.iter_mut() {
            if p.team_id.as_deref() == Some(&user_team_id) {
                p.morale = ((p.morale as i16) + morale_delta).clamp(10, 100) as u8;
            }
        }
    }

    // Generate news article
    let result_str = format!(
        "{} {} - {} {}",
        home_team, home_score, away_score, away_team
    );
    let headline = prerendered_headline.unwrap_or_else(|| {
        if quotes.is_empty() {
            format!("Post-Match: {} on {}", user_team_name, result_str)
        } else {
            let sources = [
                format!("{} Manager: {}", user_team_name, quotes[0]),
                format!(
                    "Press Conference: \"{}\" — {} boss",
                    quotes[0].trim_matches('"'),
                    user_team_name
                ),
            ];
            sources[rng.gen_range(0..sources.len())].clone()
        }
    });

    let body = prerendered_body.unwrap_or_else(|| {
        if quotes.len() > 1 {
            format!(
                "Speaking after the {} result, the {} manager addressed the press.\n\n{}\n\n\
                The conference covered the result, tactical approach, and what lies ahead for the team.",
                result_str, user_team_name,
                quotes.iter().map(|q| format!("• {}", q)).collect::<Vec<_>>().join("\n")
            )
        } else if quotes.len() == 1 {
            format!(
                "The {} manager spoke briefly after the {} result.\n\n{}",
                user_team_name, result_str, quotes[0]
            )
        } else {
            format!(
                "The {} manager declined to speak at length after the {} result.",
                user_team_name, result_str
            )
        }
    });

    let article_id = format!("press_conf_{}", today);
    let article = domain::news::NewsArticle::new(
        article_id,
        headline,
        body,
        "Sports Daily".to_string(),
        today.clone(),
        domain::news::NewsCategory::MatchReport,
    )
    .with_teams(vec![user_team_id.clone()]);

    game.news.push(article);
    state.set_game(game.clone());

    Ok(serde_json::json!({
        "game": game,
        "morale_delta": morale_delta
    }))
}

#[cfg(test)]
mod tests {
    use super::{apply_team_talk_internal, finish_live_match_internal};
    use chrono::{TimeZone, Utc};
    use domain::league::{Fixture, FixtureCompetition, FixtureStatus, League, StandingEntry};
    use domain::manager::Manager;
    use domain::player::{Player, PlayerAttributes, PlayerIssue, PlayerIssueCategory, Position};
    use domain::team::Team;
    use ofm_core::clock::GameClock;
    use ofm_core::game::Game;
    use ofm_core::live_match_manager::{self, MatchMode};
    use ofm_core::state::StateManager;

    fn default_attrs(position: Position) -> PlayerAttributes {
        let is_goalkeeper = matches!(position, Position::Goalkeeper);

        PlayerAttributes {
            pace: 65,
            stamina: 65,
            strength: 65,
            agility: 65,
            passing: 65,
            shooting: if is_goalkeeper { 30 } else { 65 },
            tackling: if is_goalkeeper { 30 } else { 65 },
            dribbling: if is_goalkeeper { 30 } else { 65 },
            defending: if is_goalkeeper { 30 } else { 65 },
            positioning: 65,
            vision: 65,
            decisions: 65,
            composure: 65,
            aggression: 50,
            teamwork: 65,
            leadership: 50,
            handling: if is_goalkeeper { 75 } else { 20 },
            reflexes: if is_goalkeeper { 75 } else { 20 },
            aerial: 60,
        }
    }

    fn make_player(id: &str, name: &str, team_id: &str, position: Position) -> Player {
        let mut player = Player::new(
            id.to_string(),
            name.to_string(),
            name.to_string(),
            "1995-01-01".to_string(),
            "England".to_string(),
            position.clone(),
            default_attrs(position),
        );
        player.team_id = Some(team_id.to_string());
        player.condition = 100;
        player.morale = 70;
        player
    }

    fn make_team(id: &str, name: &str) -> Team {
        Team::new(
            id.to_string(),
            name.to_string(),
            name[..3].to_string(),
            "England".to_string(),
            "London".to_string(),
            "Stadium".to_string(),
            40_000,
        )
    }

    fn make_squad(team_id: &str, prefix: &str) -> Vec<Player> {
        let mut players = Vec::new();
        players.push(make_player(
            &format!("{}_gk", prefix),
            &format!("{} GK", prefix),
            team_id,
            Position::Goalkeeper,
        ));
        for index in 0..4 {
            players.push(make_player(
                &format!("{}_def{}", prefix, index),
                &format!("{} Def{}", prefix, index),
                team_id,
                Position::Defender,
            ));
        }
        for index in 0..4 {
            players.push(make_player(
                &format!("{}_mid{}", prefix, index),
                &format!("{} Mid{}", prefix, index),
                team_id,
                Position::Midfielder,
            ));
        }
        for index in 0..2 {
            players.push(make_player(
                &format!("{}_fwd{}", prefix, index),
                &format!("{} Fwd{}", prefix, index),
                team_id,
                Position::Forward,
            ));
        }
        players
    }

    fn make_game_with_round() -> Game {
        let clock = GameClock::new(Utc.with_ymd_and_hms(2025, 6, 15, 12, 0, 0).unwrap());
        let mut manager = Manager::new(
            "mgr1".to_string(),
            "Test".to_string(),
            "Manager".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        manager.hire("team1".to_string());

        let teams = vec![
            make_team("team1", "Home FC"),
            make_team("team2", "Away FC"),
            make_team("team3", "Third FC"),
            make_team("team4", "Fourth FC"),
        ];
        let mut players = make_squad("team1", "t1");
        players.extend(make_squad("team2", "t2"));
        players.extend(make_squad("team3", "t3"));
        players.extend(make_squad("team4", "t4"));

        let league = League {
            id: "league1".to_string(),
            name: "Test League".to_string(),
            season: 1,
            fixtures: vec![
                Fixture {
                    id: "fix1".to_string(),
                    matchday: 1,
                    date: "2025-06-15".to_string(),
                    home_team_id: "team1".to_string(),
                    away_team_id: "team2".to_string(),
                    competition: FixtureCompetition::League,
                    status: FixtureStatus::Scheduled,
                    result: None,
                },
                Fixture {
                    id: "fix2".to_string(),
                    matchday: 1,
                    date: "2025-06-15".to_string(),
                    home_team_id: "team3".to_string(),
                    away_team_id: "team4".to_string(),
                    competition: FixtureCompetition::League,
                    status: FixtureStatus::Scheduled,
                    result: None,
                },
            ],
            standings: vec![
                StandingEntry::new("team1".to_string()),
                StandingEntry::new("team2".to_string()),
                StandingEntry::new("team3".to_string()),
                StandingEntry::new("team4".to_string()),
            ],
        };

        let mut game = Game::new(clock, manager, teams, players, vec![], vec![]);
        game.league = Some(league);
        game
    }

    fn delta_for(results: &[serde_json::Value], player_id: &str) -> i64 {
        results
            .iter()
            .find(|result| result["player_id"] == player_id)
            .and_then(|result| result["delta"].as_i64())
            .unwrap()
    }

    #[test]
    fn finish_live_match_returns_completed_round_summary_response() {
        let state = StateManager::new();
        let mut game = make_game_with_round();
        let today = game.clock.current_date.format("%Y-%m-%d").to_string();
        ofm_core::turn::simulate_other_matches(&mut game, &today, Some(0));

        let mut session =
            live_match_manager::create_live_match(&game, 0, MatchMode::Instant, false).unwrap();
        session.user_side = None;
        session.run_to_completion();

        state.set_game(game);
        state.set_live_match(session);

        let response = finish_live_match_internal(&state).expect("finish live match response");

        let round_summary = response.round_summary.expect("round summary response");
        assert!(round_summary.is_complete);
        assert_eq!(round_summary.pending_fixture_count, 0);
        assert_eq!(round_summary.completed_results.len(), 2);
        assert_eq!(
            response
                .game
                .clock
                .current_date
                .format("%Y-%m-%d")
                .to_string(),
            "2025-06-16"
        );
    }

    #[test]
    fn team_talk_reactions_vary_by_player_context() {
        let mut game = make_game_with_round();
        let composed = game
            .players
            .iter_mut()
            .find(|player| player.id == "t1_mid0")
            .unwrap();
        composed.attributes.composure = 90;
        composed.attributes.leadership = 90;
        composed.attributes.aggression = 20;
        composed.morale_core.manager_trust = 80;

        let volatile = game
            .players
            .iter_mut()
            .find(|player| player.id == "t1_fwd0")
            .unwrap();
        volatile.attributes.composure = 20;
        volatile.attributes.leadership = 20;
        volatile.attributes.aggression = 90;
        volatile.morale_core.manager_trust = 25;
        volatile.morale_core.unresolved_issue = Some(PlayerIssue {
            category: PlayerIssueCategory::Morale,
            severity: 70,
        });

        let results = apply_team_talk_internal(&mut game, "aggressive", "winning", 7).unwrap();

        assert!(delta_for(&results, "t1_mid0") > delta_for(&results, "t1_fwd0"));
    }

    #[test]
    fn repeating_same_team_talk_loses_effectiveness() {
        let mut game = make_game_with_round();
        let player = game
            .players
            .iter_mut()
            .find(|player| player.id == "t1_mid0")
            .unwrap();
        player.morale = 50;
        player.morale_core.manager_trust = 70;

        let first = apply_team_talk_internal(&mut game, "motivational", "losing", 13).unwrap();
        let second = apply_team_talk_internal(&mut game, "motivational", "losing", 13).unwrap();

        assert!(delta_for(&second, "t1_mid0") <= delta_for(&first, "t1_mid0"));
    }
}
