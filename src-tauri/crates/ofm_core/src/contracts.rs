use crate::game::Game;
use chrono::{Datelike, Months, NaiveDate};
use domain::message::{InboxMessage, MessageCategory, MessagePriority};
use domain::player::Player;
use domain::team::Team;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ContractWarningStage {
    TwelveMonths,
    SixMonths,
    ThreeMonths,
    FinalWeeks,
}

impl ContractWarningStage {
    pub(crate) fn message_suffix(self) -> &'static str {
        match self {
            ContractWarningStage::TwelveMonths => "12m",
            ContractWarningStage::SixMonths => "6m",
            ContractWarningStage::ThreeMonths => "3m",
            ContractWarningStage::FinalWeeks => "final",
        }
    }

    pub(crate) fn morale_pressure(self) -> i16 {
        match self {
            ContractWarningStage::TwelveMonths => 2,
            ContractWarningStage::SixMonths => 4,
            ContractWarningStage::ThreeMonths => 6,
            ContractWarningStage::FinalWeeks => 9,
        }
    }
}

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

pub fn contract_warning_stage(
    contract_end: Option<&str>,
    current_date: NaiveDate,
) -> Option<ContractWarningStage> {
    let days_remaining = contract_days_remaining(contract_end, current_date)?;

    if days_remaining <= 0 {
        return None;
    }

    if days_remaining <= 30 {
        return Some(ContractWarningStage::FinalWeeks);
    }

    if days_remaining <= 90 {
        return Some(ContractWarningStage::ThreeMonths);
    }

    if days_remaining <= 180 {
        return Some(ContractWarningStage::SixMonths);
    }

    if days_remaining <= 365 {
        return Some(ContractWarningStage::TwelveMonths);
    }

    None
}

pub fn process_contract_expiries(game: &mut Game) {
    let current_date = game.clock.current_date.date_naive();
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();

    let expired_player_indices: Vec<usize> = game
        .players
        .iter()
        .enumerate()
        .filter_map(|(index, player)| {
            let days_remaining =
                contract_days_remaining(player.contract_end.as_deref(), current_date)?;
            if player.team_id.is_some() && days_remaining <= 0 {
                Some(index)
            } else {
                None
            }
        })
        .collect();

    for player_index in expired_player_indices {
        let player_id = game.players[player_index].id.clone();
        let player_name = game.players[player_index].match_name.clone();
        let team_id = game.players[player_index].team_id.clone();

        if let Some(team_id) = team_id.as_deref()
            && let Some(team) = game
                .teams
                .iter_mut()
                .find(|candidate| candidate.id == team_id)
        {
            let team_name = team.name.clone();
            remove_player_from_team_references(team, &player_id);

            let player = &mut game.players[player_index];
            player.team_id = None;
            player.contract_end = None;
            player.wage = 0;
            player.transfer_listed = false;
            player.loan_listed = false;
            player.transfer_offers.clear();

            game.messages.push(contract_expired_message(
                &player_id,
                &player_name,
                &team_name,
                &today,
            ));
        }
    }
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

    wage *= importance_wage_multiplier(player);

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

fn importance_wage_multiplier(player: &Player) -> f32 {
    if player.market_value >= 2_000_000 {
        return 1.18;
    }

    if player.market_value >= 750_000 {
        return 1.10;
    }

    if player.market_value <= 150_000 {
        return 0.95;
    }

    1.0
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
    contract_days_remaining(player.contract_end.as_deref(), current_date)
        .unwrap_or(0)
        .max(0)
}

fn round_up_to_nearest_thousand(value: u32) -> u32 {
    if value == 0 {
        return 0;
    }

    ((value + 999) / 1000) * 1000
}

fn contract_days_remaining(contract_end: Option<&str>, current_date: NaiveDate) -> Option<i64> {
    let contract_end = contract_end?;
    let contract_end_date = NaiveDate::parse_from_str(contract_end, "%Y-%m-%d").ok()?;
    Some((contract_end_date - current_date).num_days())
}

fn remove_player_from_team_references(team: &mut Team, player_id: &str) {
    team.starting_xi_ids.retain(|id| id != player_id);

    for group in &mut team.training_groups {
        group.player_ids.retain(|id| id != player_id);
    }

    clear_match_role_if_matches(&mut team.match_roles.captain, player_id);
    clear_match_role_if_matches(&mut team.match_roles.vice_captain, player_id);
    clear_match_role_if_matches(&mut team.match_roles.penalty_taker, player_id);
    clear_match_role_if_matches(&mut team.match_roles.free_kick_taker, player_id);
    clear_match_role_if_matches(&mut team.match_roles.corner_taker, player_id);
}

fn clear_match_role_if_matches(role: &mut Option<String>, player_id: &str) {
    if role.as_deref() == Some(player_id) {
        *role = None;
    }
}

fn contract_expired_message(
    player_id: &str,
    player_name: &str,
    team_name: &str,
    date: &str,
) -> InboxMessage {
    InboxMessage::new(
        format!("contract_expired_{}", player_id),
        format!("{} Leaves on a Free", player_name),
        format!(
            "{} has left {} after their contract expired. The player is now a free agent.",
            player_name, team_name
        ),
        "Assistant Manager".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::Contract)
    .with_priority(MessagePriority::Urgent)
    .with_sender_role("Assistant Manager")
}
