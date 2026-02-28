use domain::player::{Player, PlayerAttributes, Position};
use domain::staff::{Staff, StaffRole, StaffAttributes};
use domain::team::{Team, TeamColors, PlayStyle};
use rand::Rng;
use uuid::Uuid;

const FIRST_NAMES: &[&str] = &[
    "John", "David", "Michael", "Chris", "James", "Robert", "Daniel", "Paul", "Mark", "Steven",
    "Tom", "Alex", "Sam", "Leo", "Marcus", "Kai", "Luca", "Pierre", "Marco", "Hugo",
    "Rui", "Lars", "Stefan", "Antoine", "Matteo", "Sergio", "Niko", "Jan", "Erik", "Raul",
];
const LAST_NAMES: &[&str] = &[
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Miller", "Davis", "Garcia",
    "Rodriguez", "Wilson", "Martinez", "Anderson", "Fernandez", "Müller", "Schmidt",
    "Rossi", "Bianchi", "Dubois", "Laurent", "De Jong", "Van Dijk", "Santos",
    "Costa", "Hernandez", "Fischer", "Moreno", "Romano", "Petit", "Berg", "Silva",
];
const NATIONALITIES: &[&str] = &[
    "English", "English", "Spanish", "German", "French", "Italian", "Dutch",
    "Portuguese", "Brazilian", "Argentine", "Colombian", "Belgian", "Swedish",
    "Norwegian", "Danish", "Croatian", "Serbian", "Swiss", "Austrian", "Scottish",
];
const TEAM_NAMES: &[&str] = &[
    "London FC",
    "Manchester United",
    "Madrid Blues",
    "Munich Red",
    "Paris Stars",
    "Rome Eagles",
    "Berlin City",
    "Amsterdam Ajax",
    "Lisbon Lions",
];
const CITY_NAMES: &[&str] = &[
    "London",
    "Manchester",
    "Madrid",
    "Munich",
    "Paris",
    "Rome",
    "Berlin",
    "Amsterdam",
    "Lisbon",
];
const COUNTRIES: &[&str] = &[
    "England",
    "England",
    "Spain",
    "Germany",
    "France",
    "Italy",
    "Germany",
    "Netherlands",
    "Portugal",
];

pub fn generate_world() -> (Vec<Team>, Vec<Player>, Vec<Staff>) {
    let mut rng = rand::thread_rng();
    let mut teams = Vec::new();
    let mut players = Vec::new();
    let mut staff = Vec::new();

    for i in 0..8 {
        let team_id = Uuid::new_v4().to_string();
        let name = TEAM_NAMES[i % TEAM_NAMES.len()].to_string();
        let short_name = name.chars().take(3).collect::<String>().to_uppercase();
        let city = CITY_NAMES[i % CITY_NAMES.len()].to_string();
        let country = COUNTRIES[i % COUNTRIES.len()].to_string();
        let stadium = format!("{} Arena", city);

        let mut team = Team::new(
            team_id.clone(),
            name,
            short_name,
            country,
            city,
            stadium,
            rng.gen_range(10000..80000),
        );
        // Vary team finances and reputation
        team.finance = rng.gen_range(500_000..10_000_000);
        team.reputation = rng.gen_range(300..900);
        team.wage_budget = (team.finance as f64 * 0.06) as i64;
        team.transfer_budget = (team.finance as f64 * 0.15) as i64;
        team.founded_year = rng.gen_range(1880..1960);
        let (pc, sc) = TEAM_COLORS_RAW[i % TEAM_COLORS_RAW.len()];
        team.colors = TeamColors { primary: pc.to_string(), secondary: sc.to_string() };
        team.play_style = play_style_from_str(PLAY_STYLES_RAW[i % PLAY_STYLES_RAW.len()]);
        teams.push(team);

        // Generate 20 players for the team
        for j in 0..20 {
            let mut player = generate_random_player(&team_id, j, &mut rng);
            // ~15% chance of being transfer listed, ~10% loan listed
            if rng.gen_range(0..100) < 15 {
                player.transfer_listed = true;
            } else if rng.gen_range(0..100) < 10 {
                player.loan_listed = true;
            }
            players.push(player);
        }

        // Generate 4 staff per team (1 of each role)
        let roles = [StaffRole::AssistantManager, StaffRole::Coach, StaffRole::Scout, StaffRole::Physio];
        for role in &roles {
            let s = generate_random_staff(&team_id, role.clone(), &mut rng);
            staff.push(s);
        }
    }

    // Generate 8 unattached staff (free agents)
    let free_roles = [
        StaffRole::Coach, StaffRole::Scout, StaffRole::Physio, StaffRole::Coach,
        StaffRole::AssistantManager, StaffRole::Scout, StaffRole::Physio, StaffRole::Coach,
    ];
    for role in &free_roles {
        let s = generate_random_staff_unattached(role.clone(), &mut rng);
        staff.push(s);
    }

    (teams, players, staff)
}

const TEAM_COLORS_RAW: &[(&str, &str)] = &[
    ("#dc2626", "#ffffff"),
    ("#b91c1c", "#fbbf24"),
    ("#1d4ed8", "#ffffff"),
    ("#dc2626", "#1e3a5f"),
    ("#1e3a5f", "#dc2626"),
    ("#eab308", "#7c2d12"),
    ("#2563eb", "#ffffff"),
    ("#dc2626", "#000000"),
];

const PLAY_STYLES_RAW: &[&str] = &[
    "Possession", "Counter", "Attacking", "HighPress",
    "Balanced", "Defensive", "Attacking", "Possession",
];

fn play_style_from_str(s: &str) -> PlayStyle {
    match s {
        "Attacking" => PlayStyle::Attacking,
        "Defensive" => PlayStyle::Defensive,
        "Possession" => PlayStyle::Possession,
        "Counter" => PlayStyle::Counter,
        "HighPress" => PlayStyle::HighPress,
        _ => PlayStyle::Balanced,
    }
}

fn generate_random_player(team_id: &str, index: usize, rng: &mut impl rand::RngCore) -> Player {
    let first_name = FIRST_NAMES[rng.gen_range(0..FIRST_NAMES.len())];
    let last_name = LAST_NAMES[rng.gen_range(0..LAST_NAMES.len())];
    let full_name = format!("{} {}", first_name, last_name);
    let match_name = last_name.to_string();

    // Distribute positions
    let position = if index < 2 {
        Position::Goalkeeper
    } else if index < 8 {
        Position::Defender
    } else if index < 14 {
        Position::Midfielder
    } else {
        Position::Forward
    };

    let p_id = Uuid::new_v4().to_string();
    let nationality = NATIONALITIES[rng.gen_range(0..NATIONALITIES.len())].to_string();

    // Generate realistic DOB (age 17-35)
    let age = rng.gen_range(17..36);
    let birth_year = 2026 - age;
    let birth_month = rng.gen_range(1..13);
    let birth_day = rng.gen_range(1..29);
    let dob = format!("{:04}-{:02}-{:02}", birth_year, birth_month, birth_day);

    let attributes = PlayerAttributes {
        pace: rng.gen_range(40..95),
        stamina: rng.gen_range(40..95),
        strength: rng.gen_range(40..95),
        passing: rng.gen_range(40..95),
        shooting: rng.gen_range(40..95),
        tackling: rng.gen_range(40..95),
        dribbling: rng.gen_range(40..95),
        defending: rng.gen_range(40..95),
        positioning: rng.gen_range(40..95),
        vision: rng.gen_range(40..95),
        decisions: rng.gen_range(40..95),
    };

    // Calculate OVR for market value estimation
    let ovr = (attributes.pace as u32 + attributes.stamina as u32 + attributes.strength as u32
        + attributes.passing as u32 + attributes.shooting as u32 + attributes.tackling as u32
        + attributes.dribbling as u32 + attributes.defending as u32
        + attributes.positioning as u32 + attributes.vision as u32 + attributes.decisions as u32) / 11;

    // Market value: age and OVR based (younger + higher OVR = more valuable)
    let age_factor = if age <= 23 { 1.5 } else if age <= 28 { 1.2 } else if age <= 32 { 0.8 } else { 0.4 };
    let base_value = (ovr as f64).powi(2) * 500.0;
    let market_value = (base_value * age_factor) as u64;

    // Wage roughly proportional to market value
    let wage = (market_value / 200).max(500) as u32;

    // Contract end: 1-4 years from now
    let contract_years = rng.gen_range(1..5);
    let contract_end = format!("{}-06-30", 2026 + contract_years);

    let mut player = Player::new(
        p_id,
        match_name,
        full_name,
        dob,
        nationality,
        position,
        attributes,
    );
    player.team_id = Some(team_id.to_string());
    player.market_value = market_value;
    player.wage = wage;
    player.contract_end = Some(contract_end);
    player.condition = rng.gen_range(75..100);
    player.morale = rng.gen_range(60..100);

    player
}

fn generate_random_staff(team_id: &str, role: StaffRole, rng: &mut impl rand::RngCore) -> Staff {
    let first_name = FIRST_NAMES[rng.gen_range(0..FIRST_NAMES.len())].to_string();
    let last_name = LAST_NAMES[rng.gen_range(0..LAST_NAMES.len())].to_string();
    let age = rng.gen_range(30..60);
    let birth_year = 2026 - age;
    let dob = format!("{:04}-{:02}-{:02}", birth_year, rng.gen_range(1..13), rng.gen_range(1..29));

    let attributes = match &role {
        StaffRole::AssistantManager => StaffAttributes {
            coaching: rng.gen_range(50..90),
            judging_ability: rng.gen_range(50..85),
            judging_potential: rng.gen_range(40..80),
            physiotherapy: rng.gen_range(20..50),
        },
        StaffRole::Coach => StaffAttributes {
            coaching: rng.gen_range(55..95),
            judging_ability: rng.gen_range(40..75),
            judging_potential: rng.gen_range(30..70),
            physiotherapy: rng.gen_range(20..45),
        },
        StaffRole::Scout => StaffAttributes {
            coaching: rng.gen_range(20..50),
            judging_ability: rng.gen_range(60..95),
            judging_potential: rng.gen_range(55..95),
            physiotherapy: rng.gen_range(10..30),
        },
        StaffRole::Physio => StaffAttributes {
            coaching: rng.gen_range(10..40),
            judging_ability: rng.gen_range(20..50),
            judging_potential: rng.gen_range(15..45),
            physiotherapy: rng.gen_range(60..95),
        },
    };

    let mut s = Staff::new(
        Uuid::new_v4().to_string(),
        first_name,
        last_name,
        dob,
        role,
        attributes,
    );
    s.team_id = Some(team_id.to_string());
    s
}

fn generate_random_staff_unattached(role: StaffRole, rng: &mut impl rand::RngCore) -> Staff {
    let first_name = FIRST_NAMES[rng.gen_range(0..FIRST_NAMES.len())].to_string();
    let last_name = LAST_NAMES[rng.gen_range(0..LAST_NAMES.len())].to_string();
    let age = rng.gen_range(28..55);
    let birth_year = 2026 - age;
    let dob = format!("{:04}-{:02}-{:02}", birth_year, rng.gen_range(1..13), rng.gen_range(1..29));

    let attributes = StaffAttributes {
        coaching: rng.gen_range(30..80),
        judging_ability: rng.gen_range(30..80),
        judging_potential: rng.gen_range(25..75),
        physiotherapy: rng.gen_range(25..75),
    };

    Staff::new(
        Uuid::new_v4().to_string(),
        first_name,
        last_name,
        dob,
        role,
        attributes,
    )
}
