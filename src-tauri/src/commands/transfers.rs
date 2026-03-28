use log::info;
use tauri::State;

use ofm_core::game::Game;
use ofm_core::state::StateManager;

#[tauri::command]
pub fn toggle_transfer_list(
    state: State<'_, StateManager>,
    player_id: String,
) -> Result<Game, String> {
    toggle_transfer_list_internal(&state, &player_id)
}

fn toggle_transfer_list_internal(state: &StateManager, player_id: &str) -> Result<Game, String> {
    info!("[cmd] toggle_transfer_list: player_id={}", player_id);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    if let Some(p) = game.players.iter_mut().find(|p| p.id == player_id) {
        p.transfer_listed = !p.transfer_listed;
    } else {
        return Err("Player not found".into());
    }
    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn toggle_loan_list(state: State<'_, StateManager>, player_id: String) -> Result<Game, String> {
    toggle_loan_list_internal(&state, &player_id)
}

fn toggle_loan_list_internal(state: &StateManager, player_id: &str) -> Result<Game, String> {
    info!("[cmd] toggle_loan_list: player_id={}", player_id);
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    if let Some(p) = game.players.iter_mut().find(|p| p.id == player_id) {
        p.loan_listed = !p.loan_listed;
    } else {
        return Err("Player not found".into());
    }
    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn make_transfer_bid(
    state: State<'_, StateManager>,
    player_id: String,
    fee: u64,
) -> Result<serde_json::Value, String> {
    make_transfer_bid_internal(&state, &player_id, fee)
}

fn make_transfer_bid_internal(
    state: &StateManager,
    player_id: &str,
    fee: u64,
) -> Result<serde_json::Value, String> {
    info!(
        "[cmd] make_transfer_bid: player_id={}, fee={}",
        player_id, fee
    );
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let result = ofm_core::transfers::make_transfer_bid(&mut game, player_id, fee)?;
    state.set_game(game.clone());

    Ok(serde_json::json!({
        "result": result,
        "game": game,
    }))
}

#[tauri::command]
pub fn respond_to_offer(
    state: State<'_, StateManager>,
    player_id: String,
    offer_id: String,
    accept: bool,
) -> Result<Game, String> {
    respond_to_offer_internal(&state, &player_id, &offer_id, accept)
}

fn respond_to_offer_internal(
    state: &StateManager,
    player_id: &str,
    offer_id: &str,
    accept: bool,
) -> Result<Game, String> {
    info!(
        "[cmd] respond_to_offer: player_id={}, offer_id={}, accept={}",
        player_id, offer_id, accept
    );
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    ofm_core::transfers::respond_to_offer(&mut game, player_id, offer_id, accept)?;
    state.set_game(game.clone());
    Ok(game)
}

#[tauri::command]
pub fn counter_offer(
    state: State<'_, StateManager>,
    player_id: String,
    offer_id: String,
    requested_fee: u64,
) -> Result<serde_json::Value, String> {
    counter_offer_internal(&state, &player_id, &offer_id, requested_fee)
}

fn counter_offer_internal(
    state: &StateManager,
    player_id: &str,
    offer_id: &str,
    requested_fee: u64,
) -> Result<serde_json::Value, String> {
    info!(
        "[cmd] counter_offer: player_id={}, offer_id={}, requested_fee={}",
        player_id, offer_id, requested_fee
    );
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    let result = ofm_core::transfers::counter_offer(&mut game, player_id, offer_id, requested_fee)?;
    state.set_game(game.clone());

    Ok(serde_json::json!({
        "result": result,
        "game": game,
    }))
}

#[tauri::command]
pub fn send_scout(
    state: State<'_, StateManager>,
    scout_id: String,
    player_id: String,
) -> Result<Game, String> {
    info!(
        "[cmd] send_scout: scout_id={}, player_id={}",
        scout_id, player_id
    );
    let mut game = state
        .get_game(|g| g.clone())
        .ok_or("No active game session".to_string())?;

    ofm_core::scouting::send_scout(&mut game, &scout_id, &player_id)?;
    state.set_game(game.clone());
    Ok(game)
}

#[cfg(test)]
mod tests {
    use super::{
        counter_offer_internal, make_transfer_bid_internal, respond_to_offer_internal,
        toggle_loan_list_internal, toggle_transfer_list_internal,
    };
    use chrono::{TimeZone, Utc};
    use domain::manager::Manager;
    use domain::player::{Player, PlayerAttributes, Position, TransferOffer, TransferOfferStatus};
    use domain::season::TransferWindowStatus;
    use domain::team::Team;
    use ofm_core::clock::GameClock;
    use ofm_core::game::Game;
    use ofm_core::state::StateManager;

    fn default_attrs() -> PlayerAttributes {
        PlayerAttributes {
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
            aggression: 60,
            teamwork: 60,
            leadership: 60,
            handling: 30,
            reflexes: 30,
            aerial: 60,
        }
    }

    fn make_user_team() -> Team {
        let mut team = Team::new(
            "team-1".to_string(),
            "User FC".to_string(),
            "USR".to_string(),
            "England".to_string(),
            "London".to_string(),
            "User Ground".to_string(),
            25_000,
        );
        team.finance = 5_000_000;
        team.transfer_budget = 2_000_000;
        team.manager_id = Some("manager-1".to_string());
        team
    }

    fn make_buyer_team() -> Team {
        let mut team = Team::new(
            "team-2".to_string(),
            "Buyer FC".to_string(),
            "BUY".to_string(),
            "England".to_string(),
            "Liverpool".to_string(),
            "Buyer Ground".to_string(),
            28_000,
        );
        team.finance = 6_000_000;
        team.transfer_budget = 3_000_000;
        team
    }

    fn make_player_with_offer() -> Player {
        let mut player = Player::new(
            "player-1".to_string(),
            "P. One".to_string(),
            "Player One".to_string(),
            "2000-01-01".to_string(),
            "England".to_string(),
            Position::Forward,
            default_attrs(),
        );
        player.team_id = Some("team-1".to_string());
        player.contract_end = Some("2028-06-30".to_string());
        player.market_value = 1_000_000;
        player.transfer_offers.push(TransferOffer {
            id: "offer-1".to_string(),
            from_team_id: "team-2".to_string(),
            fee: 900_000,
            wage_offered: 0,
            status: TransferOfferStatus::Pending,
            date: "2026-08-01".to_string(),
        });
        player
    }

    fn make_game() -> Game {
        let clock = GameClock::new(Utc.with_ymd_and_hms(2026, 8, 1, 12, 0, 0).unwrap());
        let mut manager = Manager::new(
            "manager-1".to_string(),
            "Test".to_string(),
            "Manager".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        manager.hire("team-1".to_string());

        let mut game = Game::new(
            clock,
            manager,
            vec![make_user_team(), make_buyer_team()],
            vec![make_player_with_offer()],
            vec![],
            vec![],
        );
        game.season_context.transfer_window.status = TransferWindowStatus::Open;
        game
    }

    fn make_bid_target_player() -> Player {
        let mut player = Player::new(
            "player-2".to_string(),
            "P. Two".to_string(),
            "Player Two".to_string(),
            "2000-01-01".to_string(),
            "England".to_string(),
            Position::Forward,
            default_attrs(),
        );
        player.team_id = Some("team-2".to_string());
        player.contract_end = Some("2028-06-30".to_string());
        player.market_value = 1_000_000;
        player.morale = 35;
        player.stats.appearances = 1;
        player
    }

    fn make_bid_game() -> Game {
        let clock = GameClock::new(Utc.with_ymd_and_hms(2026, 8, 1, 12, 0, 0).unwrap());
        let mut manager = Manager::new(
            "manager-1".to_string(),
            "Test".to_string(),
            "Manager".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        manager.hire("team-1".to_string());

        let mut game = Game::new(
            clock,
            manager,
            vec![make_user_team(), make_buyer_team()],
            vec![make_bid_target_player()],
            vec![],
            vec![],
        );
        game.season_context.transfer_window.status = TransferWindowStatus::Open;
        game.teams[0].reputation = 700;
        game.teams[1].reputation = 350;
        game
    }

    #[test]
    fn counter_offer_internal_returns_payload_and_updates_state() {
        let state = StateManager::new();
        state.set_game(make_game());

        let response =
            counter_offer_internal(&state, "player-1", "offer-1", 1_050_000).expect("response");

        assert_eq!(response["result"].as_str(), Some("accepted"));
        assert_eq!(
            response["game"]["players"][0]["team_id"].as_str(),
            Some("team-2")
        );
        assert_eq!(
            response["game"]["players"][0]["transfer_offers"][0]["status"].as_str(),
            Some("Accepted")
        );

        let stored_game = state.get_game(|game| game.clone()).expect("stored game");
        assert_eq!(
            stored_game
                .players
                .iter()
                .find(|player| player.id == "player-1")
                .and_then(|player| player.team_id.clone())
                .as_deref(),
            Some("team-2")
        );
    }

    #[test]
    fn make_transfer_bid_internal_returns_payload_and_updates_state() {
        let state = StateManager::new();
        state.set_game(make_bid_game());

        let response = make_transfer_bid_internal(&state, "player-2", 1_050_000).expect("response");

        assert_eq!(response["result"].as_str(), Some("accepted"));
        assert_eq!(
            response["game"]["players"][0]["team_id"].as_str(),
            Some("team-1")
        );
        assert_eq!(
            response["game"]["players"][0]["transfer_offers"][0]["status"].as_str(),
            Some("Accepted")
        );

        let stored_game = state.get_game(|game| game.clone()).expect("stored game");
        assert_eq!(
            stored_game
                .players
                .iter()
                .find(|player| player.id == "player-2")
                .and_then(|player| player.team_id.clone())
                .as_deref(),
            Some("team-1")
        );
    }

    #[test]
    fn respond_to_offer_internal_returns_game_and_updates_state() {
        let state = StateManager::new();
        state.set_game(make_game());

        let response =
            respond_to_offer_internal(&state, "player-1", "offer-1", false).expect("response");

        let player = response
            .players
            .iter()
            .find(|player| player.id == "player-1")
            .expect("player should exist");
        assert_eq!(player.team_id.as_deref(), Some("team-1"));
        assert_eq!(
            player.transfer_offers[0].status,
            TransferOfferStatus::Rejected
        );

        let stored_game = state.get_game(|game| game.clone()).expect("stored game");
        let stored_player = stored_game
            .players
            .iter()
            .find(|player| player.id == "player-1")
            .expect("stored player should exist");
        assert_eq!(stored_player.team_id.as_deref(), Some("team-1"));
        assert_eq!(
            stored_player.transfer_offers[0].status,
            TransferOfferStatus::Rejected
        );
    }

    #[test]
    fn toggle_transfer_list_internal_updates_state() {
        let state = StateManager::new();
        state.set_game(make_game());

        let response = toggle_transfer_list_internal(&state, "player-1").expect("response");

        let player = response
            .players
            .iter()
            .find(|player| player.id == "player-1")
            .expect("player should exist");
        assert!(player.transfer_listed);

        let stored_game = state.get_game(|game| game.clone()).expect("stored game");
        let stored_player = stored_game
            .players
            .iter()
            .find(|player| player.id == "player-1")
            .expect("stored player should exist");
        assert!(stored_player.transfer_listed);
    }

    #[test]
    fn toggle_loan_list_internal_updates_state() {
        let state = StateManager::new();
        state.set_game(make_game());

        let response = toggle_loan_list_internal(&state, "player-1").expect("response");

        let player = response
            .players
            .iter()
            .find(|player| player.id == "player-1")
            .expect("player should exist");
        assert!(player.loan_listed);

        let stored_game = state.get_game(|game| game.clone()).expect("stored game");
        let stored_player = stored_game
            .players
            .iter()
            .find(|player| player.id == "player-1")
            .expect("stored player should exist");
        assert!(stored_player.loan_listed);
    }
}
