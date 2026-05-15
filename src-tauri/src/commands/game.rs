use log::info;
use tauri::State;

use chrono::{Datelike, Duration, TimeZone, Utc};

use db::save_index::SaveEntry;
use domain::manager::Manager;
use domain::stats::StatsState;
use ofm_core::clock::GameClock;
use ofm_core::game::Game;
use ofm_core::state::StateManager;

use crate::SaveManagerState;

fn load_world_entities_from_path(
    world_source: &str,
) -> Result<
    (
        Vec<domain::team::Team>,
        Vec<domain::player::Player>,
        Vec<domain::staff::Staff>,
    ),
    String,
> {
    let path = world_source.strip_prefix("file:").unwrap_or(world_source);
    let json =
        std::fs::read_to_string(path).map_err(|_| "be.error.worldReadFileFailed".to_string())?;
    let world = ofm_core::generator::load_world_from_json(&json)?;
    Ok((world.teams, world.players, world.staff))
}

fn map_save_manager_lock_error<T>(result: std::sync::LockResult<T>) -> Result<T, String> {
    result.map_err(|_| "be.error.saveManagerUnavailable".to_string())
}

fn default_league_name() -> String {
    ["Premier", "Division"].join(" ")
}

const GENERATED_HISTORY_DEPTH_YEARS: u32 = 6;

fn long_date_format() -> String {
    ['%', 'B', ' ', '%', 'd', ',', ' ', '%', 'Y']
        .into_iter()
        .collect()
}

fn default_save_name(manager_name: &str) -> String {
    let mut save_name = manager_name.to_string();
    save_name.push('\'');
    save_name.push('s');
    save_name.push(' ');
    save_name.push_str("Career");
    save_name
}

#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RawStartupOptions {
    #[serde(default)]
    start_year: Option<i32>,
    #[serde(default)]
    start_phase: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StartPhase {
    SeasonStart,
    MidSeason,
}

impl StartPhase {
    fn parse(value: &str) -> Option<Self> {
        match value {
            "seasonStart" => Some(Self::SeasonStart),
            "midSeason" => Some(Self::MidSeason),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::SeasonStart => "seasonStart",
            Self::MidSeason => "midSeason",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct StartupOptions {
    start_year: i32,
    start_phase: StartPhase,
}

fn default_start_year() -> i32 {
    chrono::Utc::now().year().max(2020)
}

fn start_date_for_year(start_year: i32) -> chrono::DateTime<Utc> {
    Utc.with_ymd_and_hms(start_year, 7, 1, 0, 0, 0).unwrap()
}

fn current_date_for_phase(start_year: i32, start_phase: StartPhase) -> chrono::DateTime<Utc> {
    let start_date = start_date_for_year(start_year);
    match start_phase {
        StartPhase::SeasonStart => start_date,
        StartPhase::MidSeason => start_date + Duration::days(120),
    }
}

fn start_phase_for_game(game: &Game) -> StartPhase {
    if game.clock.current_date > game.clock.start_date {
        StartPhase::MidSeason
    } else {
        StartPhase::SeasonStart
    }
}

fn preseason_season_start(clock: &GameClock) -> chrono::DateTime<Utc> {
    clock.start_date + Duration::days(30)
}

fn preseason_league_year(clock: &GameClock) -> u32 {
    u32::try_from(clock.start_date.year()).unwrap_or(2020)
}

fn normalize_startup_options(raw: Option<RawStartupOptions>) -> Result<StartupOptions, String> {
    let raw = raw.unwrap_or_default();
    let start_year = raw.start_year.unwrap_or_else(default_start_year);
    if start_year < 2020 {
        return Err("be.error.createManager.startYearMin".to_string());
    }

    let start_phase = match raw.start_phase.as_deref() {
        None | Some("") => StartPhase::SeasonStart,
        Some(value) => StartPhase::parse(value)
            .ok_or_else(|| "be.error.createManager.invalidStartPhase".to_string())?,
    };

    Ok(StartupOptions {
        start_year,
        start_phase,
    })
}

fn apply_generated_past_history(game: &mut Game, startup_options: &StartupOptions) {
    ofm_core::history_generation::generate_past_world_history(
        game,
        startup_options.start_year,
        GENERATED_HISTORY_DEPTH_YEARS,
    );
}

fn bootstrap_season_start(game: &mut Game, team_id: &str) -> Result<StatsState, String> {
    let team = game
        .teams
        .iter()
        .find(|t| t.id == team_id)
        .ok_or("be.error.teamNotFound".to_string())?;
    let team_name = team.name.clone();

    game.manager.hire(team_id.to_string());
    if let Some(t) = game.teams.iter_mut().find(|t| t.id == team_id) {
        t.manager_id = Some(game.manager.id.clone());
    }
    game.manager_id = game.manager.id.clone();
    ofm_core::ai_hiring::seed_ai_managers(game);

    let season_start = preseason_season_start(&game.clock);
    let team_ids: Vec<String> = game.teams.iter().map(|t| t.id.clone()).collect();
    let league_name = default_league_name();
    let mut league = ofm_core::schedule::generate_league(
        &league_name,
        preseason_league_year(&game.clock),
        &team_ids,
        season_start,
    );
    let friendlies = ofm_core::schedule::generate_preseason_friendlies(&team_ids, season_start, 4);
    ofm_core::schedule::append_fixtures(&mut league, friendlies);
    game.league = Some(league);
    ofm_core::season_context::refresh_game_context(game);

    let date_str = game.clock.current_date.to_rfc3339();
    let welcome_msg = ofm_core::messages::welcome_message(&team_name, team_id, &date_str);
    game.messages.push(welcome_msg);

    let season_msg = ofm_core::messages::season_schedule_message(
        &league_name,
        &season_start.format(&long_date_format()).to_string(),
        &date_str,
    );
    game.messages.push(season_msg);

    let team_names: Vec<String> = game.teams.iter().map(|team| team.name.clone()).collect();
    game.news.push(ofm_core::news::season_preview_article(
        &team_names,
        &date_str,
    ));

    let staff_msg = ofm_core::messages::staff_advice_message(&team_name, team_id, &date_str);
    game.messages.push(staff_msg);

    ofm_core::player_events::generate_takeover_contract_review_message(game);

    Ok(StatsState::default())
}

fn competitive_fixture_count_for_team(game: &Game, team_id: &str) -> usize {
    game.league
        .as_ref()
        .map(|league| {
            league
                .fixtures
                .iter()
                .filter(|fixture| {
                    fixture.counts_for_league_standings()
                        && (fixture.home_team_id == team_id || fixture.away_team_id == team_id)
                })
                .count()
        })
        .unwrap_or_default()
}

fn completed_competitive_fixture_count_for_team(game: &Game, team_id: &str) -> usize {
    game.league
        .as_ref()
        .map(|league| {
            league
                .fixtures
                .iter()
                .filter(|fixture| {
                    fixture.counts_for_league_standings()
                        && fixture.status == domain::league::FixtureStatus::Completed
                        && (fixture.home_team_id == team_id || fixture.away_team_id == team_id)
                })
                .count()
        })
        .unwrap_or_default()
}

fn bootstrap_midseason_takeover(game: &mut Game, team_id: &str) -> Result<StatsState, String> {
    let team = game
        .teams
        .iter()
        .find(|t| t.id == team_id)
        .ok_or("be.error.teamNotFound".to_string())?;
    let team_name = team.name.clone();

    ofm_core::ai_hiring::seed_ai_managers(game);

    let season_start = preseason_season_start(&game.clock);
    let league_name = default_league_name();
    let team_ids: Vec<String> = game.teams.iter().map(|t| t.id.clone()).collect();
    game.league = Some(ofm_core::schedule::generate_league(
        &league_name,
        preseason_league_year(&game.clock),
        &team_ids,
        season_start,
    ));
    game.clock.current_date = season_start;
    ofm_core::season_context::refresh_game_context(game);

    let total_fixtures = competitive_fixture_count_for_team(game, team_id);
    let target_completed = (total_fixtures / 2).max(1);
    let mut stats_state = StatsState::default();
    let mut safeguard_days = 0usize;
    while completed_competitive_fixture_count_for_team(game, team_id) < target_completed {
        let mut captures = Vec::new();
        ofm_core::turn::process_day_with_capture(game, &mut |capture| captures.push(capture));
        for capture in captures {
            stats_state.append(capture);
        }
        safeguard_days += 1;
        if safeguard_days > 240 {
            break;
        }
    }

    let takeover_date = game.clock.current_date.format("%Y-%m-%d").to_string();
    let _ = ofm_core::firing::fire_ai_manager_for_team(game, team_id, &takeover_date);
    ofm_core::job_offers::hire_manager(game, team_id, &takeover_date)?;

    let staff_msg = ofm_core::messages::staff_advice_message(&team_name, team_id, &takeover_date);
    game.messages.push(staff_msg);
    ofm_core::player_events::generate_takeover_contract_review_message(game);
    ofm_core::season_context::refresh_game_context(game);

    Ok(stats_state)
}

fn bootstrap_team_selection(
    game: &mut Game,
    team_id: &str,
    start_phase: StartPhase,
) -> Result<StatsState, String> {
    match start_phase {
        StartPhase::SeasonStart => bootstrap_season_start(game, team_id),
        StartPhase::MidSeason => bootstrap_midseason_takeover(game, team_id),
    }
}

/// Step 1: Create manager + generate world. No team assigned yet.
/// Returns the Game object so the frontend can show team selection.
/// world_source: "random" (default) or a file path to a JSON world database.
#[tauri::command]
pub async fn start_new_game(
    state: State<'_, StateManager>,
    first_name: String,
    last_name: String,
    dob: String,
    nationality: String,
    startup_options: Option<RawStartupOptions>,
    world_source: Option<String>,
) -> Result<Game, String> {
    // Validate inputs
    let first_name = first_name.trim().to_string();
    let last_name = last_name.trim().to_string();
    if first_name.is_empty() || last_name.is_empty() {
        return Err("be.error.createManager.nameRequired".to_string());
    }
    if first_name.len() > 30 || last_name.len() > 30 {
        return Err("be.error.createManager.nameMaxLength".to_string());
    }
    let nationality = nationality.trim().to_string();
    if nationality.is_empty() {
        return Err("be.error.createManager.nationalityRequired".to_string());
    }

    // Validate DOB: must be a valid date and manager must be at least 30 years old
    let birth_date = chrono::NaiveDate::parse_from_str(&dob, "%Y-%m-%d")
        .map_err(|_| "be.error.createManager.invalidDobFormat".to_string())?;
    let today = chrono::Utc::now().date_naive();
    let age = today.signed_duration_since(birth_date).num_days() / 365;
    if age < 30 {
        return Err("be.error.createManager.minAge".to_string());
    }
    if age > 99 {
        return Err("be.error.createManager.invalidDob".to_string());
    }

    let manager = Manager::new(
        "mgr_user".to_string(),
        first_name,
        last_name,
        dob,
        nationality,
    );

    let startup_options = normalize_startup_options(startup_options)?;
    info!(
        "[cmd] start_new_game: {} {} (nationality={}, start_year={}, start_phase={}, world_source={:?})",
        manager.first_name,
        manager.last_name,
        manager.nationality,
        startup_options.start_year,
        startup_options.start_phase.as_str(),
        world_source
    );

    let mut clock = GameClock::new(start_date_for_year(startup_options.start_year));
    clock.current_date =
        current_date_for_phase(startup_options.start_year, startup_options.start_phase);

    // Load world based on source
    let world_source = world_source.unwrap_or_else(|| "random".to_string());
    let (teams, players, staff) = if world_source == "random" {
        ofm_core::generator::generate_world(None)
    } else {
        load_world_entities_from_path(&world_source)?
    };

    let mut new_game = Game::new(clock, manager, teams, players, staff, vec![]);
    apply_generated_past_history(&mut new_game, &startup_options);

    info!(
        "[cmd] start_new_game: world generated with {} teams, {} players, {} staff",
        new_game.teams.len(),
        new_game.players.len(),
        new_game.staff.len()
    );
    state.set_game(new_game.clone());
    state.set_stats_state(StatsState::default());
    Ok(new_game)
}

/// Step 2: User picks a team. Assigns manager, generates welcome message, saves to DB.
#[tauri::command]
pub async fn select_team(
    state: State<'_, StateManager>,
    sm_state: State<'_, SaveManagerState>,
    team_id: String,
) -> Result<Game, String> {
    info!("[cmd] select_team: team_id={}", team_id);
    let mut game = state
        .get_game(|g: &Game| g.clone())
        .ok_or("be.error.noActiveGameSession".to_string())?;

    let start_phase = start_phase_for_game(&game);
    let stats_state = bootstrap_team_selection(&mut game, &team_id, start_phase)?;

    // Save to new per-save DB
    let manager_name = format!("{} {}", game.manager.first_name, game.manager.last_name);
    let save_name = default_save_name(&manager_name);

    let mut sm = map_save_manager_lock_error(sm_state.0.lock())?;
    let save_id = sm.create_save(&game, &save_name)?;
    state.set_save_id(save_id);

    state.set_game(game.clone());
    state.set_stats_state(stats_state);
    Ok(game)
}

#[tauri::command]
pub async fn get_saves(sm_state: State<'_, SaveManagerState>) -> Result<Vec<SaveEntry>, String> {
    log::debug!("[cmd] get_saves");
    let mut sm = map_save_manager_lock_error(sm_state.0.lock())?;
    sm.load_saves()
}

#[tauri::command]
pub async fn delete_save(
    sm_state: State<'_, SaveManagerState>,
    save_id: String,
) -> Result<bool, String> {
    info!("[cmd] delete_save: save_id={}", save_id);
    let mut sm = map_save_manager_lock_error(sm_state.0.lock())?;
    sm.delete_save(&save_id)
}

#[tauri::command]
pub async fn load_game(
    state: State<'_, StateManager>,
    sm_state: State<'_, SaveManagerState>,
    save_id: String,
) -> Result<String, String> {
    info!("[cmd] load_game: save_id={}", save_id);
    let mut sm = map_save_manager_lock_error(sm_state.0.lock())?;
    let mut game = sm.load_game(&save_id)?;
    let stats_state = sm.load_stats_state(&save_id)?;
    ofm_core::ai_hiring::seed_ai_managers(&mut game);
    ofm_core::season_context::refresh_game_context(&mut game);

    let mgr_name = format!("{} {}", game.manager.first_name, game.manager.last_name);

    state.set_save_id(save_id);
    state.set_game(game);
    state.set_stats_state(stats_state);
    Ok(mgr_name)
}

#[tauri::command]
pub async fn get_active_game(state: State<'_, StateManager>) -> Result<Game, String> {
    log::debug!("[cmd] get_active_game");
    state
        .get_game(|g: &Game| g.clone())
        .ok_or("be.error.noActiveGameSession".to_string())
}

#[tauri::command]
pub async fn save_game(
    state: State<'_, StateManager>,
    sm_state: State<'_, SaveManagerState>,
) -> Result<(), String> {
    info!("[cmd] save_game");
    let game = state
        .get_game(|g: &Game| g.clone())
        .ok_or("be.error.noActiveGameSession".to_string())?;

    let save_id = state
        .get_save_id()
        .ok_or("be.error.noActiveSaveSession".to_string())?;

    let mut sm = map_save_manager_lock_error(sm_state.0.lock())?;
    sm.save_game(&game, &save_id)?;
    let stats_state = state
        .get_stats_state(|stats| stats.clone())
        .unwrap_or_default();
    sm.save_stats_state(&stats_state, &save_id)
}

/// Save the current game and clear the active session so the player returns to the main menu.
#[tauri::command]
pub async fn exit_to_menu(
    state: State<'_, StateManager>,
    sm_state: State<'_, SaveManagerState>,
) -> Result<(), String> {
    info!("[cmd] exit_to_menu");
    let game = state
        .get_game(|g: &Game| g.clone())
        .ok_or("be.error.noActiveGameSession")?;

    // Auto-save
    if let Some(save_id) = state.get_save_id() {
        let mut sm = map_save_manager_lock_error(sm_state.0.lock())?;
        sm.save_game(&game, &save_id)?;
        let stats_state = state
            .get_stats_state(|stats| stats.clone())
            .unwrap_or_default();
        sm.save_stats_state(&stats_state, &save_id)?;
    }

    // Clear the in-memory game state
    state.clear_game();
    state.clear_save_id();

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        apply_generated_past_history, bootstrap_team_selection, current_date_for_phase,
        load_world_entities_from_path, map_save_manager_lock_error, normalize_startup_options,
        preseason_league_year, preseason_season_start, start_date_for_year, RawStartupOptions,
        StartPhase, StartupOptions,
    };
    use ofm_core::{clock::GameClock, game::Game, season_context::refresh_game_context};
    use std::sync::Mutex;

    fn default_player_attributes() -> domain::player::PlayerAttributes {
        domain::player::PlayerAttributes {
            pace: 60,
            stamina: 60,
            strength: 60,
            agility: 60,
            passing: 60,
            shooting: 60,
            tackling: 60,
            dribbling: 60,
            defending: 60,
            positioning: 60,
            vision: 60,
            decisions: 60,
            composure: 60,
            aggression: 50,
            teamwork: 60,
            leadership: 50,
            handling: 20,
            reflexes: 20,
            aerial: 60,
        }
    }

    fn make_bootstrap_test_game() -> Game {
        let clock = GameClock::new(start_date_for_year(2032));
        let manager = domain::manager::Manager::new(
            "mgr-user".to_string(),
            "Alex".to_string(),
            "Manager".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        let teams = vec![
            domain::team::Team::new(
                "team1".to_string(),
                "Alpha FC".to_string(),
                "AFC".to_string(),
                "England".to_string(),
                "London".to_string(),
                "Alpha Park".to_string(),
                20_000,
            ),
            domain::team::Team::new(
                "team2".to_string(),
                "Beta FC".to_string(),
                "BFC".to_string(),
                "England".to_string(),
                "Manchester".to_string(),
                "Beta Park".to_string(),
                22_000,
            ),
        ];
        let staff = vec![
            {
                let mut staff = domain::staff::Staff::new(
                    "staff1".to_string(),
                    "Pat".to_string(),
                    "Coach".to_string(),
                    "1978-01-01".to_string(),
                    domain::staff::StaffRole::AssistantManager,
                    domain::staff::StaffAttributes {
                        coaching: 70,
                        judging_ability: 65,
                        judging_potential: 64,
                        physiotherapy: 40,
                    },
                );
                staff.nationality = "England".to_string();
                staff.team_id = Some("team1".to_string());
                staff
            },
            {
                let mut staff = domain::staff::Staff::new(
                    "staff2".to_string(),
                    "Lee".to_string(),
                    "Coach".to_string(),
                    "1979-01-01".to_string(),
                    domain::staff::StaffRole::AssistantManager,
                    domain::staff::StaffAttributes {
                        coaching: 72,
                        judging_ability: 66,
                        judging_potential: 65,
                        physiotherapy: 39,
                    },
                );
                staff.nationality = "England".to_string();
                staff.team_id = Some("team2".to_string());
                staff
            },
        ];

        let mut players = Vec::new();
        for team_id in ["team1", "team2"] {
            for index in 0..11 {
                let position = if index == 0 {
                    domain::player::Position::Goalkeeper
                } else if index < 5 {
                    domain::player::Position::Defender
                } else if index < 8 {
                    domain::player::Position::Midfielder
                } else {
                    domain::player::Position::Forward
                };
                let mut player = domain::player::Player::new(
                    format!("{}-player-{}", team_id, index),
                    format!("{} P{}", team_id, index),
                    format!("{} Player {}", team_id, index),
                    format!("199{}-01-01", index),
                    "England".to_string(),
                    position,
                    default_player_attributes(),
                );
                player.team_id = Some(team_id.to_string());
                player.ovr = 62 + index as u8;
                player.potential = 68 + index as u8;
                players.push(player);
            }
        }

        Game::new(clock, manager, teams, players, staff, vec![])
    }

    #[test]
    fn load_world_entities_from_path_returns_read_file_key_when_missing() {
        let result =
            load_world_entities_from_path("file:Z:/definitely-missing/openfootmanager-world.json");

        assert_eq!(result.unwrap_err(), "be.error.worldReadFileFailed");
    }

    #[test]
    fn map_save_manager_lock_error_returns_backend_key_for_poisoned_mutex() {
        let mutex = Mutex::new(());
        let _ = std::panic::catch_unwind(|| {
            let _guard = mutex.lock().unwrap();
            panic!("poison save manager mutex for test");
        });

        let result = map_save_manager_lock_error(mutex.lock());

        assert_eq!(result.unwrap_err(), "be.error.saveManagerUnavailable");
    }

    #[test]
    fn normalize_startup_options_defaults_to_current_year_and_season_start() {
        let options = normalize_startup_options(None).unwrap();

        assert!(options.start_year >= 2020);
        assert_eq!(options.start_phase, StartPhase::SeasonStart);
    }

    #[test]
    fn normalize_startup_options_rejects_years_before_2020() {
        let result = normalize_startup_options(Some(RawStartupOptions {
            start_year: Some(2019),
            start_phase: Some("seasonStart".to_string()),
        }));

        assert_eq!(result.unwrap_err(), "be.error.createManager.startYearMin");
    }

    #[test]
    fn normalize_startup_options_rejects_unknown_start_phase() {
        let result = normalize_startup_options(Some(RawStartupOptions {
            start_year: Some(2026),
            start_phase: Some("playoffs".to_string()),
        }));

        assert_eq!(
            result.unwrap_err(),
            "be.error.createManager.invalidStartPhase"
        );
    }

    #[test]
    fn start_date_for_year_uses_selected_july_first() {
        let start_date = start_date_for_year(2032);

        assert_eq!(start_date.to_rfc3339(), "2032-07-01T00:00:00+00:00");
    }

    #[test]
    fn current_date_for_midseason_phase_is_after_start_date() {
        let current_date = current_date_for_phase(2032, StartPhase::MidSeason);

        assert_eq!(current_date.to_rfc3339(), "2032-10-29T00:00:00+00:00");
    }

    #[test]
    fn preseason_league_setup_uses_selected_start_year_for_context() {
        let clock = GameClock::new(start_date_for_year(2032));
        let manager = domain::manager::Manager::new(
            "mgr1".to_string(),
            "Alex".to_string(),
            "Manager".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        let teams = vec![
            domain::team::Team::new(
                "team1".to_string(),
                "Alpha FC".to_string(),
                "AFC".to_string(),
                "England".to_string(),
                "London".to_string(),
                "Alpha Park".to_string(),
                20_000,
            ),
            domain::team::Team::new(
                "team2".to_string(),
                "Beta FC".to_string(),
                "BFC".to_string(),
                "England".to_string(),
                "Manchester".to_string(),
                "Beta Park".to_string(),
                22_000,
            ),
        ];
        let mut game = Game::new(clock, manager, teams, vec![], vec![], vec![]);

        let season_start = preseason_season_start(&game.clock);
        let team_ids = game
            .teams
            .iter()
            .map(|team| team.id.clone())
            .collect::<Vec<_>>();
        game.league = Some(ofm_core::schedule::generate_league(
            "Premier Division",
            preseason_league_year(&game.clock),
            &team_ids,
            season_start,
        ));
        refresh_game_context(&mut game);

        assert_eq!(
            game.clock.start_date.to_rfc3339(),
            "2032-07-01T00:00:00+00:00"
        );
        assert_eq!(game.league.as_ref().map(|league| league.season), Some(2032));
        assert_eq!(
            game.season_context.season_start.as_deref(),
            Some("2032-07-31")
        );
        assert_eq!(game.season_context.days_until_season_start, Some(30));
    }

    #[test]
    fn apply_generated_past_history_populates_default_six_prior_seasons() {
        let clock = GameClock::new(start_date_for_year(2032));
        let manager = domain::manager::Manager::new(
            "mgr-user".to_string(),
            "Alex".to_string(),
            "Manager".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        let teams = vec![
            domain::team::Team::new(
                "team1".to_string(),
                "Alpha FC".to_string(),
                "AFC".to_string(),
                "England".to_string(),
                "London".to_string(),
                "Alpha Park".to_string(),
                20_000,
            ),
            domain::team::Team::new(
                "team2".to_string(),
                "Beta FC".to_string(),
                "BFC".to_string(),
                "England".to_string(),
                "Manchester".to_string(),
                "Beta Park".to_string(),
                22_000,
            ),
        ];
        let staff = vec![
            {
                let mut staff = domain::staff::Staff::new(
                    "staff1".to_string(),
                    "Pat".to_string(),
                    "Coach".to_string(),
                    "1978-01-01".to_string(),
                    domain::staff::StaffRole::AssistantManager,
                    domain::staff::StaffAttributes {
                        coaching: 70,
                        judging_ability: 65,
                        judging_potential: 64,
                        physiotherapy: 40,
                    },
                );
                staff.nationality = "England".to_string();
                staff.team_id = Some("team1".to_string());
                staff
            },
            {
                let mut staff = domain::staff::Staff::new(
                    "staff2".to_string(),
                    "Lee".to_string(),
                    "Coach".to_string(),
                    "1979-01-01".to_string(),
                    domain::staff::StaffRole::AssistantManager,
                    domain::staff::StaffAttributes {
                        coaching: 72,
                        judging_ability: 66,
                        judging_potential: 65,
                        physiotherapy: 39,
                    },
                );
                staff.nationality = "England".to_string();
                staff.team_id = Some("team2".to_string());
                staff
            },
        ];
        let players = vec![
            {
                let mut player = domain::player::Player::new(
                    "player1".to_string(),
                    "A. Keeper".to_string(),
                    "Alex Keeper".to_string(),
                    "1994-01-01".to_string(),
                    "England".to_string(),
                    domain::player::Position::Goalkeeper,
                    domain::player::PlayerAttributes {
                        pace: 48,
                        stamina: 62,
                        strength: 64,
                        agility: 66,
                        passing: 50,
                        shooting: 20,
                        tackling: 18,
                        dribbling: 32,
                        defending: 24,
                        positioning: 68,
                        vision: 48,
                        decisions: 63,
                        composure: 61,
                        aggression: 38,
                        teamwork: 64,
                        leadership: 58,
                        handling: 76,
                        reflexes: 77,
                        aerial: 72,
                    },
                );
                player.team_id = Some("team1".to_string());
                player.ovr = 68;
                player.potential = 73;
                player
            },
            {
                let mut player = domain::player::Player::new(
                    "player2".to_string(),
                    "A. Striker".to_string(),
                    "Alex Striker".to_string(),
                    "1996-01-01".to_string(),
                    "England".to_string(),
                    domain::player::Position::Striker,
                    domain::player::PlayerAttributes {
                        pace: 72,
                        stamina: 68,
                        strength: 70,
                        agility: 71,
                        passing: 60,
                        shooting: 79,
                        tackling: 34,
                        dribbling: 73,
                        defending: 28,
                        positioning: 74,
                        vision: 62,
                        decisions: 68,
                        composure: 69,
                        aggression: 52,
                        teamwork: 64,
                        leadership: 47,
                        handling: 18,
                        reflexes: 18,
                        aerial: 61,
                    },
                );
                player.team_id = Some("team1".to_string());
                player.ovr = 74;
                player.potential = 80;
                player
            },
            {
                let mut player = domain::player::Player::new(
                    "player3".to_string(),
                    "B. Keeper".to_string(),
                    "Ben Keeper".to_string(),
                    "1993-01-01".to_string(),
                    "England".to_string(),
                    domain::player::Position::Goalkeeper,
                    domain::player::PlayerAttributes {
                        pace: 47,
                        stamina: 61,
                        strength: 63,
                        agility: 65,
                        passing: 49,
                        shooting: 19,
                        tackling: 18,
                        dribbling: 30,
                        defending: 23,
                        positioning: 67,
                        vision: 47,
                        decisions: 62,
                        composure: 60,
                        aggression: 39,
                        teamwork: 63,
                        leadership: 57,
                        handling: 75,
                        reflexes: 76,
                        aerial: 71,
                    },
                );
                player.team_id = Some("team2".to_string());
                player.ovr = 67;
                player.potential = 72;
                player
            },
            {
                let mut player = domain::player::Player::new(
                    "player4".to_string(),
                    "B. Striker".to_string(),
                    "Ben Striker".to_string(),
                    "1995-01-01".to_string(),
                    "England".to_string(),
                    domain::player::Position::Striker,
                    domain::player::PlayerAttributes {
                        pace: 71,
                        stamina: 67,
                        strength: 69,
                        agility: 70,
                        passing: 59,
                        shooting: 78,
                        tackling: 33,
                        dribbling: 72,
                        defending: 27,
                        positioning: 73,
                        vision: 61,
                        decisions: 67,
                        composure: 68,
                        aggression: 51,
                        teamwork: 63,
                        leadership: 46,
                        handling: 18,
                        reflexes: 18,
                        aerial: 60,
                    },
                );
                player.team_id = Some("team2".to_string());
                player.ovr = 73;
                player.potential = 79;
                player
            },
        ];
        let mut game = Game::new(clock, manager, teams, players, staff, vec![]);

        apply_generated_past_history(
            &mut game,
            &StartupOptions {
                start_year: 2032,
                start_phase: StartPhase::SeasonStart,
            },
        );

        assert!(game.teams.iter().all(|team| team.history.len() == 6));
        assert_eq!(game.world_history.season_awards.len(), 6);
        assert!(game.players.iter().any(|player| player.career.len() == 6));
        assert!(game
            .managers
            .iter()
            .any(|manager| !manager.career_history.is_empty()));
    }

    #[test]
    fn bootstrap_team_selection_midseason_populates_half_season_state() {
        let mut game = make_bootstrap_test_game();

        let stats_state =
            bootstrap_team_selection(&mut game, "team1", StartPhase::MidSeason).unwrap();

        let league = game.league.as_ref().unwrap();
        let completed = league
            .fixtures
            .iter()
            .filter(|fixture| {
                fixture.counts_for_league_standings()
                    && fixture.status == domain::league::FixtureStatus::Completed
                    && (fixture.home_team_id == "team1" || fixture.away_team_id == "team1")
            })
            .count();
        let scheduled = league
            .fixtures
            .iter()
            .filter(|fixture| {
                fixture.counts_for_league_standings()
                    && (fixture.home_team_id == "team1" || fixture.away_team_id == "team1")
            })
            .count();

        assert_eq!(completed, scheduled / 2);
        assert!(!stats_state.team_matches.is_empty());
        assert!(game
            .news
            .iter()
            .any(|article| { article.category == domain::news::NewsCategory::ManagerialChange }));
    }
}
