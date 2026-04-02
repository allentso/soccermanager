use crate::game::Game;
use chrono::{Datelike, Months, NaiveDate};
use domain::message::{
    DelegatedRenewalCaseData as DelegatedRenewalCaseMessageData, DelegatedRenewalReportData,
    InboxMessage, MessageCategory, MessageContext, MessagePriority,
};
use domain::negotiation::{NegotiationFeedback, NegotiationMood};
use domain::player::{ContractRenewalState, Player, RenewalSessionOutcome, RenewalSessionStatus};
use domain::staff::StaffRole;
use domain::team::Team;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

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
    pub session_status: RenewalSessionStatus,
    pub is_terminal: bool,
    pub feedback: Option<NegotiationFeedback>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DelegatedRenewalOptions {
    pub player_ids: Option<Vec<String>>,
    pub max_wage_increase_pct: u32,
    pub max_contract_years: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DelegatedRenewalResultStatus {
    Successful,
    Failed,
    Stalled,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DelegatedRenewalCase {
    pub player_id: String,
    pub player_name: String,
    pub status: DelegatedRenewalResultStatus,
    pub agreed_wage: Option<u32>,
    pub agreed_years: Option<u32>,
    pub note: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note_key: Option<String>,
    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub note_params: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DelegatedRenewalReport {
    pub success_count: u32,
    pub failure_count: u32,
    pub stalled_count: u32,
    pub cases: Vec<DelegatedRenewalCase>,
}

fn renewal_outcome(
    decision: RenewalDecision,
    suggested_wage: Option<u32>,
    suggested_years: Option<u32>,
    session_status: RenewalSessionStatus,
    is_terminal: bool,
    feedback: Option<NegotiationFeedback>,
) -> RenewalOutcome {
    RenewalOutcome {
        decision,
        suggested_wage,
        suggested_years,
        session_status,
        is_terminal,
        feedback,
    }
}

pub fn evaluate_renewal_offer(
    player: &Player,
    team: &Team,
    current_date: NaiveDate,
    offer: &RenewalOffer,
) -> RenewalOutcome {
    let round = next_renewal_round(player, None);
    let expected_wage = expected_wage(player, team, current_date);
    let expected_years = expected_contract_years(player, current_date);
    let minimum_wage = minimum_acceptable_wage(player.wage);

    if offer.weekly_wage < minimum_wage || offer.contract_years == 0 {
        let feedback = build_renewal_feedback(
            player,
            current_date,
            RenewalDecision::Rejected,
            RenewalSessionStatus::Stalled,
            round,
            expected_wage,
            false,
        );
        return renewal_outcome(
            RenewalDecision::Rejected,
            None,
            None,
            RenewalSessionStatus::Stalled,
            false,
            Some(feedback),
        );
    }

    if offer.weekly_wage >= expected_wage && offer.contract_years >= expected_years {
        let feedback = build_renewal_feedback(
            player,
            current_date,
            RenewalDecision::Accepted,
            RenewalSessionStatus::Agreed,
            round,
            expected_wage,
            false,
        );
        return renewal_outcome(
            RenewalDecision::Accepted,
            None,
            None,
            RenewalSessionStatus::Agreed,
            true,
            Some(feedback),
        );
    }

    let feedback = build_renewal_feedback(
        player,
        current_date,
        RenewalDecision::CounterOffer,
        RenewalSessionStatus::Open,
        round,
        expected_wage,
        false,
    );

    renewal_outcome(
        RenewalDecision::CounterOffer,
        Some(expected_wage),
        Some(expected_years),
        RenewalSessionStatus::Open,
        false,
        Some(feedback),
    )
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
    let today = current_date.format("%Y-%m-%d").to_string();
    let round = next_renewal_round(&game.players[player_index], Some(today.as_str()));

    if has_active_manager_block(&game.players[player_index], current_date) {
        return Ok(renewal_outcome(
            RenewalDecision::Rejected,
            None,
            None,
            RenewalSessionStatus::Blocked,
            true,
            Some(build_renewal_feedback(
                &game.players[player_index],
                current_date,
                RenewalDecision::Rejected,
                RenewalSessionStatus::Blocked,
                round,
                0,
                false,
            )),
        ));
    }

    if let Some(state) = game.players[player_index]
        .morale_core
        .renewal_state
        .as_ref()
        && state.status == RenewalSessionStatus::Agreed
        && state.last_attempt_date.as_deref() == Some(today.as_str())
    {
        return Ok(renewal_outcome(
            RenewalDecision::Rejected,
            None,
            None,
            RenewalSessionStatus::Agreed,
            true,
            Some(build_renewal_feedback(
                &game.players[player_index],
                current_date,
                RenewalDecision::Accepted,
                RenewalSessionStatus::Agreed,
                round,
                game.players[player_index].wage,
                false,
            )),
        ));
    }

    let expected_wage = expected_wage(&game.players[player_index], &team, current_date);
    let mut outcome =
        evaluate_renewal_offer(&game.players[player_index], &team, current_date, &offer);
    let relationship_blocked = should_manual_renewal_fail_on_relationship(
        &game.players[player_index],
        expected_wage,
        offer.weekly_wage,
    );

    if relationship_blocked {
        outcome = renewal_outcome(
            RenewalDecision::Rejected,
            None,
            None,
            RenewalSessionStatus::Stalled,
            false,
            Some(build_renewal_feedback(
                &game.players[player_index],
                current_date,
                RenewalDecision::Rejected,
                RenewalSessionStatus::Stalled,
                round,
                expected_wage,
                true,
            )),
        );
    }

    if outcome.decision == RenewalDecision::Accepted {
        let new_contract_end = current_date
            .checked_add_months(Months::new(offer.contract_years * 12))
            .ok_or("Unable to calculate new contract end date".to_string())?;

        let player = &mut game.players[player_index];
        player.wage = offer.weekly_wage;
        player.contract_end = Some(new_contract_end.format("%Y-%m-%d").to_string());
        let state = player
            .morale_core
            .renewal_state
            .get_or_insert_with(ContractRenewalState::default);
        state.status = RenewalSessionStatus::Agreed;
        state.manager_blocked_until = None;
        state.last_attempt_date = Some(today);
        state.last_outcome = Some(RenewalSessionOutcome::AcceptedByManager);
        state.conversation_round = round;
        return Ok(renewal_outcome(
            RenewalDecision::Accepted,
            None,
            None,
            RenewalSessionStatus::Agreed,
            true,
            Some(build_renewal_feedback(
                player,
                current_date,
                RenewalDecision::Accepted,
                RenewalSessionStatus::Agreed,
                round,
                expected_wage,
                false,
            )),
        ));
    }

    let player = &mut game.players[player_index];
    let state = player
        .morale_core
        .renewal_state
        .get_or_insert_with(ContractRenewalState::default);
    state.last_attempt_date = Some(today);
    state.conversation_round = round;

    match outcome.decision {
        RenewalDecision::Rejected => {
            state.status = outcome.session_status.clone();
            state.last_outcome = Some(RenewalSessionOutcome::RejectedByPlayer);
        }
        RenewalDecision::CounterOffer => {
            state.status = RenewalSessionStatus::Open;
            state.last_outcome = Some(RenewalSessionOutcome::Stalled);
        }
        RenewalDecision::Accepted => {}
    }

    if outcome.feedback.is_none() {
        outcome.feedback = Some(build_renewal_feedback(
            player,
            current_date,
            outcome.decision.clone(),
            outcome.session_status.clone(),
            round,
            expected_wage,
            relationship_blocked,
        ));
    }

    Ok(outcome)
}

pub fn delegate_renewals(
    game: &mut Game,
    options: DelegatedRenewalOptions,
) -> Result<DelegatedRenewalReport, String> {
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
    let assistant = game
        .staff
        .iter()
        .find(|staff| {
            staff.team_id.as_deref() == Some(team.id.as_str())
                && staff.role == StaffRole::AssistantManager
        })
        .ok_or("No assistant manager assigned to your team".to_string())?;
    let current_date = game.clock.current_date.date_naive();
    let today = current_date.format("%Y-%m-%d").to_string();
    let max_years = options.max_contract_years.max(1);
    let selected_ids = options
        .player_ids
        .clone()
        .map(|ids| ids.into_iter().collect::<HashSet<_>>());
    let candidate_indices: Vec<usize> = game
        .players
        .iter()
        .enumerate()
        .filter_map(|(index, player)| {
            if player.team_id.as_deref() != Some(team.id.as_str()) || player.contract_end.is_none()
            {
                return None;
            }

            if let Some(selected_ids) = selected_ids.as_ref() {
                if selected_ids.contains(&player.id) {
                    return Some(index);
                }

                return None;
            }

            if contract_warning_stage(player.contract_end.as_deref(), current_date).is_some() {
                return Some(index);
            }

            None
        })
        .collect();
    let mut report = DelegatedRenewalReport {
        success_count: 0,
        failure_count: 0,
        stalled_count: 0,
        cases: Vec::new(),
    };

    for player_index in candidate_indices {
        let player = &game.players[player_index];
        let expected_wage = expected_wage(player, &team, current_date);
        let expected_years = expected_contract_years(player, current_date);
        let agreed_years = expected_years.min(max_years);
        let max_wage = round_up_to_nearest_thousand(
            player
                .wage
                .saturating_mul(100 + options.max_wage_increase_pct)
                / 100,
        );

        let mut case = DelegatedRenewalCase {
            player_id: player.id.clone(),
            player_name: player.match_name.clone(),
            status: DelegatedRenewalResultStatus::Failed,
            agreed_wage: None,
            agreed_years: None,
            note: String::new(),
            note_key: None,
            note_params: HashMap::new(),
        };

        if has_active_manager_block(player, current_date) {
            report.failure_count += 1;
            case.note = "You told me not to reopen contract talks yet.".to_string();
            case.note_key = Some("be.msg.delegatedRenewals.notes.managerBlocked".to_string());
            report.cases.push(case);
            continue;
        }

        if max_wage < expected_wage || max_years < expected_years {
            report.stalled_count += 1;
            case.status = DelegatedRenewalResultStatus::Stalled;
            case.note = format!(
                "Their camp want around €{}/wk for {} years, which is beyond the delegation limits.",
                expected_wage, expected_years
            );
            case.note_key = Some("be.msg.delegatedRenewals.notes.beyondLimits".to_string());
            case.note_params = delegated_note_params(&[
                ("wage", expected_wage.to_string()),
                ("years", expected_years.to_string()),
            ]);
            let player = &mut game.players[player_index];
            let state = player
                .morale_core
                .renewal_state
                .get_or_insert_with(ContractRenewalState::default);
            state.status = RenewalSessionStatus::Stalled;
            state.last_assistant_attempt_date = Some(today.clone());
            state.last_outcome = Some(RenewalSessionOutcome::Stalled);
            state.conversation_round = 0;
            report.cases.push(case);
            continue;
        }

        let delegation_score = assistant_delegation_score(assistant, player, current_date);

        if delegation_score >= 95 {
            let new_contract_end = current_date
                .checked_add_months(Months::new(agreed_years * 12))
                .ok_or("Unable to calculate delegated contract end date".to_string())?;
            let player = &mut game.players[player_index];
            player.wage = expected_wage.min(max_wage);
            player.contract_end = Some(new_contract_end.format("%Y-%m-%d").to_string());
            let state = player
                .morale_core
                .renewal_state
                .get_or_insert_with(ContractRenewalState::default);
            state.status = RenewalSessionStatus::Agreed;
            state.manager_blocked_until = None;
            state.last_assistant_attempt_date = Some(today.clone());
            state.last_outcome = Some(RenewalSessionOutcome::AcceptedByAssistant);
            state.conversation_round = 0;

            report.success_count += 1;
            case.status = DelegatedRenewalResultStatus::Successful;
            case.agreed_wage = Some(player.wage);
            case.agreed_years = Some(agreed_years);
            case.note = "I was able to close this one without needing you to step in.".to_string();
            case.note_key = Some("be.msg.delegatedRenewals.notes.completed".to_string());
            report.cases.push(case);
            continue;
        }

        if delegation_score >= 72 {
            report.stalled_count += 1;
            case.status = DelegatedRenewalResultStatus::Stalled;
            case.note = format!(
                "They would listen, but they still want about €{}/wk for {} years and prefer to hear from you directly.",
                expected_wage, expected_years
            );
            case.note_key = Some("be.msg.delegatedRenewals.notes.prefersManager".to_string());
            case.note_params = delegated_note_params(&[
                ("wage", expected_wage.to_string()),
                ("years", expected_years.to_string()),
            ]);
            let player = &mut game.players[player_index];
            let state = player
                .morale_core
                .renewal_state
                .get_or_insert_with(ContractRenewalState::default);
            state.status = RenewalSessionStatus::Open;
            state.last_assistant_attempt_date = Some(today.clone());
            state.last_outcome = Some(RenewalSessionOutcome::Stalled);
            state.conversation_round = 0;
            report.cases.push(case);
            continue;
        }

        report.failure_count += 1;
        case.note = "They are not willing to commit through me under the current relationship and contract situation.".to_string();
        case.note_key = Some("be.msg.delegatedRenewals.notes.relationshipBlocked".to_string());
        let player = &mut game.players[player_index];
        let state = player
            .morale_core
            .renewal_state
            .get_or_insert_with(ContractRenewalState::default);
        state.status = RenewalSessionStatus::Stalled;
        state.last_assistant_attempt_date = Some(today.clone());
        state.last_outcome = Some(RenewalSessionOutcome::RejectedByPlayer);
        state.conversation_round = 0;
        report.cases.push(case);
    }

    if !report.cases.is_empty() {
        let team_name = team.name.clone();
        let message_id_suffix = game.messages.len();
        game.messages.push(delegated_renewal_report_message(
            &team.id,
            &team_name,
            &today,
            &report,
            message_id_suffix,
        ));
    }

    Ok(report)
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

fn next_renewal_round(player: &Player, today: Option<&str>) -> u8 {
    let Some(state) = player.morale_core.renewal_state.as_ref() else {
        return 1;
    };

    if let Some(today) = today {
        if state.last_attempt_date.as_deref() != Some(today) {
            return 1;
        }
    }

    state.conversation_round.saturating_add(1).max(1)
}

fn build_renewal_feedback(
    player: &Player,
    current_date: NaiveDate,
    decision: RenewalDecision,
    session_status: RenewalSessionStatus,
    round: u8,
    expected_wage: u32,
    relationship_blocked: bool,
) -> NegotiationFeedback {
    let trust = player.morale_core.manager_trust;
    let remaining_days = remaining_contract_days(player, current_date);
    let urgency_pressure = if remaining_days <= 90 {
        24
    } else if remaining_days <= 180 {
        16
    } else if remaining_days <= 365 {
        8
    } else {
        2
    };
    let morale_pressure = if player.morale <= 40 {
        24
    } else if player.morale <= 60 {
        12
    } else {
        0
    };
    let trust_pressure = if trust <= 25 {
        26
    } else if trust <= 40 {
        12
    } else {
        0
    };
    let value_pressure = if player.market_value >= 2_000_000 {
        12
    } else if player.market_value >= 750_000 {
        6
    } else {
        0
    };
    let tension = (22 + urgency_pressure + morale_pressure + trust_pressure + value_pressure)
        .clamp(10, 92) as u8;
    let patience = (100_i32 - i32::from(round.saturating_sub(1)) * 18 - i32::from(tension) / 3)
        .clamp(18, 92) as u8;

    let (mood, headline_key, detail_key) = if session_status == RenewalSessionStatus::Blocked {
        (
            NegotiationMood::Guarded,
            "playerProfile.renewalFeedbackBlockedHeadline",
            Some("playerProfile.renewalFeedbackBlockedDetail"),
        )
    } else if decision == RenewalDecision::Accepted && round >= 2 {
        (
            NegotiationMood::Positive,
            "playerProfile.renewalFeedbackAcceptedLateHeadline",
            Some("playerProfile.renewalFeedbackAcceptedLateDetail"),
        )
    } else if decision == RenewalDecision::Accepted {
        (
            NegotiationMood::Positive,
            "playerProfile.renewalFeedbackAcceptedHeadline",
            Some("playerProfile.renewalFeedbackAcceptedDetail"),
        )
    } else if relationship_blocked || tension >= 70 {
        (
            NegotiationMood::Tense,
            "playerProfile.renewalFeedbackTenseHeadline",
            Some("playerProfile.renewalFeedbackTenseDetail"),
        )
    } else if expected_wage > player.wage || round >= 2 {
        (
            NegotiationMood::Firm,
            "playerProfile.renewalFeedbackFirmHeadline",
            Some("playerProfile.renewalFeedbackFirmDetail"),
        )
    } else {
        (
            NegotiationMood::Calm,
            "playerProfile.renewalFeedbackCalmHeadline",
            Some("playerProfile.renewalFeedbackCalmDetail"),
        )
    };

    NegotiationFeedback {
        mood,
        headline_key: headline_key.to_string(),
        detail_key: detail_key.map(str::to_string),
        tension,
        patience,
        round,
        params: HashMap::new(),
    }
}

fn should_manual_renewal_fail_on_relationship(
    player: &Player,
    expected_wage: u32,
    offered_wage: u32,
) -> bool {
    let trust = player.morale_core.manager_trust;
    let relationship_margin = if trust <= 20 {
        2_000
    } else if trust <= 30 {
        1_000
    } else {
        0
    };

    relationship_margin > 0 && offered_wage < expected_wage.saturating_add(relationship_margin)
}

fn has_active_manager_block(player: &Player, current_date: NaiveDate) -> bool {
    let Some(state) = player.morale_core.renewal_state.as_ref() else {
        return false;
    };

    if state.status != RenewalSessionStatus::Blocked {
        return false;
    }

    let Some(blocked_until) = state.manager_blocked_until.as_deref() else {
        return true;
    };

    NaiveDate::parse_from_str(blocked_until, "%Y-%m-%d")
        .map(|blocked_until| blocked_until >= current_date)
        .unwrap_or(true)
}

fn assistant_delegation_score(
    assistant: &domain::staff::Staff,
    player: &Player,
    current_date: NaiveDate,
) -> i32 {
    let assistant_quality = (i32::from(assistant.attributes.coaching) * 4
        + i32::from(assistant.attributes.judging_ability) * 3
        + i32::from(assistant.attributes.judging_potential) * 3)
        / 10;
    let trust_bonus = i32::from(player.morale_core.manager_trust) / 3;
    let morale_bonus = i32::from(player.morale) / 2;
    let urgency_bonus = match contract_warning_stage(player.contract_end.as_deref(), current_date) {
        Some(ContractWarningStage::FinalWeeks) => 18,
        Some(ContractWarningStage::ThreeMonths) => 14,
        Some(ContractWarningStage::SixMonths) => 10,
        Some(ContractWarningStage::TwelveMonths) => 6,
        None => 2,
    };
    let importance_penalty = if player.market_value >= 2_000_000 {
        22
    } else if player.market_value >= 750_000 {
        10
    } else {
        0
    };
    let issue_penalty = player
        .morale_core
        .unresolved_issue
        .as_ref()
        .map(|issue| i32::from(issue.severity) / 2)
        .unwrap_or(0);

    assistant_quality + trust_bonus + morale_bonus + urgency_bonus
        - importance_penalty
        - issue_penalty
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

fn delegated_note_params(entries: &[(&str, String)]) -> HashMap<String, String> {
    entries
        .iter()
        .map(|(key, value)| ((*key).to_string(), value.clone()))
        .collect()
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

fn delegated_renewal_report_message(
    team_id: &str,
    team_name: &str,
    date: &str,
    report: &DelegatedRenewalReport,
    id_suffix: usize,
) -> InboxMessage {
    InboxMessage::new(
        format!("delegated_renewals_{}_{}", date, id_suffix),
        "Assistant Report — Contract Renewals".to_string(),
        format!(
            "Boss, I went through our renewal list at {}. {} completed, {} still pending, {} failed.",
            team_name, report.success_count, report.stalled_count, report.failure_count
        ),
        "Assistant Manager".to_string(),
        date.to_string(),
    )
    .with_category(MessageCategory::Contract)
    .with_priority(MessagePriority::High)
    .with_sender_role("Assistant Manager")
    .with_i18n(
        "be.msg.delegatedRenewals.subject",
        "be.msg.delegatedRenewals.body",
        delegated_note_params(&[
            ("team", team_name.to_string()),
            ("successes", report.success_count.to_string()),
            ("stalled", report.stalled_count.to_string()),
            ("failures", report.failure_count.to_string()),
        ]),
    )
    .with_sender_i18n("be.sender.assistantManager", "be.role.assistantManager")
    .with_context(MessageContext {
        team_id: Some(team_id.to_string()),
        delegated_renewal_report: Some(DelegatedRenewalReportData {
            success_count: report.success_count,
            failure_count: report.failure_count,
            stalled_count: report.stalled_count,
            cases: report
                .cases
                .iter()
                .map(|case| DelegatedRenewalCaseMessageData {
                    player_id: case.player_id.clone(),
                    player_name: case.player_name.clone(),
                    status: match case.status {
                        DelegatedRenewalResultStatus::Successful => "successful".to_string(),
                        DelegatedRenewalResultStatus::Failed => "failed".to_string(),
                        DelegatedRenewalResultStatus::Stalled => "stalled".to_string(),
                    },
                    agreed_wage: case.agreed_wage,
                    agreed_years: case.agreed_years,
                    note_key: case.note_key.clone(),
                    note_params: case.note_params.clone(),
                })
                .collect(),
        }),
        ..Default::default()
    })
}
