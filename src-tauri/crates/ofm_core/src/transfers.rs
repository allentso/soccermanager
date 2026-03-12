use crate::game::Game;
use chrono::NaiveDate;
use domain::player::TransferOfferStatus;
use uuid::Uuid;

enum PlayerImportance {
    Key,
    Regular,
    Fringe,
}

fn contract_days_remaining(current_date: NaiveDate, contract_end: Option<&str>) -> Option<i64> {
    let contract_end = contract_end?;
    let contract_end_date = NaiveDate::parse_from_str(contract_end, "%Y-%m-%d").ok()?;
    Some((contract_end_date - current_date).num_days())
}

fn infer_player_importance(
    player: &domain::player::Player,
    owner_team: &domain::team::Team,
) -> PlayerImportance {
    if owner_team.starting_xi_ids.iter().any(|id| id == &player.id) {
        return PlayerImportance::Key;
    }

    if player.market_value >= 1_500_000 {
        return PlayerImportance::Regular;
    }

    PlayerImportance::Fringe
}

fn minimum_acceptable_fee(
    current_date: NaiveDate,
    player: &domain::player::Player,
    owner_team: &domain::team::Team,
) -> u64 {
    let mut multiplier: f64 = if player.transfer_listed { 0.8 } else { 1.2 };

    if let Some(days_remaining) =
        contract_days_remaining(current_date, player.contract_end.as_deref())
    {
        if days_remaining <= 60 {
            multiplier -= 0.25;
        } else if days_remaining <= 180 {
            multiplier -= 0.15;
        } else if days_remaining <= 365 {
            multiplier -= 0.05;
        }
    }

    match infer_player_importance(player, owner_team) {
        PlayerImportance::Key => multiplier += 0.2,
        PlayerImportance::Regular => multiplier += 0.1,
        PlayerImportance::Fringe => {}
    }

    if player.morale <= 40 {
        multiplier -= 0.05;
    }

    let multiplier = multiplier.clamp(0.55, 1.6);
    ((player.market_value as f64) * multiplier).round() as u64
}

/// Submit a transfer bid from user's team for a player.
/// The AI evaluates the bid and accepts/rejects based on fee vs market value.
pub fn make_transfer_bid(game: &mut Game, player_id: &str, fee: u64) -> Result<String, String> {
    let user_team_id = game.manager.team_id.clone().ok_or("No user team")?;

    let player = game
        .players
        .iter()
        .find(|p| p.id == player_id)
        .ok_or("Player not found")?;

    if player.team_id.as_deref() == Some(&user_team_id) {
        return Err("Cannot bid on your own player".into());
    }

    let owner_team_id = player.team_id.clone().ok_or("Player has no team")?;

    let my_team = game
        .teams
        .iter()
        .find(|t| t.id == user_team_id)
        .ok_or("User team not found")?;

    if (my_team.finance as u64) < fee {
        return Err("Insufficient funds".into());
    }

    if my_team.transfer_budget < fee as i64 {
        return Err("Transfer budget too low".into());
    }

    let owner_team = game
        .teams
        .iter()
        .find(|t| t.id == owner_team_id)
        .ok_or("Owner team not found")?;

    let current_date = game.clock.current_date.date_naive();

    let threshold = minimum_acceptable_fee(current_date, player, owner_team);

    let offer_id = Uuid::new_v4().to_string();
    let date = game.clock.current_date.format("%Y-%m-%d").to_string();

    let status = if fee >= threshold {
        TransferOfferStatus::Accepted
    } else {
        TransferOfferStatus::Rejected
    };

    let offer = domain::player::TransferOffer {
        id: offer_id.clone(),
        from_team_id: user_team_id.clone(),
        fee,
        wage_offered: 0,
        status: status.clone(),
        date: date.clone(),
    };

    // Add offer to player
    if let Some(p) = game.players.iter_mut().find(|p| p.id == player_id) {
        p.transfer_offers.push(offer);
    }

    if status == TransferOfferStatus::Accepted {
        // Execute transfer
        execute_transfer(game, player_id, &user_team_id, &owner_team_id, fee)?;

        // Generate message
        let player_name = game
            .players
            .iter()
            .find(|p| p.id == player_id)
            .map(|p| p.full_name.clone())
            .unwrap_or_default();

        let msg = crate::messages::transfer_complete_message(&player_name, fee, &date);
        game.messages.push(msg);
    }

    Ok(if status == TransferOfferStatus::Accepted {
        "accepted".into()
    } else {
        "rejected".into()
    })
}

/// Respond to an incoming transfer offer on one of user's players.
pub fn respond_to_offer(
    game: &mut Game,
    player_id: &str,
    offer_id: &str,
    accept: bool,
) -> Result<(), String> {
    let user_team_id = game.manager.team_id.clone().ok_or("No user team")?;

    let player = game
        .players
        .iter()
        .find(|p| p.id == player_id && p.team_id.as_deref() == Some(&user_team_id))
        .ok_or("Player not found or not yours")?;

    let offer = player
        .transfer_offers
        .iter()
        .find(|o| o.id == offer_id && o.status == TransferOfferStatus::Pending)
        .ok_or("Offer not found or not pending")?;

    let from_team_id = offer.from_team_id.clone();
    let fee = offer.fee;

    // Update offer status
    if let Some(p) = game.players.iter_mut().find(|p| p.id == player_id)
        && let Some(o) = p.transfer_offers.iter_mut().find(|o| o.id == offer_id)
    {
        o.status = if accept {
            TransferOfferStatus::Accepted
        } else {
            TransferOfferStatus::Rejected
        };
    }

    if accept {
        execute_transfer(game, player_id, &from_team_id, &user_team_id, fee)?;
    }

    Ok(())
}

/// Transfer a player between teams, adjusting finances.
fn execute_transfer(
    game: &mut Game,
    player_id: &str,
    to_team_id: &str,
    from_team_id: &str,
    fee: u64,
) -> Result<(), String> {
    // Move player
    if let Some(p) = game.players.iter_mut().find(|p| p.id == player_id) {
        p.team_id = Some(to_team_id.to_string());
        p.transfer_listed = false;
        p.loan_listed = false;
        // Remove from any starting XI
    }

    // Debit buying team
    if let Some(t) = game.teams.iter_mut().find(|t| t.id == to_team_id) {
        t.finance -= fee as i64;
        // Remove from starting XI if player was there
        if let Some(pos) = t.starting_xi_ids.iter().position(|id| id == player_id) {
            t.starting_xi_ids.remove(pos);
        }
    }

    // Credit selling team
    if let Some(t) = game.teams.iter_mut().find(|t| t.id == from_team_id) {
        t.finance += fee as i64;
        // Remove from starting XI
        if let Some(pos) = t.starting_xi_ids.iter().position(|id| id == player_id) {
            t.starting_xi_ids.remove(pos);
        }
    }

    Ok(())
}
