use crate::game::Game;
use domain::player::Position as DomainPosition;
use engine::{PlayStyle, PlayerData, Position, TeamData};

// ---------------------------------------------------------------------------
// Domain → Engine conversion with starting XI / bench split
// ---------------------------------------------------------------------------

pub(super) fn build_team_with_bench(game: &Game, team_id: &str) -> (TeamData, Vec<PlayerData>) {
    let team = game.teams.iter().find(|t| t.id == team_id);
    let (name, formation, play_style) = match team {
        Some(t) => (
            t.name.clone(),
            t.formation.clone(),
            match t.play_style {
                domain::team::PlayStyle::Attacking => PlayStyle::Attacking,
                domain::team::PlayStyle::Defensive => PlayStyle::Defensive,
                domain::team::PlayStyle::Possession => PlayStyle::Possession,
                domain::team::PlayStyle::Counter => PlayStyle::Counter,
                domain::team::PlayStyle::HighPress => PlayStyle::HighPress,
                _ => PlayStyle::Balanced,
            },
        ),
        None => ("Unknown".into(), "4-4-2".into(), PlayStyle::Balanced),
    };

    // Collect all available (non-injured) players for this team
    let mut all_players: Vec<PlayerData> = game
        .players
        .iter()
        .filter(|p| p.team_id.as_deref() == Some(team_id) && p.injury.is_none())
        .map(to_engine_player)
        .collect();

    // Sort by position priority (GK, DEF, MID, FWD) then by overall desc
    all_players.sort_by(|a, b| {
        position_order(&a.position)
            .cmp(&position_order(&b.position))
            .then(
                b.overall()
                    .partial_cmp(&a.overall())
                    .unwrap_or(std::cmp::Ordering::Equal),
            )
    });

    // Pick starting XI based on formation
    let (gk_count, def_count, mid_count, fwd_count) = parse_formation(&formation);
    let mut starting_xi = Vec::with_capacity(11);
    let mut bench = Vec::new();

    let mut gk_picked = 0u8;
    let mut def_picked = 0u8;
    let mut mid_picked = 0u8;
    let mut fwd_picked = 0u8;

    for player in all_players {
        let needed = match player.position {
            Position::Goalkeeper => gk_picked < gk_count,
            Position::Defender => def_picked < def_count,
            Position::Midfielder => mid_picked < mid_count,
            Position::Forward => fwd_picked < fwd_count,
        };

        if needed && starting_xi.len() < 11 {
            match player.position {
                Position::Goalkeeper => gk_picked += 1,
                Position::Defender => def_picked += 1,
                Position::Midfielder => mid_picked += 1,
                Position::Forward => fwd_picked += 1,
            }
            starting_xi.push(player);
        } else {
            bench.push(player);
        }
    }

    let team_data = TeamData {
        id: team_id.to_string(),
        name,
        formation,
        play_style,
        players: starting_xi,
    };

    (team_data, bench)
}

fn to_engine_player(p: &domain::player::Player) -> PlayerData {
    let pos = match p.position {
        DomainPosition::Goalkeeper => Position::Goalkeeper,
        DomainPosition::Defender => Position::Defender,
        DomainPosition::Midfielder => Position::Midfielder,
        DomainPosition::Forward => Position::Forward,
    };
    PlayerData {
        id: p.id.clone(),
        name: p.match_name.clone(),
        position: pos,
        condition: p.condition,
        pace: p.attributes.pace,
        stamina: p.attributes.stamina,
        strength: p.attributes.strength,
        agility: p.attributes.agility,
        passing: p.attributes.passing,
        shooting: p.attributes.shooting,
        tackling: p.attributes.tackling,
        dribbling: p.attributes.dribbling,
        defending: p.attributes.defending,
        positioning: p.attributes.positioning,
        vision: p.attributes.vision,
        decisions: p.attributes.decisions,
        composure: p.attributes.composure,
        aggression: p.attributes.aggression,
        teamwork: p.attributes.teamwork,
        leadership: p.attributes.leadership,
        handling: p.attributes.handling,
        reflexes: p.attributes.reflexes,
        aerial: p.attributes.aerial,
        traits: p.traits.iter().map(|t| format!("{:?}", t)).collect(),
    }
}

/// Auto-select set-piece takers from a set of player IDs.
/// Returns (captain_id, penalty_taker_id, free_kick_taker_id, corner_taker_id).
pub fn auto_select_set_pieces(
    game: &Game,
    player_ids: &[String],
) -> (
    Option<String>,
    Option<String>,
    Option<String>,
    Option<String>,
) {
    let players: Vec<&domain::player::Player> = player_ids
        .iter()
        .filter_map(|id| game.players.iter().find(|p| &p.id == id))
        .collect();

    if players.is_empty() {
        return (None, None, None, None);
    }

    // Captain: highest leadership + teamwork
    let captain = players
        .iter()
        .max_by_key(|p| (p.attributes.leadership as u16) + (p.attributes.teamwork as u16))
        .map(|p| p.id.clone());

    // Penalty taker: highest shooting + composure (exclude GK)
    let penalty = players
        .iter()
        .filter(|p| p.position != DomainPosition::Goalkeeper)
        .max_by_key(|p| (p.attributes.shooting as u16) + (p.attributes.composure as u16))
        .map(|p| p.id.clone());

    // Free kick taker: highest passing + vision + shooting (exclude GK)
    let free_kick = players
        .iter()
        .filter(|p| p.position != DomainPosition::Goalkeeper)
        .max_by_key(|p| {
            (p.attributes.passing as u16)
                + (p.attributes.vision as u16)
                + (p.attributes.shooting as u16) / 2
        })
        .map(|p| p.id.clone());

    // Corner taker: highest passing + vision (exclude GK, prefer different from FK)
    let corner = players
        .iter()
        .filter(|p| p.position != DomainPosition::Goalkeeper)
        .max_by_key(|p| {
            let base = (p.attributes.passing as u16) + (p.attributes.vision as u16);
            // Small penalty if same as free kick taker to encourage variety
            if free_kick.as_ref() == Some(&p.id) {
                base.saturating_sub(5)
            } else {
                base
            }
        })
        .map(|p| p.id.clone());

    (captain, penalty, free_kick, corner)
}

fn position_order(pos: &Position) -> u8 {
    match pos {
        Position::Goalkeeper => 0,
        Position::Defender => 1,
        Position::Midfielder => 2,
        Position::Forward => 3,
    }
}

fn parse_formation(formation: &str) -> (u8, u8, u8, u8) {
    // Parse "4-4-2", "4-3-3", "3-5-2", etc.
    let parts: Vec<u8> = formation
        .split('-')
        .filter_map(|s| s.parse().ok())
        .collect();

    match parts.len() {
        3 => (1, parts[0], parts[1], parts[2]),
        4 => (parts[0], parts[1], parts[2], parts[3]),
        _ => (1, 4, 4, 2), // fallback 4-4-2
    }
}
