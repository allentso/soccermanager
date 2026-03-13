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
    buyer_team: &domain::team::Team,
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

    let openness_score = player_move_openness_score(current_date, player, owner_team, buyer_team);
    if openness_score >= 60 {
        multiplier -= 0.20;
    } else if openness_score >= 40 {
        multiplier -= 0.10;
    }

    let multiplier = multiplier.clamp(0.55, 1.6);
    ((player.market_value as f64) * multiplier).round() as u64
}

fn player_move_openness_score(
    current_date: NaiveDate,
    player: &domain::player::Player,
    owner_team: &domain::team::Team,
    buyer_team: &domain::team::Team,
) -> i32 {
    let mut score = 0;

    if player.morale <= 45 {
        score += 20;
    } else if player.morale <= 60 {
        score += 10;
    }

    if player.stats.appearances <= 2 {
        score += 15;
    } else if player.stats.appearances <= 5 {
        score += 8;
    }

    if let Some(days_remaining) =
        contract_days_remaining(current_date, player.contract_end.as_deref())
    {
        if days_remaining <= 180 {
            score += 20;
        } else if days_remaining <= 365 {
            score += 10;
        }
    }

    let reputation_gap = buyer_team.reputation as i32 - owner_team.reputation as i32;
    if reputation_gap >= 200 {
        score += 25;
    } else if reputation_gap >= 75 {
        score += 15;
    }

    if player.transfer_listed {
        score += 10;
    }

    score
}

fn apply_blocked_move_consequences(player: &mut domain::player::Player, openness_score: i32) {
    if openness_score < 40 {
        return;
    }

    let morale_drop = if openness_score >= 60 { 10 } else { 6 };
    player.morale = (i16::from(player.morale) - morale_drop).clamp(0, 100) as u8;
    player.morale_core.manager_trust =
        (i16::from(player.morale_core.manager_trust) - 5).clamp(0, 100) as u8;
    player.morale_core.unresolved_issue = Some(domain::player::PlayerIssue {
        category: domain::player::PlayerIssueCategory::Contract,
        severity: if openness_score >= 60 { 75 } else { 60 },
    });
}

fn incoming_interest_score(current_date: NaiveDate, player: &domain::player::Player) -> i32 {
    let mut score = 0;

    if player.transfer_listed {
        score += 30;
    }

    if let Some(days_remaining) =
        contract_days_remaining(current_date, player.contract_end.as_deref())
    {
        if days_remaining <= 60 {
            score += 40;
        } else if days_remaining <= 180 {
            score += 25;
        } else if days_remaining <= 365 {
            score += 10;
        }
    }

    if player.market_value >= 1_000_000 {
        score += 20;
    } else if player.market_value >= 500_000 {
        score += 10;
    }

    if player.morale <= 45 {
        score += 10;
    }

    score
}

fn suggested_incoming_fee(current_date: NaiveDate, player: &domain::player::Player) -> u64 {
    let mut multiplier: f64 = if player.transfer_listed { 0.9 } else { 1.0 };

    if let Some(days_remaining) =
        contract_days_remaining(current_date, player.contract_end.as_deref())
    {
        if days_remaining <= 60 {
            multiplier -= 0.15;
        } else if days_remaining <= 180 {
            multiplier -= 0.1;
        }
    }

    if player.morale <= 45 {
        multiplier -= 0.05;
    }

    let multiplier = multiplier.clamp(0.7, 1.05);
    ((player.market_value as f64) * multiplier).round() as u64
}

fn has_open_incoming_offer_from_club(player: &domain::player::Player, club_id: &str) -> bool {
    player
        .transfer_offers
        .iter()
        .any(|offer| offer.from_team_id == club_id && offer.status == TransferOfferStatus::Pending)
}

pub fn generate_incoming_transfer_offers(game: &mut Game) {
    let Some(user_team_id) = game.manager.team_id.clone() else {
        return;
    };

    let current_date = game.clock.current_date.date_naive();
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();

    let buyer_ids: Vec<String> = game
        .teams
        .iter()
        .filter(|team| team.id != user_team_id)
        .map(|team| team.id.clone())
        .collect();

    for buyer_id in buyer_ids {
        let Some(buyer_team) = game.teams.iter().find(|team| team.id == buyer_id) else {
            continue;
        };

        let mut chosen_player_id: Option<String> = None;
        let mut chosen_score = i32::MIN;
        let mut chosen_fee = 0_u64;

        for player in &game.players {
            if player.team_id.as_deref() != Some(user_team_id.as_str()) {
                continue;
            }

            if has_open_incoming_offer_from_club(player, &buyer_id) {
                continue;
            }

            let score = incoming_interest_score(current_date, player);
            if score < 35 {
                continue;
            }

            let fee = suggested_incoming_fee(current_date, player);
            if buyer_team.transfer_budget < fee as i64 || buyer_team.finance < fee as i64 {
                continue;
            }

            if score > chosen_score {
                chosen_player_id = Some(player.id.clone());
                chosen_score = score;
                chosen_fee = fee;
            }
        }

        let Some(player_id) = chosen_player_id else {
            continue;
        };

        let Some(player) = game
            .players
            .iter_mut()
            .find(|player| player.id == player_id)
        else {
            continue;
        };

        let offer_id = Uuid::new_v4().to_string();

        player.transfer_offers.push(domain::player::TransferOffer {
            id: offer_id.clone(),
            from_team_id: buyer_id.clone(),
            fee: chosen_fee,
            wage_offered: 0,
            status: TransferOfferStatus::Pending,
            date: today.clone(),
        });

        let player_name = player.full_name.clone();
        let buyer_name = buyer_team.name.clone();
        let message = crate::messages::incoming_transfer_offer_message(
            &offer_id,
            &player_id,
            &player_name,
            &buyer_name,
            chosen_fee,
            &today,
        );
        game.messages.push(message);
    }
}

fn buyer_counter_offer_ceiling(
    current_date: NaiveDate,
    player: &domain::player::Player,
    current_offer_fee: u64,
    buyer_team: &domain::team::Team,
) -> u64 {
    let baseline_fee = suggested_incoming_fee(current_date, player).max(current_offer_fee);
    let ceiling = ((baseline_fee as f64) * 1.2).round() as u64;
    ceiling
        .min(buyer_team.transfer_budget.max(0) as u64)
        .min(buyer_team.finance.max(0) as u64)
}

fn should_generate_major_transfer_news(player: &domain::player::Player, fee: u64) -> bool {
    fee >= 1_000_000 || player.market_value >= 1_000_000
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

    let buyer_team = my_team;

    let current_date = game.clock.current_date.date_naive();

    let threshold = minimum_acceptable_fee(current_date, player, owner_team, buyer_team);

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
    let current_date = game.clock.current_date.date_naive();
    let owner_team = game
        .teams
        .iter()
        .find(|team| team.id == user_team_id)
        .ok_or("User team not found")?;
    let buyer_team = game
        .teams
        .iter()
        .find(|team| team.id == from_team_id)
        .ok_or("Buying team not found")?;
    let openness_score = player_move_openness_score(current_date, player, owner_team, buyer_team);

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
    } else if let Some(player) = game
        .players
        .iter_mut()
        .find(|player| player.id == player_id)
    {
        apply_blocked_move_consequences(player, openness_score);
    }

    Ok(())
}

pub fn counter_offer(
    game: &mut Game,
    player_id: &str,
    offer_id: &str,
    requested_fee: u64,
) -> Result<String, String> {
    let user_team_id = game.manager.team_id.clone().ok_or("No user team")?;

    let player = game
        .players
        .iter()
        .find(|p| p.id == player_id && p.team_id.as_deref() == Some(&user_team_id))
        .ok_or("Player not found or not yours")?;

    let offer = player
        .transfer_offers
        .iter()
        .find(|offer| offer.id == offer_id && offer.status == TransferOfferStatus::Pending)
        .ok_or("Offer not found or not pending")?;

    if requested_fee <= offer.fee {
        return Err("Counter offer must exceed current offer".into());
    }

    let buyer_team = game
        .teams
        .iter()
        .find(|team| team.id == offer.from_team_id)
        .ok_or("Buying team not found")?;

    let buyer_team_id = buyer_team.id.clone();
    let current_date = game.clock.current_date.date_naive();
    let counter_ceiling = buyer_counter_offer_ceiling(current_date, player, offer.fee, buyer_team);
    let accepted = requested_fee <= counter_ceiling;

    if let Some(player) = game
        .players
        .iter_mut()
        .find(|player| player.id == player_id)
        && let Some(offer) = player
            .transfer_offers
            .iter_mut()
            .find(|offer| offer.id == offer_id)
    {
        if accepted {
            offer.fee = requested_fee;
            offer.status = TransferOfferStatus::Accepted;
        } else {
            offer.status = TransferOfferStatus::Rejected;
        }
    }

    if accepted {
        execute_transfer(
            game,
            player_id,
            &buyer_team_id,
            &user_team_id,
            requested_fee,
        )?;
        return Ok("accepted".into());
    }

    Ok("rejected".into())
}

/// Transfer a player between teams, adjusting finances.
fn execute_transfer(
    game: &mut Game,
    player_id: &str,
    to_team_id: &str,
    from_team_id: &str,
    fee: u64,
) -> Result<(), String> {
    let player_snapshot = game
        .players
        .iter()
        .find(|player| player.id == player_id)
        .cloned()
        .ok_or("Player not found")?;
    let from_team_name = game
        .teams
        .iter()
        .find(|team| team.id == from_team_id)
        .map(|team| team.name.clone())
        .unwrap_or_else(|| from_team_id.to_string());
    let to_team_name = game
        .teams
        .iter()
        .find(|team| team.id == to_team_id)
        .map(|team| team.name.clone())
        .unwrap_or_else(|| to_team_id.to_string());
    let today = game.clock.current_date.format("%Y-%m-%d").to_string();
    let departing_starter_ids: Vec<String> = game
        .teams
        .iter()
        .find(|team| team.id == from_team_id)
        .filter(|team| team.starting_xi_ids.iter().any(|id| id == player_id))
        .map(|team| {
            team.starting_xi_ids
                .iter()
                .filter(|id| id.as_str() != player_id)
                .cloned()
                .collect()
        })
        .unwrap_or_default();

    // Move player
    if let Some(p) = game.players.iter_mut().find(|p| p.id == player_id) {
        p.team_id = Some(to_team_id.to_string());
        p.transfer_listed = false;
        p.loan_listed = false;
        // Remove from any starting XI
    }

    if !departing_starter_ids.is_empty() {
        for player in &mut game.players {
            if player.team_id.as_deref() == Some(from_team_id)
                && departing_starter_ids.iter().any(|id| id == &player.id)
            {
                player.morale = (i16::from(player.morale) - 4).clamp(0, 100) as u8;
            }
        }
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

    if should_generate_major_transfer_news(&player_snapshot, fee) {
        let article_id = format!(
            "transfer_news_{}_{}_{}_{}",
            player_id, from_team_id, to_team_id, today
        );
        if !game.news.iter().any(|article| article.id == article_id) {
            game.news.push(crate::news::major_transfer_article(
                &article_id,
                player_id,
                &player_snapshot.full_name,
                from_team_id,
                &from_team_name,
                to_team_id,
                &to_team_name,
                fee,
                &today,
            ));
        }
    }

    Ok(())
}
