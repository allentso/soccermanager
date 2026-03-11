use crate::game::Game;
use chrono::{Datelike, Months, NaiveDate};
use domain::player::Player;
use domain::team::Team;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RenewalOffer {
    pub weekly_wage: u32,
    pub contract_years: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum RenewalDecision {
    Accepted,
    Rejected,
    CounterOffer,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RenewalOutcome {
    pub decision: RenewalDecision,
    pub suggested_wage: Option<u32>,
    pub suggested_years: Option<u32>,
}

pub fn evaluate_renewal_offer(
    player: &Player,
    team: &Team,
    current_date: NaiveDate,
    offer: &RenewalOffer,
) -> RenewalOutcome {
    let expected_wage = expected_wage(player, team, current_date);
    let expected_years = expected_contract_years(player, current_date);
    let minimum_wage = minimum_acceptable_wage(player.wage);

    if offer.weekly_wage < minimum_wage || offer.contract_years == 0 {
        return RenewalOutcome {
            decision: RenewalDecision::Rejected,
            suggested_wage: None,
            suggested_years: None,
        };
    }

    if offer.weekly_wage >= expected_wage && offer.contract_years >= expected_years {
        return RenewalOutcome {
            decision: RenewalDecision::Accepted,
            suggested_wage: None,
            suggested_years: None,
        };
    }

    RenewalOutcome {
        decision: RenewalDecision::CounterOffer,
        suggested_wage: Some(expected_wage),
        suggested_years: Some(expected_years),
    }
}

pub fn propose_renewal(
    game: &mut Game,
    player_id: &str,
    offer: RenewalOffer,
) -> Result<RenewalOutcome, String> {
    let manager_team_id = game
        .manager
        .team_id
        .clone()
        .ok_or("No team assigned".to_string())?;

    let team = game
        .teams
        .iter()
        .find(|candidate| candidate.id == manager_team_id)
        .ok_or("Manager team not found".to_string())?
        .clone();

    let player_index = game
        .players
        .iter()
        .position(|candidate| candidate.id == player_id)
        .ok_or("Player not found".to_string())?;

    if game.players[player_index].team_id.as_deref() != Some(team.id.as_str()) {
        return Err("Player does not belong to your club".to_string());
    }

    let current_date = game.clock.current_date.date_naive();
    let outcome = evaluate_renewal_offer(&game.players[player_index], &team, current_date, &offer);

    if outcome.decision == RenewalDecision::Accepted {
        let new_contract_end = current_date
            .checked_add_months(Months::new(offer.contract_years * 12))
            .ok_or("Unable to calculate new contract end date".to_string())?;

        let player = &mut game.players[player_index];
        player.wage = offer.weekly_wage;
        player.contract_end = Some(new_contract_end.format("%Y-%m-%d").to_string());
    }

    Ok(outcome)
}

fn expected_wage(player: &Player, team: &Team, current_date: NaiveDate) -> u32 {
    let mut wage = player.wage as f32;
    let age = player_age_on(current_date, &player.date_of_birth);
    let remaining_days = remaining_contract_days(player, current_date);

    if age <= 27 {
        wage *= 1.05;
    } else if age >= 32 {
        wage *= 0.95;
    }

    if player.morale <= 50 {
        wage *= 1.10;
    }

    if team.reputation < 40 {
        wage *= 1.05;
    }

    if remaining_days <= 180 {
        wage *= 1.10;
    } else if remaining_days <= 365 {
        wage *= 1.05;
    }

    let rounded = round_up_to_nearest_thousand(wage.ceil() as u32);
    rounded.max(player.wage)
}

fn expected_contract_years(player: &Player, current_date: NaiveDate) -> u32 {
    let age = player_age_on(current_date, &player.date_of_birth);

    if age <= 28 {
        return 3;
    }

    if age <= 32 {
        return 2;
    }

    1
}

fn minimum_acceptable_wage(current_wage: u32) -> u32 {
    ((current_wage as f32) * 0.85).floor() as u32
}

fn player_age_on(current_date: NaiveDate, date_of_birth: &str) -> i32 {
    let Ok(dob) = NaiveDate::parse_from_str(date_of_birth, "%Y-%m-%d") else {
        return 30;
    };

    let mut age = current_date.year() - dob.year();
    if current_date.ordinal() < dob.ordinal() {
        age -= 1;
    }
    age
}

fn remaining_contract_days(player: &Player, current_date: NaiveDate) -> i64 {
    let Some(contract_end) = &player.contract_end else {
        return 0;
    };

    let Ok(contract_end_date) = NaiveDate::parse_from_str(contract_end, "%Y-%m-%d") else {
        return 0;
    };

    (contract_end_date - current_date).num_days().max(0)
}

fn round_up_to_nearest_thousand(value: u32) -> u32 {
    if value == 0 {
        return 0;
    }

    ((value + 999) / 1000) * 1000
}
