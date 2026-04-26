use crate::game::Game;
use domain::manager::{Manager, ManagerCareerEntry};
use domain::staff::{Staff, StaffRole};
use std::collections::HashSet;

const BASE_AI_MANAGER_SATISFACTION: i32 = 50;

fn manager_seed_staff<'a>(staff: &'a [Staff], team_id: &str) -> Option<&'a Staff> {
    staff.iter()
        .filter(|member| member.team_id.as_deref() == Some(team_id))
        .find(|member| member.role == StaffRole::AssistantManager)
        .or_else(|| {
            staff.iter()
                .filter(|member| member.team_id.as_deref() == Some(team_id))
                .min_by(|left, right| left.id.cmp(&right.id))
        })
}

fn seeded_manager_id(team_id: &str, source_staff: &Staff) -> String {
    format!("mgr_{}_{}", team_id, source_staff.id)
}

fn create_seeded_manager(game: &Game, team_id: &str, source_staff: &Staff) -> Option<Manager> {
    let team = game.teams.iter().find(|team| team.id == team_id)?;
    let nationality = if source_staff.nationality.is_empty() {
        team.country.clone()
    } else {
        source_staff.nationality.clone()
    };

    let mut manager = Manager::new(
        seeded_manager_id(team_id, source_staff),
        source_staff.first_name.clone(),
        source_staff.last_name.clone(),
        source_staff.date_of_birth.clone(),
        nationality,
    );
    manager.reputation = team.reputation;
    manager.satisfaction = BASE_AI_MANAGER_SATISFACTION as u8;
    manager.fan_approval = 50;
    manager.hire(team.id.clone());
    manager.career_history.push(ManagerCareerEntry {
        team_id: team.id.clone(),
        team_name: team.name.clone(),
        start_date: game.clock.current_date.format("%Y-%m-%d").to_string(),
        end_date: None,
        matches: 0,
        wins: 0,
        draws: 0,
        losses: 0,
        best_league_position: None,
    });
    Some(manager)
}

fn ai_manager_satisfaction(form: &[String]) -> u8 {
    let mut satisfaction = BASE_AI_MANAGER_SATISFACTION;

    for result in form {
        match result.as_str() {
            "W" => satisfaction += 8,
            "D" => satisfaction += 1,
            "L" => satisfaction -= 12,
            _ => {}
        }
    }

    if form.iter().rev().take(4).count() == 4 && form.iter().rev().take(4).all(|result| result == "L") {
        satisfaction -= 12;
    }

    satisfaction.clamp(0, 100) as u8
}

pub fn seed_ai_managers(game: &mut Game) {
    if game.manager_id.is_empty() {
        game.manager_id = game.manager.id.clone();
    }
    game.sync_user_manager_record();

    let user_team_id = game.manager.team_id.clone();
    let existing_manager_ids: HashSet<String> = game.managers.iter().map(|manager| manager.id.clone()).collect();

    let team_ids_to_seed: Vec<String> = game
        .teams
        .iter()
        .filter(|team| Some(team.id.clone()) != user_team_id)
        .filter(|team| {
            team.manager_id
                .as_ref()
                .and_then(|manager_id| game.managers.iter().find(|manager| &manager.id == manager_id))
                .is_none()
        })
        .map(|team| team.id.clone())
        .collect();

    for team_id in team_ids_to_seed {
        let Some(source_staff) = manager_seed_staff(&game.staff, &team_id) else {
            continue;
        };
        let manager_id = seeded_manager_id(&team_id, source_staff);
        if existing_manager_ids.contains(&manager_id) {
            continue;
        }
        let Some(manager) = create_seeded_manager(game, &team_id, source_staff) else {
            continue;
        };
        if let Some(team) = game.teams.iter_mut().find(|team| team.id == team_id) {
            team.manager_id = Some(manager.id.clone());
        }
        game.managers.push(manager);
    }

    game.sync_user_manager_record();
}

pub fn update_ai_manager_satisfaction(game: &mut Game) {
    let user_manager_id = if game.manager_id.is_empty() {
        game.manager.id.clone()
    } else {
        game.manager_id.clone()
    };

    for manager in game.managers.iter_mut() {
        if manager.id == user_manager_id {
            continue;
        }

        let Some(team_id) = manager.team_id.clone() else {
            continue;
        };
        let Some(team) = game.teams.iter().find(|team| team.id == team_id) else {
            continue;
        };

        manager.satisfaction = ai_manager_satisfaction(&team.form);
    }
}

#[cfg(test)]
mod tests {
    use super::{seed_ai_managers, update_ai_manager_satisfaction};
    use crate::clock::GameClock;
    use crate::game::Game;
    use chrono::{TimeZone, Utc};
    use domain::manager::Manager;
    use domain::staff::{Staff, StaffAttributes, StaffRole};
    use domain::team::Team;

    fn make_team(id: &str, name: &str) -> Team {
        Team::new(
            id.to_string(),
            name.to_string(),
            name[..3].to_string(),
            "England".to_string(),
            "Testville".to_string(),
            "Test Ground".to_string(),
            20_000,
        )
    }

    fn make_staff(id: &str, team_id: &str, role: StaffRole, first_name: &str, last_name: &str) -> Staff {
        let mut staff = Staff::new(
            id.to_string(),
            first_name.to_string(),
            last_name.to_string(),
            "1980-01-01".to_string(),
            role,
            StaffAttributes {
                coaching: 60,
                judging_ability: 60,
                judging_potential: 60,
                physiotherapy: 20,
            },
        );
        staff.nationality = "England".to_string();
        staff.team_id = Some(team_id.to_string());
        staff
    }

    fn make_game() -> Game {
        let clock = GameClock::new(Utc.with_ymd_and_hms(2026, 7, 1, 12, 0, 0).unwrap());
        let mut manager = Manager::new(
            "mgr1".to_string(),
            "Alex".to_string(),
            "Boss".to_string(),
            "1980-01-01".to_string(),
            "England".to_string(),
        );
        manager.hire("team1".to_string());

        let mut user_team = make_team("team1", "Test FC");
        user_team.manager_id = Some("mgr1".to_string());
        let rival_team = make_team("team2", "Rival FC");

        Game::new(
            clock,
            manager,
            vec![user_team, rival_team],
            vec![],
            vec![
                make_staff("staff1", "team1", StaffRole::AssistantManager, "Amy", "Assistant"),
                make_staff("staff2", "team2", StaffRole::AssistantManager, "Marco", "Rossi"),
            ],
            vec![],
        )
    }

    #[test]
    fn seed_ai_managers_assigns_missing_manager_to_ai_club() {
        let mut game = make_game();

        seed_ai_managers(&mut game);

        let rival_team = game.teams.iter().find(|team| team.id == "team2").unwrap();
        assert!(rival_team.manager_id.is_some());
        assert_eq!(game.managers.len(), 2);
        assert!(game.managers.iter().any(|manager| {
            manager.team_id.as_deref() == Some("team2") && manager.full_name() == "Marco Rossi"
        }));
    }

    #[test]
    fn update_ai_manager_satisfaction_penalizes_heavy_losing_run() {
        let mut game = make_game();
        seed_ai_managers(&mut game);

        game.teams
            .iter_mut()
            .find(|team| team.id == "team2")
            .unwrap()
            .form = vec!["L".to_string(), "L".to_string(), "L".to_string(), "L".to_string()];

        update_ai_manager_satisfaction(&mut game);

        let rival_manager = game
            .managers
            .iter()
            .find(|manager| manager.team_id.as_deref() == Some("team2"))
            .unwrap();
        assert!(
            rival_manager.satisfaction <= 10,
            "Four straight defeats should push an AI manager into the firing zone"
        );
    }
}