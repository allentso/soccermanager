use chrono::{TimeZone, Utc};
use domain::manager::Manager;
use domain::player::{Player, PlayerAttributes, Position};
use domain::team::Team;
use ofm_core::clock::GameClock;
use ofm_core::contracts::{
    propose_renewal, RenewalDecision, RenewalOffer,
};
use ofm_core::game::Game;

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

fn make_player() -> Player {
    let mut player = Player::new(
        "player-1".to_string(),
        "J. Smith".to_string(),
        "John Smith".to_string(),
        "2000-01-01".to_string(),
        "England".to_string(),
        Position::Forward,
        default_attrs(),
    );
    player.team_id = Some("team-1".to_string());
    player.contract_end = Some("2026-10-15".to_string());
    player.wage = 12_000;
    player.morale = 75;
    player.market_value = 350_000;
    player
}

fn make_team() -> Team {
    let mut team = Team::new(
        "team-1".to_string(),
        "Alpha FC".to_string(),
        "ALP".to_string(),
        "England".to_string(),
        "London".to_string(),
        "Alpha Ground".to_string(),
        30_000,
    );
    team.manager_id = Some("manager-1".to_string());
    team.reputation = 50;
    team.wage_budget = 50_000;
    team
}

fn make_game() -> Game {
    let clock = GameClock::new(Utc.with_ymd_and_hms(2026, 8, 1, 12, 0, 0).unwrap());
    let mut manager = Manager::new(
        "manager-1".to_string(),
        "Jane".to_string(),
        "Doe".to_string(),
        "1980-01-01".to_string(),
        "England".to_string(),
    );
    manager.hire("team-1".to_string());

    Game::new(clock, manager, vec![make_team()], vec![make_player()], vec![], vec![])
}

#[test]
fn accepted_offer_updates_wage_and_term_correctly() {
    let mut game = make_game();

    let outcome = propose_renewal(
        &mut game,
        "player-1",
        RenewalOffer {
            weekly_wage: 15_000,
            contract_years: 3,
        },
    )
    .expect("renewal should succeed");

    assert!(matches!(outcome.decision, RenewalDecision::Accepted));
    let player = game.players.iter().find(|p| p.id == "player-1").unwrap();
    assert_eq!(player.wage, 15_000);
    assert_eq!(player.contract_end.as_deref(), Some("2029-08-01"));
}

#[test]
fn rejected_offer_leaves_state_unchanged() {
    let mut game = make_game();
    let original_wage = game.players[0].wage;
    let original_end = game.players[0].contract_end.clone();

    let outcome = propose_renewal(
        &mut game,
        "player-1",
        RenewalOffer {
            weekly_wage: 7_000,
            contract_years: 1,
        },
    )
    .expect("renewal should return a decision");

    assert!(matches!(outcome.decision, RenewalDecision::Rejected));
    assert_eq!(game.players[0].wage, original_wage);
    assert_eq!(game.players[0].contract_end, original_end);
}

#[test]
fn counter_offer_returns_understandable_feedback() {
    let mut game = make_game();

    let outcome = propose_renewal(
        &mut game,
        "player-1",
        RenewalOffer {
            weekly_wage: 13_000,
            contract_years: 2,
        },
    )
    .expect("renewal should return a counter offer");

    assert!(matches!(outcome.decision, RenewalDecision::CounterOffer));
    assert_eq!(outcome.suggested_wage, Some(14_000));
    assert_eq!(outcome.suggested_years, Some(3));
}
