use domain::player::{Player, PlayerAttributes, Position};
use domain::staff::{Staff, StaffAttributes, StaffRole};
use domain::team::{PlayStyle, Team, TeamColors};
use log::{debug, info};
use rand::Rng;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Definition file types (JSON-serialisable)
// ---------------------------------------------------------------------------

/// Name pools definition file format.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NamesDefinition {
    #[serde(default)]
    pub version: u32,
    #[serde(default)]
    pub description: String,
    /// Keyed by ISO 3166-1 alpha-2 country code.
    pub pools: HashMap<String, NamePool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NamePool {
    pub first_names: Vec<String>,
    pub last_names: Vec<String>,
}

/// Team templates definition file format.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TeamsDefinition {
    #[serde(default)]
    pub version: u32,
    #[serde(default)]
    pub description: String,
    pub teams: Vec<TeamDef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TeamDef {
    pub name: String,
    #[serde(default)]
    pub short_name: String,
    pub city: String,
    /// ISO 3166-1 alpha-2 country code.
    pub country: String,
    pub colors: TeamColorsDef,
    #[serde(default = "default_play_style")]
    pub play_style: String,
    #[serde(default)]
    pub stadium_name: String,
    #[serde(default)]
    pub reputation_range: Option<[u32; 2]>,
    #[serde(default)]
    pub finance_range: Option<[i64; 2]>,
}

fn default_play_style() -> String {
    "Balanced".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TeamColorsDef {
    pub primary: String,
    pub secondary: String,
}

/// Try to load a names definition from a file, returning None on any error.
pub fn load_names_definition(path: &std::path::Path) -> Option<NamesDefinition> {
    let contents = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&contents).ok()
}

/// Try to load a teams definition from a file, returning None on any error.
pub fn load_teams_definition(path: &std::path::Path) -> Option<TeamsDefinition> {
    let contents = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&contents).ok()
}

/// Build the hardcoded names definition as fallback.
fn default_names_definition() -> NamesDefinition {
    let mut pools = HashMap::new();
    for entry in NATIONALITY_POOLS {
        pools.insert(
            entry.nationality.to_string(),
            NamePool {
                first_names: entry.first_names.iter().map(|s| s.to_string()).collect(),
                last_names: entry.last_names.iter().map(|s| s.to_string()).collect(),
            },
        );
    }
    NamesDefinition {
        version: 1,
        description: "Built-in default".to_string(),
        pools,
    }
}

/// Build the hardcoded teams definition as fallback.
fn default_teams_definition() -> TeamsDefinition {
    TeamsDefinition {
        version: 1,
        description: "Built-in default".to_string(),
        teams: TEAM_TEMPLATES
            .iter()
            .map(|t| TeamDef {
                name: t.name.to_string(),
                short_name: t
                    .name
                    .split_whitespace()
                    .filter_map(|w| w.chars().next())
                    .collect::<String>()
                    .to_uppercase()
                    .chars()
                    .take(3)
                    .collect(),
                city: t.city.to_string(),
                country: t.country.to_string(),
                colors: TeamColorsDef {
                    primary: t.colors.0.to_string(),
                    secondary: t.colors.1.to_string(),
                },
                play_style: t.play_style.to_string(),
                stadium_name: format!("{} Arena", t.city),
                reputation_range: Some([300, 900]),
                finance_range: Some([500_000, 10_000_000]),
            })
            .collect(),
    }
}

/// Serialisable world database — can be saved to / loaded from JSON.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorldData {
    pub name: String,
    pub description: String,
    pub teams: Vec<Team>,
    pub players: Vec<Player>,
    pub staff: Vec<Staff>,
}

/// Lightweight metadata shown in the UI when listing available databases.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorldDatabaseInfo {
    pub id: String,
    pub name: String,
    pub description: String,
    pub team_count: usize,
    pub player_count: usize,
    /// "builtin" | "user"
    pub source: String,
    /// Filesystem path (empty for built-in random)
    pub path: String,
}

/// Generate a random world and wrap it in a `WorldData`.
/// If `data_dir` is provided, tries to load definition files from that directory.
pub fn generate_world_data(data_dir: Option<&std::path::Path>) -> WorldData {
    let (teams, players, staff) = generate_world(data_dir);
    WorldData {
        name: "Random World".to_string(),
        description: format!(
            "Randomly generated league with {} teams across Europe",
            teams.len()
        ),
        teams,
        players,
        staff,
    }
}

/// Parse a JSON string into a `WorldData`.
pub fn load_world_from_json(json: &str) -> Result<WorldData, String> {
    serde_json::from_str(json).map_err(|e| format!("Failed to parse world database: {}", e))
}

/// Serialise a `WorldData` to a pretty-printed JSON string.
pub fn export_world_to_json(world: &WorldData) -> Result<String, String> {
    serde_json::to_string_pretty(world).map_err(|e| format!("Failed to serialise world: {}", e))
}

/// Scan a directory for `.json` world database files and return their metadata.
pub fn scan_world_databases(dir: &std::path::Path) -> Vec<WorldDatabaseInfo> {
    let mut results = Vec::new();
    let Ok(entries) = std::fs::read_dir(dir) else {
        return results;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let Ok(contents) = std::fs::read_to_string(&path) else {
            continue;
        };
        // Parse just enough to get metadata — try full parse
        if let Ok(world) = serde_json::from_str::<WorldData>(&contents) {
            let file_stem = path
                .file_stem()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string();
            results.push(WorldDatabaseInfo {
                id: format!("file:{}", path.display()),
                name: world.name,
                description: world.description,
                team_count: world.teams.len(),
                player_count: world.players.len(),
                source: "user".to_string(),
                path: path.to_string_lossy().to_string(),
            });
            // suppress unused variable warning
            let _ = file_stem;
        }
    }
    results
}

// ---------------------------------------------------------------------------
// Nationality-aware name pools
// ---------------------------------------------------------------------------

struct NationalityNames {
    nationality: &'static str,
    first_names: &'static [&'static str],
    last_names: &'static [&'static str],
}

const NATIONALITY_POOLS: &[NationalityNames] = &[
    NationalityNames {
        nationality: "GB",
        first_names: &[
            "James", "Harry", "Jack", "Oliver", "George", "Charlie", "Thomas", "William", "Daniel",
            "Ben", "Luke", "Ryan", "Joe", "Sam", "Callum", "Nathan", "Ross", "Adam", "Liam",
            "Marcus",
        ],
        last_names: &[
            "Smith", "Johnson", "Williams", "Brown", "Jones", "Taylor", "Wilson", "Davies",
            "Evans", "Walker", "Robinson", "Clark", "Wright", "Hall", "Green", "Baker", "Hill",
            "Allen", "Young", "King",
        ],
    },
    NationalityNames {
        nationality: "ES",
        first_names: &[
            "Sergio",
            "Pablo",
            "Alejandro",
            "Carlos",
            "Javier",
            "Miguel",
            "Raul",
            "David",
            "Andres",
            "Alvaro",
            "Hugo",
            "Iker",
            "Marcos",
            "Luis",
            "Pedro",
            "Adrian",
            "Diego",
            "Fernando",
            "Gonzalo",
            "Antonio",
        ],
        last_names: &[
            "Garcia",
            "Rodriguez",
            "Martinez",
            "Lopez",
            "Sanchez",
            "Fernandez",
            "Gonzalez",
            "Hernandez",
            "Moreno",
            "Ruiz",
            "Diaz",
            "Alvarez",
            "Romero",
            "Torres",
            "Navarro",
            "Gil",
            "Vega",
            "Ramos",
            "Ortiz",
            "Castro",
        ],
    },
    NationalityNames {
        nationality: "DE",
        first_names: &[
            "Lukas",
            "Niklas",
            "Leon",
            "Felix",
            "Maximilian",
            "Jonas",
            "Florian",
            "Julian",
            "Tim",
            "Jan",
            "Kevin",
            "Marco",
            "Kai",
            "Stefan",
            "Patrick",
            "Dennis",
            "Tobias",
            "Marcel",
            "Timo",
            "Lars",
        ],
        last_names: &[
            "Müller",
            "Schmidt",
            "Schneider",
            "Fischer",
            "Weber",
            "Meyer",
            "Wagner",
            "Becker",
            "Schulz",
            "Hoffmann",
            "Koch",
            "Richter",
            "Wolf",
            "Schäfer",
            "Neumann",
            "Schwarz",
            "Zimmermann",
            "Braun",
            "Hartmann",
            "Krüger",
        ],
    },
    NationalityNames {
        nationality: "FR",
        first_names: &[
            "Antoine",
            "Hugo",
            "Lucas",
            "Mathieu",
            "Julien",
            "Maxime",
            "Pierre",
            "Thomas",
            "Raphael",
            "Adrien",
            "Kevin",
            "Alexandre",
            "Nicolas",
            "Loic",
            "Clement",
            "Florian",
            "Theo",
            "Damien",
            "Yann",
            "Baptiste",
        ],
        last_names: &[
            "Martin", "Bernard", "Dubois", "Thomas", "Robert", "Petit", "Moreau", "Laurent",
            "Simon", "Michel", "Lefevre", "Leroy", "Roux", "David", "Bertrand", "Morel",
            "Fournier", "Girard", "Bonnet", "Dupont",
        ],
    },
    NationalityNames {
        nationality: "IT",
        first_names: &[
            "Marco",
            "Luca",
            "Andrea",
            "Matteo",
            "Alessandro",
            "Lorenzo",
            "Davide",
            "Simone",
            "Riccardo",
            "Federico",
            "Gianluca",
            "Stefano",
            "Fabio",
            "Roberto",
            "Nicola",
            "Salvatore",
            "Daniele",
            "Paolo",
            "Vincenzo",
            "Emanuele",
        ],
        last_names: &[
            "Rossi", "Russo", "Ferrari", "Esposito", "Bianchi", "Romano", "Colombo", "Ricci",
            "Marino", "Greco", "Bruno", "Gallo", "Conti", "De Luca", "Costa", "Mancini",
            "Barbieri", "Fontana", "Santoro", "Rinaldi",
        ],
    },
    NationalityNames {
        nationality: "NL",
        first_names: &[
            "Daan", "Sem", "Lars", "Tim", "Thomas", "Jesse", "Jordi", "Luuk", "Rick", "Bas",
            "Stijn", "Nick", "Davy", "Wesley", "Kevin", "Robin", "Sander", "Ruud", "Dennis",
            "Patrick",
        ],
        last_names: &[
            "De Jong",
            "Van Dijk",
            "Jansen",
            "De Vries",
            "Van den Berg",
            "Bakker",
            "Visser",
            "Smit",
            "Meijer",
            "De Boer",
            "Mulder",
            "Dekker",
            "Peters",
            "Hendriks",
            "Van Leeuwen",
            "De Graaf",
            "Kok",
            "Brouwer",
            "Vermeer",
            "Van Dam",
        ],
    },
    NationalityNames {
        nationality: "PT",
        first_names: &[
            "Rui", "Joao", "Bruno", "Diogo", "Pedro", "Tiago", "Nuno", "Miguel", "Andre",
            "Goncalo", "Rafael", "Luis", "Ricardo", "Hugo", "Fabio", "Bernardo", "Daniel", "Vitor",
            "Nelson", "Sergio",
        ],
        last_names: &[
            "Silva",
            "Santos",
            "Ferreira",
            "Costa",
            "Pereira",
            "Oliveira",
            "Rodrigues",
            "Martins",
            "Sousa",
            "Fernandes",
            "Goncalves",
            "Lopes",
            "Almeida",
            "Carvalho",
            "Ribeiro",
            "Pinto",
            "Teixeira",
            "Mendes",
            "Neves",
            "Vieira",
        ],
    },
    NationalityNames {
        nationality: "BR",
        first_names: &[
            "Lucas",
            "Gabriel",
            "Rafael",
            "Matheus",
            "Guilherme",
            "Felipe",
            "Thiago",
            "Vinicius",
            "Pedro",
            "Gustavo",
            "Bruno",
            "Leonardo",
            "Anderson",
            "Douglas",
            "Eduardo",
            "Henrique",
            "Marcelo",
            "Diego",
            "Igor",
            "Leandro",
        ],
        last_names: &[
            "Silva",
            "Santos",
            "Oliveira",
            "Souza",
            "Pereira",
            "Costa",
            "Ferreira",
            "Rodrigues",
            "Almeida",
            "Nascimento",
            "Lima",
            "Araujo",
            "Ribeiro",
            "Carvalho",
            "Gomes",
            "Martins",
            "Rocha",
            "Mendes",
            "Barbosa",
            "Moreira",
        ],
    },
    NationalityNames {
        nationality: "AR",
        first_names: &[
            "Lionel", "Gonzalo", "Angel", "Sergio", "Nicolas", "Pablo", "Mauro", "Lucas",
            "Ezequiel", "Javier", "Marcos", "Leandro", "Federico", "Ignacio", "Rodrigo", "Matias",
            "Franco", "Agustin", "Julian", "Cristian",
        ],
        last_names: &[
            "Gonzalez",
            "Rodriguez",
            "Martinez",
            "Lopez",
            "Fernandez",
            "Garcia",
            "Romero",
            "Diaz",
            "Torres",
            "Sanchez",
            "Alvarez",
            "Acosta",
            "Gutierrez",
            "Castro",
            "Pereyra",
            "Aguero",
            "Ruiz",
            "Herrera",
            "Medina",
            "Flores",
        ],
    },
    NationalityNames {
        nationality: "BE",
        first_names: &[
            "Kevin", "Eden", "Romelu", "Dries", "Yannick", "Thomas", "Axel", "Thorgan", "Michy",
            "Nacer", "Radja", "Jan", "Toby", "Simon", "Leander", "Jason", "Timothy", "Hans",
            "Dennis", "Laurent",
        ],
        last_names: &[
            "Janssens", "Peeters", "Maes", "Jacobs", "Mertens", "Willems", "Claes", "Goossens",
            "Wouters", "De Smet", "Hermans", "Peters", "Stevens", "Leclercq", "Lambert", "Dupont",
            "Dumont", "Simon", "Laurent", "Renard",
        ],
    },
    NationalityNames {
        nationality: "HR",
        first_names: &[
            "Luka", "Ivan", "Mateo", "Mario", "Dejan", "Ante", "Josip", "Marko", "Nikola",
            "Marcelo", "Andrej", "Darijo", "Sime", "Borna", "Domagoj", "Vedran", "Duje", "Filip",
            "Tin", "Bruno",
        ],
        last_names: &[
            "Kovacic",
            "Horvat",
            "Babic",
            "Maric",
            "Juric",
            "Novak",
            "Perisic",
            "Tomic",
            "Vucinic",
            "Brozovic",
            "Kramaric",
            "Vidovic",
            "Lovren",
            "Srna",
            "Rakitic",
            "Modric",
            "Pasalic",
            "Rebic",
            "Livakovic",
            "Gvardiol",
        ],
    },
    NationalityNames {
        nationality: "SE",
        first_names: &[
            "Emil",
            "Oscar",
            "Viktor",
            "Erik",
            "Alexander",
            "Marcus",
            "Sebastian",
            "Filip",
            "Albin",
            "Robin",
            "Pontus",
            "Mattias",
            "Andreas",
            "Gustav",
            "Kristoffer",
            "Joel",
            "Ludwig",
            "Simon",
            "Martin",
            "Henrik",
        ],
        last_names: &[
            "Andersson",
            "Johansson",
            "Karlsson",
            "Nilsson",
            "Eriksson",
            "Larsson",
            "Olsson",
            "Persson",
            "Svensson",
            "Gustafsson",
            "Pettersson",
            "Jonsson",
            "Jansson",
            "Hansson",
            "Bengtsson",
            "Lindberg",
            "Lundqvist",
            "Forsberg",
            "Lindqvist",
            "Berg",
        ],
    },
];

// ---------------------------------------------------------------------------
// Team data — 16 teams across multiple countries
// ---------------------------------------------------------------------------

struct TeamTemplate {
    name: &'static str,
    city: &'static str,
    country: &'static str,
    colors: (&'static str, &'static str),
    play_style: &'static str,
}

const TEAM_TEMPLATES: &[TeamTemplate] = &[
    TeamTemplate {
        name: "London FC",
        city: "London",
        country: "England",
        colors: ("#dc2626", "#ffffff"),
        play_style: "Possession",
    },
    TeamTemplate {
        name: "Manchester City",
        city: "Manchester",
        country: "England",
        colors: ("#60a5fa", "#1e3a5f"),
        play_style: "Attacking",
    },
    TeamTemplate {
        name: "Liverpool Athletic",
        city: "Liverpool",
        country: "England",
        colors: ("#b91c1c", "#fbbf24"),
        play_style: "HighPress",
    },
    TeamTemplate {
        name: "Newcastle Town",
        city: "Newcastle",
        country: "England",
        colors: ("#000000", "#ffffff"),
        play_style: "Counter",
    },
    TeamTemplate {
        name: "Madrid Real",
        city: "Madrid",
        country: "Spain",
        colors: ("#ffffff", "#d4af37"),
        play_style: "Possession",
    },
    TeamTemplate {
        name: "Barcelona FC",
        city: "Barcelona",
        country: "Spain",
        colors: ("#9f1239", "#1d4ed8"),
        play_style: "Attacking",
    },
    TeamTemplate {
        name: "Munich Bayern",
        city: "Munich",
        country: "Germany",
        colors: ("#dc2626", "#1e3a5f"),
        play_style: "HighPress",
    },
    TeamTemplate {
        name: "Dortmund BV",
        city: "Dortmund",
        country: "Germany",
        colors: ("#eab308", "#000000"),
        play_style: "Counter",
    },
    TeamTemplate {
        name: "Paris Étoile",
        city: "Paris",
        country: "France",
        colors: ("#1e3a5f", "#dc2626"),
        play_style: "Attacking",
    },
    TeamTemplate {
        name: "Lyon Olympique",
        city: "Lyon",
        country: "France",
        colors: ("#1d4ed8", "#ffffff"),
        play_style: "Balanced",
    },
    TeamTemplate {
        name: "Milan Rossoneri",
        city: "Milan",
        country: "Italy",
        colors: ("#dc2626", "#000000"),
        play_style: "Defensive",
    },
    TeamTemplate {
        name: "Rome Gladiators",
        city: "Rome",
        country: "Italy",
        colors: ("#eab308", "#7c2d12"),
        play_style: "Counter",
    },
    TeamTemplate {
        name: "Amsterdam United",
        city: "Amsterdam",
        country: "Netherlands",
        colors: ("#dc2626", "#ffffff"),
        play_style: "Attacking",
    },
    TeamTemplate {
        name: "Lisbon Sporting",
        city: "Lisbon",
        country: "Portugal",
        colors: ("#16a34a", "#ffffff"),
        play_style: "Possession",
    },
    TeamTemplate {
        name: "Porto Dragões",
        city: "Porto",
        country: "Portugal",
        colors: ("#1d4ed8", "#ffffff"),
        play_style: "Defensive",
    },
    TeamTemplate {
        name: "Brussels Royal",
        city: "Brussels",
        country: "Belgium",
        colors: ("#7c3aed", "#fbbf24"),
        play_style: "Balanced",
    },
];

/// Generate a random world (raw tuple — used by `generate_world_data`).
/// Loads definition files from `data_dir` if provided; falls back to hardcoded defaults.
pub fn generate_world(data_dir: Option<&std::path::Path>) -> (Vec<Team>, Vec<Player>, Vec<Staff>) {
    info!("[generator] generate_world: data_dir={:?}", data_dir);
    let mut rng = rand::thread_rng();
    let mut teams_out = Vec::new();
    let mut players = Vec::new();
    let mut staff = Vec::new();

    // Load definitions (external file → hardcoded fallback)
    let names_def = data_dir
        .and_then(|dir| {
            let path = dir.join("default_names.json");
            let result = load_names_definition(&path);
            if result.is_some() {
                info!("[generator] loaded names from {:?}", path);
            } else {
                debug!("[generator] no names file at {:?}, using defaults", path);
            }
            result
        })
        .unwrap_or_else(default_names_definition);
    let teams_def = data_dir
        .and_then(|dir| {
            let path = dir.join("default_teams.json");
            let result = load_teams_definition(&path);
            if result.is_some() {
                info!("[generator] loaded teams from {:?}", path);
            } else {
                debug!("[generator] no teams file at {:?}, using defaults", path);
            }
            result
        })
        .unwrap_or_else(default_teams_definition);

    let country_codes: Vec<String> = names_def.pools.keys().cloned().collect();

    for tdef in &teams_def.teams {
        let team_id = Uuid::new_v4().to_string();
        let short_name = if tdef.short_name.is_empty() {
            tdef.name
                .split_whitespace()
                .filter_map(|w| w.chars().next())
                .collect::<String>()
                .to_uppercase()
                .chars()
                .take(3)
                .collect()
        } else {
            tdef.short_name.clone()
        };
        let stadium = if tdef.stadium_name.is_empty() {
            format!("{} Arena", tdef.city)
        } else {
            tdef.stadium_name.clone()
        };

        let rep_range = tdef.reputation_range.unwrap_or([300, 900]);
        let fin_range = tdef.finance_range.unwrap_or([500_000, 10_000_000]);

        let mut team = Team::new(
            team_id.clone(),
            tdef.name.clone(),
            short_name,
            tdef.country.clone(),
            tdef.city.clone(),
            stadium,
            rng.gen_range(10000..80000),
        );
        team.finance = rng.gen_range(fin_range[0]..fin_range[1]);
        team.reputation = rng.gen_range(rep_range[0]..rep_range[1]);
        team.wage_budget = (team.finance as f64 * 0.06) as i64;
        team.transfer_budget = (team.finance as f64 * 0.15) as i64;
        team.founded_year = rng.gen_range(1880..1960);
        team.colors = TeamColors {
            primary: tdef.colors.primary.clone(),
            secondary: tdef.colors.secondary.clone(),
        };
        team.play_style = play_style_from_str(&tdef.play_style);
        teams_out.push(team);

        // Generate 22 players
        for j in 0..22 {
            let nationality = pick_nationality_from_def(&tdef.country, &country_codes, &mut rng);
            let mut player =
                generate_random_player_from_def(&team_id, j, &nationality, &names_def, &mut rng);
            if rng.gen_range(0..100) < 12 {
                player.transfer_listed = true;
            } else if rng.gen_range(0..100) < 8 {
                player.loan_listed = true;
            }
            players.push(player);
        }

        // Generate 4 staff per team
        let roles = [
            StaffRole::AssistantManager,
            StaffRole::Coach,
            StaffRole::Scout,
            StaffRole::Physio,
        ];
        for role in &roles {
            let nationality = pick_nationality_from_def(&tdef.country, &country_codes, &mut rng);
            let s = generate_random_staff_from_def(
                &team_id,
                role.clone(),
                &nationality,
                &names_def,
                &mut rng,
            );
            staff.push(s);
        }
    }

    // Generate free-agent staff
    let free_roles = [
        StaffRole::Coach,
        StaffRole::Scout,
        StaffRole::Physio,
        StaffRole::Coach,
        StaffRole::AssistantManager,
        StaffRole::Scout,
        StaffRole::Physio,
        StaffRole::Coach,
        StaffRole::Coach,
        StaffRole::Physio,
        StaffRole::Scout,
        StaffRole::AssistantManager,
    ];
    for role in &free_roles {
        let nat = &country_codes[rng.gen_range(0..country_codes.len())];
        let s = generate_random_staff_unattached_from_def(role.clone(), nat, &names_def, &mut rng);
        staff.push(s);
    }

    info!(
        "[generator] world generated: {} teams, {} players, {} staff",
        teams_out.len(),
        players.len(),
        staff.len()
    );
    (teams_out, players, staff)
}

/// Pick a nationality code weighted 60% toward team country.
fn pick_nationality_from_def(
    team_country: &str,
    available_codes: &[String],
    rng: &mut impl rand::RngCore,
) -> String {
    // Map team country name → ISO code for the 60% local weight
    let local_code = country_to_iso(team_country);
    if rng.gen_range(0..100) < 60 {
        local_code.to_string()
    } else if available_codes.is_empty() {
        local_code.to_string()
    } else {
        available_codes[rng.gen_range(0..available_codes.len())].clone()
    }
}

/// Pick a name from the NamesDefinition for a given nationality code.
fn pick_name_from_def(
    nationality: &str,
    names_def: &NamesDefinition,
    rng: &mut impl rand::RngCore,
) -> (String, String) {
    if let Some(pool) = names_def.pools.get(nationality)
        && !pool.first_names.is_empty()
        && !pool.last_names.is_empty()
    {
        let first = pool.first_names[rng.gen_range(0..pool.first_names.len())].clone();
        let last = pool.last_names[rng.gen_range(0..pool.last_names.len())].clone();
        return (first, last);
    }
    // Fallback: pick from any available pool
    let keys: Vec<&String> = names_def.pools.keys().collect();
    if let Some(key) = keys.first() {
        let pool = &names_def.pools[*key];
        let first = pool.first_names[rng.gen_range(0..pool.first_names.len())].clone();
        let last = pool.last_names[rng.gen_range(0..pool.last_names.len())].clone();
        return (first, last);
    }
    ("Player".to_string(), "Unknown".to_string())
}

fn country_to_iso(country: &str) -> &str {
    match country {
        "England" | "GB" => "GB",
        "Spain" | "ES" => "ES",
        "Germany" | "DE" => "DE",
        "France" | "FR" => "FR",
        "Italy" | "IT" => "IT",
        "Netherlands" | "NL" => "NL",
        "Portugal" | "PT" => "PT",
        "Brazil" | "BR" => "BR",
        "Argentina" | "AR" => "AR",
        "Belgium" | "BE" => "BE",
        "Croatia" | "HR" => "HR",
        "Sweden" | "SE" => "SE",
        other => {
            // If already 2-letter code, return as-is
            if other.len() == 2 { other } else { "GB" }
        }
    }
}

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

fn generate_random_player_from_def(
    team_id: &str,
    index: usize,
    nationality: &str,
    names_def: &NamesDefinition,
    rng: &mut impl rand::RngCore,
) -> Player {
    let (first_name, last_name) = pick_name_from_def(nationality, names_def, rng);
    let full_name = format!("{} {}", first_name, last_name);
    let match_name = last_name.clone();

    // Distribute positions: GK:0-1, DEF:2-8, MID:9-15, FWD:16-21
    let position = if index < 2 {
        Position::Goalkeeper
    } else if index < 9 {
        Position::Defender
    } else if index < 16 {
        Position::Midfielder
    } else {
        Position::Forward
    };

    let p_id = Uuid::new_v4().to_string();
    let nationality = nationality.to_string();

    let age = rng.gen_range(17..36);
    let birth_year = 2026 - age;
    let birth_month = rng.gen_range(1..13);
    let birth_day = rng.gen_range(1..29);
    let dob = format!("{:04}-{:02}-{:02}", birth_year, birth_month, birth_day);

    let is_gk = matches!(position, Position::Goalkeeper);
    let is_def = matches!(position, Position::Defender);
    let is_fwd = matches!(position, Position::Forward);

    let attributes = PlayerAttributes {
        pace: rng.gen_range(40..95),
        stamina: rng.gen_range(40..95),
        strength: rng.gen_range(40..95),
        agility: rng.gen_range(40..95),
        passing: rng.gen_range(40..95),
        shooting: if is_gk {
            rng.gen_range(20..50)
        } else {
            rng.gen_range(40..95)
        },
        tackling: if is_gk || is_fwd {
            rng.gen_range(20..60)
        } else {
            rng.gen_range(40..95)
        },
        dribbling: if is_gk {
            rng.gen_range(20..50)
        } else {
            rng.gen_range(40..95)
        },
        defending: if is_gk {
            rng.gen_range(25..55)
        } else if is_def {
            rng.gen_range(55..95)
        } else {
            rng.gen_range(40..95)
        },
        positioning: rng.gen_range(40..95),
        vision: rng.gen_range(40..95),
        decisions: rng.gen_range(40..95),
        composure: rng.gen_range(40..95),
        aggression: rng.gen_range(30..90),
        teamwork: rng.gen_range(45..95),
        leadership: rng.gen_range(30..90),
        handling: if is_gk {
            rng.gen_range(50..95)
        } else {
            rng.gen_range(10..35)
        },
        reflexes: if is_gk {
            rng.gen_range(50..95)
        } else {
            rng.gen_range(20..50)
        },
        aerial: if is_gk {
            rng.gen_range(50..95)
        } else if is_def {
            rng.gen_range(45..90)
        } else {
            rng.gen_range(30..75)
        },
    };

    let ovr = (attributes.pace as u32
        + attributes.stamina as u32
        + attributes.strength as u32
        + attributes.passing as u32
        + attributes.shooting as u32
        + attributes.tackling as u32
        + attributes.dribbling as u32
        + attributes.defending as u32
        + attributes.positioning as u32
        + attributes.vision as u32
        + attributes.decisions as u32)
        / 11;

    let age_factor = if age <= 23 {
        1.5
    } else if age <= 28 {
        1.2
    } else if age <= 32 {
        0.8
    } else {
        0.4
    };
    let base_value = (ovr as f64).powi(2) * 500.0;
    let market_value = (base_value * age_factor) as u64;
    let wage = (market_value / 200).max(500) as u32;
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

fn generate_random_staff_from_def(
    team_id: &str,
    role: StaffRole,
    nationality: &str,
    names_def: &NamesDefinition,
    rng: &mut impl rand::RngCore,
) -> Staff {
    let (first_name, last_name) = pick_name_from_def(nationality, names_def, rng);
    let age = rng.gen_range(30..60);
    let birth_year = 2026 - age;
    let dob = format!(
        "{:04}-{:02}-{:02}",
        birth_year,
        rng.gen_range(1..13),
        rng.gen_range(1..29)
    );

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
    s.nationality = nationality.to_string();
    s.team_id = Some(team_id.to_string());
    s
}

fn generate_random_staff_unattached_from_def(
    role: StaffRole,
    nationality: &str,
    names_def: &NamesDefinition,
    rng: &mut impl rand::RngCore,
) -> Staff {
    let (first_name, last_name) = pick_name_from_def(nationality, names_def, rng);
    let age = rng.gen_range(28..55);
    let birth_year = 2026 - age;
    let dob = format!(
        "{:04}-{:02}-{:02}",
        birth_year,
        rng.gen_range(1..13),
        rng.gen_range(1..29)
    );

    let attributes = StaffAttributes {
        coaching: rng.gen_range(30..80),
        judging_ability: rng.gen_range(30..80),
        judging_potential: rng.gen_range(25..75),
        physiotherapy: rng.gen_range(25..75),
    };

    let mut s = Staff::new(
        Uuid::new_v4().to_string(),
        first_name,
        last_name,
        dob,
        role,
        attributes,
    );
    s.nationality = nationality.to_string();
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_world_team_count() {
        let (teams, players, staff) = generate_world(None);
        assert_eq!(teams.len(), 16);
        assert_eq!(players.len(), 16 * 22);
        assert_eq!(staff.len(), 16 * 4 + 12);
    }

    #[test]
    fn test_generate_world_all_players_assigned() {
        let (teams, players, _) = generate_world(None);
        let team_ids: Vec<&str> = teams.iter().map(|t| t.id.as_str()).collect();
        for p in &players {
            assert!(p.team_id.is_some(), "Player {} has no team", p.full_name);
            assert!(
                team_ids.contains(&p.team_id.as_deref().unwrap()),
                "Player has unknown team"
            );
        }
    }

    #[test]
    fn test_generate_world_positions_per_team() {
        let (teams, players, _) = generate_world(None);
        for team in &teams {
            let team_players: Vec<_> = players
                .iter()
                .filter(|p| p.team_id.as_deref() == Some(&team.id))
                .collect();
            assert_eq!(team_players.len(), 22);
            let gk = team_players
                .iter()
                .filter(|p| p.position == Position::Goalkeeper)
                .count();
            assert!(gk >= 2, "Team {} has only {} GK", team.name, gk);
        }
    }

    #[test]
    fn test_pick_name_from_def() {
        let mut rng = rand::thread_rng();
        let names_def = default_names_definition();
        // Known nationality (ISO alpha-2)
        let (first, last) = pick_name_from_def("ES", &names_def, &mut rng);
        assert!(!first.is_empty());
        assert!(!last.is_empty());
        // Unknown code falls back to any pool
        let (first2, last2) = pick_name_from_def("ZZ", &names_def, &mut rng);
        assert!(!first2.is_empty());
        assert!(!last2.is_empty());
    }

    #[test]
    fn test_pick_nationality_weighted() {
        let mut rng = rand::thread_rng();
        let codes: Vec<String> = NATIONALITY_POOLS
            .iter()
            .map(|p| p.nationality.to_string())
            .collect();
        let mut gb_count = 0;
        for _ in 0..100 {
            let nat = pick_nationality_from_def("England", &codes, &mut rng);
            if nat == "GB" {
                gb_count += 1;
            }
        }
        assert!(
            gb_count > 30,
            "GB players should be weighted: got {}/100",
            gb_count
        );
    }

    #[test]
    fn test_all_nationalities_are_iso_alpha2() {
        let (_, players, staff) = generate_world(None);
        for p in &players {
            assert_eq!(
                p.nationality.len(),
                2,
                "Player {} has non-ISO nationality: {}",
                p.full_name,
                p.nationality
            );
            assert!(
                p.nationality.chars().all(|c| c.is_ascii_uppercase()),
                "Player {} nationality not uppercase: {}",
                p.full_name,
                p.nationality
            );
        }
        for s in &staff {
            assert_eq!(
                s.nationality.len(),
                2,
                "Staff {} has non-ISO nationality: {}",
                s.first_name,
                s.nationality
            );
        }
    }

    #[test]
    fn test_team_templates_have_unique_names() {
        let names: Vec<&str> = TEAM_TEMPLATES.iter().map(|t| t.name).collect();
        let unique: std::collections::HashSet<&str> = names.iter().cloned().collect();
        assert_eq!(names.len(), unique.len(), "Duplicate team names found");
    }

    #[test]
    fn test_world_data_wrapper() {
        let world = generate_world_data(None);
        assert_eq!(world.teams.len(), 16);
        assert!(!world.name.is_empty());
        assert!(!world.description.is_empty());
    }

    #[test]
    fn test_definition_file_roundtrip() {
        let names_def = default_names_definition();
        let json = serde_json::to_string(&names_def).unwrap();
        let parsed: NamesDefinition = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.pools.len(), names_def.pools.len());

        let teams_def = default_teams_definition();
        let json2 = serde_json::to_string(&teams_def).unwrap();
        let parsed2: TeamsDefinition = serde_json::from_str(&json2).unwrap();
        assert_eq!(parsed2.teams.len(), teams_def.teams.len());
    }
}
