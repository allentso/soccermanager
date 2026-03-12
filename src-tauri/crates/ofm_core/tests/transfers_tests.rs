use chrono::{TimeZone, Utc};
use domain::manager::Manager;
use domain::player::{Player, PlayerAttributes, Position};
use domain::team::Team;
use ofm_core::clock::GameClock;
use ofm_core::game::Game;
use ofm_core::transfers::make_transfer_bid;

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

fn make_player(id: &str) -> Player {
    let mut player = Player::new(
        id.to_string(),
        format!("{}. Test", id),
        format!("{} Test", id),
        "2000-01-01".to_string(),
        "England".to_string(),
        Position::Forward,
        default_attrs(),
    );
    player.team_id = Some("team-2".to_string());
    player.contract_end = Some("2028-06-30".to_string());
    player.market_value = 1_000_000;
    player.morale = 70;
    player
}

fn make_user_team(finance: i64, transfer_budget: i64) -> Team {
    let mut team = Team::new(
        "team-1".to_string(),
        "User FC".to_string(),
        "USR".to_string(),
        "England".to_string(),
        "London".to_string(),
        "User Ground".to_string(),
        25_000,
    );
    team.finance = finance;
    team.transfer_budget = transfer_budget;
    team.manager_id = Some("manager-1".to_string());
    team
}

fn make_seller_team(starting_xi_ids: Vec<String>) -> Team {
    let mut team = Team::new(
        "team-2".to_string(),
        "Seller FC".to_string(),
        "SEL".to_string(),
        "England".to_string(),
        "Liverpool".to_string(),
        "Seller Ground".to_string(),
        28_000,
    );
    team.starting_xi_ids = starting_xi_ids;
    team
}

fn make_game_with_player(
    player: Player,
    seller_starting_xi_ids: Vec<String>,
    user_finance: i64,
    user_transfer_budget: i64,
) -> Game {
    let clock = GameClock::new(Utc.with_ymd_and_hms(2026, 8, 1, 12, 0, 0).unwrap());

    let mut manager = Manager::new(
        "manager-1".to_string(),
        "Jane".to_string(),
        "Doe".to_string(),
        "1980-01-01".to_string(),
        "England".to_string(),
    );
    manager.hire("team-1".to_string());

    Game::new(
        clock,
        manager,
        vec![
            make_user_team(user_finance, user_transfer_budget),
            make_seller_team(seller_starting_xi_ids),
        ],
        vec![player],
        vec![],
        vec![],
    )
}

#[test]
fn expiring_contract_lowers_resistance_to_sale() {
    let mut player = make_player("player-expiring");
    player.contract_end = Some("2026-08-31".to_string());

    let mut game = make_game_with_player(player, vec![], 5_000_000, 2_000_000);

    let result = make_transfer_bid(&mut game, "player-expiring", 1_000_000)
        .expect("bid should be evaluated");

    assert_eq!(result, "accepted");
    assert_eq!(
        game.players
            .iter()
            .find(|player| player.id == "player-expiring")
            .and_then(|player| player.team_id.as_deref()),
        Some("team-1")
    );
}

#[test]
fn key_player_is_harder_to_buy_than_fringe_player() {
    let mut star = make_player("player-star");
    star.attributes.shooting = 88;
    star.attributes.dribbling = 86;
    star.attributes.pace = 84;

    let mut star_game = make_game_with_player(
        star,
        vec!["player-star".to_string()],
        5_000_000,
        2_000_000,
    );
    let star_result =
        make_transfer_bid(&mut star_game, "player-star", 1_250_000).expect("star bid");

    let fringe = make_player("player-fringe");
    let mut fringe_game = make_game_with_player(fringe, vec![], 5_000_000, 2_000_000);
    let fringe_result = make_transfer_bid(&mut fringe_game, "player-fringe", 1_250_000)
        .expect("fringe bid");

    assert_eq!(star_result, "rejected");
    assert_eq!(fringe_result, "accepted");
}

#[test]
fn low_transfer_budget_cannot_behave_unrealistically() {
    let mut player = make_player("player-budget");
    player.transfer_listed = true;

    let mut game = make_game_with_player(player, vec![], 5_000_000, 400_000);

    let error = make_transfer_bid(&mut game, "player-budget", 900_000)
        .expect_err("bid should be blocked by transfer budget");

    assert_eq!(error, "Transfer budget too low");
}
