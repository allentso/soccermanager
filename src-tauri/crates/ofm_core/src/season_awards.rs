use crate::game::Game;
use serde::{Deserialize, Serialize};

/// A single award entry (player + stat value).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AwardEntry {
    pub player_id: String,
    pub player_name: String,
    pub team_id: String,
    pub team_name: String,
    pub value: f64,
}

/// Season award standings — top 5 in each category.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SeasonAwards {
    pub golden_boot: Vec<AwardEntry>,      // Top scorers
    pub assist_king: Vec<AwardEntry>,      // Top assists
    pub player_of_year: Vec<AwardEntry>,   // Best avg rating (min 5 apps)
    pub clean_sheet_king: Vec<AwardEntry>, // Most clean sheets (GKs only)
    pub most_appearances: Vec<AwardEntry>,
    pub young_player: Vec<AwardEntry>, // Best avg rating, age <= 21
}

/// Compute current season award standings from player stats.
pub fn compute_season_awards(game: &Game) -> SeasonAwards {
    let current_date = game.clock.current_date;

    // Build entries for all players with at least 1 appearance
    let mut entries: Vec<(
        String,
        String,
        String,
        String,
        &domain::player::PlayerSeasonStats,
        i32,
    )> = Vec::new();
    for player in &game.players {
        if player.stats.appearances == 0 {
            continue;
        }
        let team_name = player
            .team_id
            .as_ref()
            .and_then(|tid| game.teams.iter().find(|t| &t.id == tid))
            .map(|t| t.name.clone())
            .unwrap_or_else(|| "Free Agent".to_string());
        let team_id = player.team_id.clone().unwrap_or_default();

        // Calculate age
        let age =
            if let Ok(dob) = chrono::NaiveDate::parse_from_str(&player.date_of_birth, "%Y-%m-%d") {
                let today = current_date.date_naive();
                let mut a = today.year() - dob.year();
                if today.ordinal() < dob.ordinal() {
                    a -= 1;
                }
                a
            } else {
                30
            };

        entries.push((
            player.id.clone(),
            player.match_name.clone(),
            team_id,
            team_name,
            &player.stats,
            age,
        ));
    }

    let top_n = |mut v: Vec<AwardEntry>| -> Vec<AwardEntry> {
        v.sort_by(|a, b| {
            b.value
                .partial_cmp(&a.value)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        v.truncate(5);
        v
    };

    // Golden Boot — top scorers
    let golden_boot = top_n(
        entries
            .iter()
            .filter(|(_, _, _, _, s, _)| s.goals > 0)
            .map(|(pid, pname, tid, tname, s, _)| AwardEntry {
                player_id: pid.clone(),
                player_name: pname.clone(),
                team_id: tid.clone(),
                team_name: tname.clone(),
                value: s.goals as f64,
            })
            .collect(),
    );

    // Assist King
    let assist_king = top_n(
        entries
            .iter()
            .filter(|(_, _, _, _, s, _)| s.assists > 0)
            .map(|(pid, pname, tid, tname, s, _)| AwardEntry {
                player_id: pid.clone(),
                player_name: pname.clone(),
                team_id: tid.clone(),
                team_name: tname.clone(),
                value: s.assists as f64,
            })
            .collect(),
    );

    // Player of the Year — best avg rating, min 5 appearances
    let player_of_year = top_n(
        entries
            .iter()
            .filter(|(_, _, _, _, s, _)| s.appearances >= 5 && s.avg_rating > 0.0)
            .map(|(pid, pname, tid, tname, s, _)| AwardEntry {
                player_id: pid.clone(),
                player_name: pname.clone(),
                team_id: tid.clone(),
                team_name: tname.clone(),
                value: s.avg_rating as f64,
            })
            .collect(),
    );

    // Clean Sheet King — GKs only
    let gk_ids: std::collections::HashSet<String> = game
        .players
        .iter()
        .filter(|p| p.position == domain::player::Position::Goalkeeper)
        .map(|p| p.id.clone())
        .collect();
    let clean_sheet_king = top_n(
        entries
            .iter()
            .filter(|(pid, _, _, _, s, _)| gk_ids.contains(pid) && s.clean_sheets > 0)
            .map(|(pid, pname, tid, tname, s, _)| AwardEntry {
                player_id: pid.clone(),
                player_name: pname.clone(),
                team_id: tid.clone(),
                team_name: tname.clone(),
                value: s.clean_sheets as f64,
            })
            .collect(),
    );

    // Most Appearances
    let most_appearances = top_n(
        entries
            .iter()
            .map(|(pid, pname, tid, tname, s, _)| AwardEntry {
                player_id: pid.clone(),
                player_name: pname.clone(),
                team_id: tid.clone(),
                team_name: tname.clone(),
                value: s.appearances as f64,
            })
            .collect(),
    );

    // Young Player of the Year — age <= 21, best avg rating, min 3 apps
    let young_player = top_n(
        entries
            .iter()
            .filter(|(_, _, _, _, s, age)| *age <= 21 && s.appearances >= 3 && s.avg_rating > 0.0)
            .map(|(pid, pname, tid, tname, s, _)| AwardEntry {
                player_id: pid.clone(),
                player_name: pname.clone(),
                team_id: tid.clone(),
                team_name: tname.clone(),
                value: s.avg_rating as f64,
            })
            .collect(),
    );

    SeasonAwards {
        golden_boot,
        assist_king,
        player_of_year,
        clean_sheet_king,
        most_appearances,
        young_player,
    }
}

use chrono::Datelike;
