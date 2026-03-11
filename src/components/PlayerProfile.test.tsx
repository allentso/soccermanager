import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import type { GameStateData, PlayerData, TeamData } from "../store/gameStore";
import PlayerProfile from "./PlayerProfile";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
}));

vi.mock("react-i18next", () => ({
  useTranslation: () => ({
    t: (key: string, params?: Record<string, string | number>) => {
      if (key === "common.back") return "Back";
      if (key === "common.contract") return "Contract";
      if (key === "common.condition") return "Condition";
      if (key === "common.morale") return "Morale";
      if (key === "common.value") return "Value";
      if (key === "common.wage") return "Wage";
      if (key === "common.age") return "Age";
      if (key === "common.freeAgent") return "Free Agent";
      if (key === "common.unknown") return "Unknown";
      if (key === "finances.perWeekSuffix") return "/wk";
      if (key === "finances.marketValue") return "Market Value";
      if (key === "finances.contractRiskCritical") return "Critical";
      if (key === "finances.contractRiskWarning") return "Warning";
      if (key === "finances.contractRiskStable") return "Stable";
      if (key === "finances.contractExpiresOn")
        return `Expires ${params?.date}`;
      if (key === "playerProfile.contractInfo") return "Contract Info";
      if (key === "playerProfile.dateOfBirth") return "Date of Birth";
      if (key === "playerProfile.weeklyWage") return "Weekly Wage";
      if (key === "playerProfile.noContract") return "No Contract";
      if (key === "playerProfile.yearsRemaining") return "Years Remaining";
      if (key === "playerProfile.contractRisk") return "Contract Risk";
      if (key === "playerProfile.attributes") return "Attributes";
      if (key === "playerProfile.seasonStats") return "Season Stats";
      if (key === "playerProfile.careerHistory") return "Career History";
      if (key === "playerProfile.noCareer") return "No Career";
      if (key === "finances.wagePerWeek") return "Wage/wk";
      return key;
    },
    i18n: { language: "en" },
  }),
}));

vi.mock("../lib/countries", () => ({
  countryMarker: () => "🏴",
  countryName: () => "England",
  isValidCountryCode: () => true,
  normaliseNationality: (value: string) => value,
}));

function createTeam(overrides: Partial<TeamData> = {}): TeamData {
  return {
    id: "team-1",
    name: "Alpha FC",
    short_name: "ALP",
    country: "GB",
    city: "London",
    stadium_name: "Alpha Ground",
    stadium_capacity: 30000,
    finance: 500000,
    manager_id: "manager-1",
    reputation: 50,
    wage_budget: 50000,
    transfer_budget: 250000,
    season_income: 0,
    season_expenses: 0,
    formation: "4-4-2",
    play_style: "Balanced",
    training_focus: "General",
    training_intensity: "Balanced",
    training_schedule: "Balanced",
    founded_year: 1900,
    colors: { primary: "#000000", secondary: "#ffffff" },
    starting_xi_ids: [],
    form: [],
    history: [],
    ...overrides,
  };
}

function createPlayer(overrides: Partial<PlayerData> = {}): PlayerData {
  return {
    id: "player-1",
    match_name: "J. Smith",
    full_name: "John Smith",
    date_of_birth: "2000-01-01",
    nationality: "GB",
    position: "Forward",
    natural_position: "Forward",
    alternate_positions: [],
    training_focus: null,
    attributes: {
      pace: 60,
      stamina: 60,
      strength: 60,
      agility: 60,
      passing: 60,
      shooting: 60,
      tackling: 60,
      dribbling: 60,
      defending: 60,
      positioning: 60,
      vision: 60,
      decisions: 60,
      composure: 60,
      aggression: 60,
      teamwork: 60,
      leadership: 60,
      handling: 20,
      reflexes: 20,
      aerial: 60,
    },
    condition: 80,
    morale: 75,
    injury: null,
    team_id: "team-1",
    contract_end: "2026-10-15",
    wage: 12000,
    market_value: 350000,
    stats: {
      appearances: 0,
      goals: 0,
      assists: 0,
      clean_sheets: 0,
      yellow_cards: 0,
      red_cards: 0,
      avg_rating: 0,
      minutes_played: 0,
    },
    career: [],
    transfer_listed: false,
    loan_listed: false,
    transfer_offers: [],
    traits: [],
    ...overrides,
  };
}

function createGameState(player: PlayerData): GameStateData {
  return {
    clock: {
      current_date: "2026-08-01T00:00:00Z",
      start_date: "2026-07-01T00:00:00Z",
    },
    manager: {
      id: "manager-1",
      first_name: "Jane",
      last_name: "Doe",
      date_of_birth: "1980-01-01",
      nationality: "GB",
      reputation: 50,
      satisfaction: 50,
      fan_approval: 50,
      team_id: "team-1",
      career_stats: {
        matches_managed: 0,
        wins: 0,
        draws: 0,
        losses: 0,
        trophies: 0,
        best_finish: null,
      },
      career_history: [],
    },
    teams: [createTeam()],
    players: [player],
    staff: [],
    messages: [],
    news: [],
    league: {
      id: "league-1",
      name: "League",
      season: 1,
      fixtures: [],
      standings: [],
    },
    scouting_assignments: [],
    board_objectives: [],
  };
}

describe("PlayerProfile contract surfaces", () => {
  it("renders expiry date, years remaining, and contract risk for the selected player", () => {
    const player = createPlayer();
    const gameState = createGameState(player);

    render(
      <PlayerProfile
        player={player}
        gameState={gameState}
        isOwnClub
        onClose={vi.fn()}
      />,
    );

    expect(screen.getByText("Contract Info")).toBeInTheDocument();
    expect(screen.getByText("Expires 2026-10-15")).toBeInTheDocument();
    expect(screen.getByText("Years Remaining")).toBeInTheDocument();
    expect(screen.getByText("Contract Risk")).toBeInTheDocument();
    expect(screen.getByText("Critical")).toBeInTheDocument();
    expect(screen.getAllByText("€12,000/wk").length).toBeGreaterThan(0);
  });
});
