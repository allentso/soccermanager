use crate::game::Game;
use domain::player::TransferOfferStatus;
use uuid::Uuid;

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

    let market_value = player.market_value;
    let is_transfer_listed = player.transfer_listed;

    // Check user team can afford it
    let my_team = game
        .teams
        .iter()
        .find(|t| t.id == user_team_id)
        .ok_or("User team not found")?;

    if (my_team.finance as u64) < fee {
        return Err("Insufficient funds".into());
    }

    // AI decision: accept if fee >= threshold
    // Transfer listed players accept at 80% of market value
    // Non-listed players need 120% of market value
    let threshold = if is_transfer_listed {
        (market_value as f64 * 0.8) as u64
    } else {
        (market_value as f64 * 1.2) as u64
    };

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
