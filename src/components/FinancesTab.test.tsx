import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { GameStateData, PlayerData, TeamData } from "../store/gameStore";
import FinancesTab from "./FinancesTab";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
}));

vi.mock("react-i18next", () => ({
  useTranslation: () => ({
    t: (key: string, params?: Record<string, string | number>) => {
      if (key === "finances.facilities") return "Facilities";
      if (key === "finances.facilityTraining") return "Training Facility";
      if (key === "finances.facilityMedical") return "Medical Facility";
      if (key === "finances.facilityScouting") return "Scouting Facility";
      if (key === "finances.facilityLevel") return `Level ${params?.level}`;
      if (key === "finances.upgradeFacility") return "Upgrade";
      if (key === "finances.insufficientFunds") return "Insufficient funds";
      if (key === "finances.nextUpgradeCost")
        return `Next upgrade: €${params?.amount}`;
      if (key === "finances.facilityTrainingEffect")
        return "Improves training quality";
      if (key === "finances.facilityMedicalEffect") return "Improves recovery";
      if (key === "finances.facilityScoutingEffect")
        return "Improves scouting reports";
      if (key === "finances.overview") return "Overview";
      if (key === "finances.wageBill") return "Wage Bill";
      if (key === "finances.weeklyTotal") return "Weekly Total";
      if (key === "finances.budget") return "Budget";
      if (key === "finances.underBudget") return "Under budget";
      if (key === "finances.overBudget") return "Over budget";
      if (key === "finances.payroll") return "Payroll";
      if (key === "finances.squadValue") return "Squad Value";
      if (key === "finances.clubBalance") return "Club Balance";
      if (key === "finances.wageBudget") return "Wage Budget";
      if (key === "finances.transferBudget") return "Transfer Budget";
      if (key === "finances.seasonIncome") return "Season Income";
      if (key === "finances.seasonExpenses") return "Season Expenses";
      if (key === "finances.perWeekSuffix") return "/wk";
      if (key === "finances.wagePerWeek") return "Wage/wk";
      if (key === "finances.marketValue") return "Market Value";
      if (key === "finances.until") return `Until ${params?.year}`;
      if (key === "common.player") return "Player";
      if (key === "common.position") return "Position";
      if (key === "common.contract") return "Contract";
      if (key === "common.noTeam") return "No team";
      return key;
    },
    i18n: { language: "en" },
  }),
}));

const mockedInvoke = vi.mocked(invoke);

function createTeam(overrides: Partial<TeamData> = {}): TeamData {
  return {
    id: "team-1",
    name: "Alpha FC",
    short_name: "ALP",
    country: "BR",
    city: "Rio",
    stadium_name: "Alpha Arena",
    stadium_capacity: 50000,
    finance: 900000,
    manager_id: "manager-1",
    reputation: 50,
    wage_budget: 50000,
    transfer_budget: 300000,
    season_income: 1000000,
    season_expenses: 500000,
    formation: "4-4-2",
    play_style: "Balanced",
    training_focus: "Physical",
    training_intensity: "Medium",
    training_schedule: "Balanced",
    founded_year: 1900,
    colors: {
      primary: "#111111",
      secondary: "#ffffff",
    },
    facilities: {
      training: 2,
      medical: 1,
      scouting: 3,
    },
    starting_xi_ids: [],
    match_roles: {
      captain: null,
      vice_captain: null,
      penalty_taker: null,
      free_kick_taker: null,
      corner_taker: null,
    },
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
    nationality: "BR",
    position: "Forward",
    natural_position: "Forward",
    alternate_positions: [],
    training_focus: null,
    attributes: {
      pace: 10,
      stamina: 10,
      strength: 10,
      agility: 10,
      passing: 10,
      shooting: 10,
      tackling: 10,
      dribbling: 10,
      defending: 10,
      positioning: 10,
      vision: 10,
      decisions: 10,
      composure: 10,
      aggression: 10,
      teamwork: 10,
      leadership: 10,
      handling: 10,
      reflexes: 10,
      aerial: 10,
    },
    condition: 80,
    morale: 80,
    injury: null,
    team_id: "team-1",
    contract_end: null,
    wage: 1000,
    market_value: 200000,
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

function createGameState(teamOverrides: Partial<TeamData> = {}): GameStateData {
  return {
    clock: {
      current_date: "2025-01-20T00:00:00Z",
      start_date: "2025-01-01T00:00:00Z",
    },
    manager: {
      id: "manager-1",
      first_name: "Jane",
      last_name: "Doe",
      date_of_birth: "1980-01-01",
      nationality: "BR",
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
    teams: [createTeam(teamOverrides)],
    players: [createPlayer()],
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

describe("FinancesTab facilities", () => {
  beforeEach(() => {
    mockedInvoke.mockReset();
  });

  it("renders facility cards with levels and disables upgrades when funds are insufficient", () => {
    const gameState = createGameState({ finance: 200000 });

    render(<FinancesTab gameState={gameState} />);

    expect(screen.getByText("Facilities")).toBeInTheDocument();
    expect(screen.getByText("Training Facility")).toBeInTheDocument();
    expect(screen.getByText("Medical Facility")).toBeInTheDocument();
    expect(screen.getByText("Scouting Facility")).toBeInTheDocument();
    expect(screen.getByText("Level 2")).toBeInTheDocument();
    expect(screen.getByText("Level 1")).toBeInTheDocument();
    expect(screen.getByText("Level 3")).toBeInTheDocument();

    const upgradeButtons = screen.getAllByRole("button", { name: "Upgrade" });
    expect(upgradeButtons).toHaveLength(3);
    expect(upgradeButtons[0]).toBeDisabled();
    expect(upgradeButtons[1]).toBeDisabled();
    expect(upgradeButtons[2]).toBeDisabled();
    expect(screen.getAllByText("Insufficient funds")).toHaveLength(3);
  });

  it("invokes facility upgrade and publishes the updated game state", async () => {
    const initialState = createGameState();
    const updatedState = createGameState({
      finance: 650000,
      facilities: {
        training: 2,
        medical: 2,
        scouting: 3,
      },
      season_expenses: 750000,
    });
    const onGameUpdate = vi.fn();
    mockedInvoke.mockResolvedValue(updatedState);

    render(
      <FinancesTab gameState={initialState} onGameUpdate={onGameUpdate} />,
    );

    const upgradeButtons = screen.getAllByRole("button", { name: "Upgrade" });
    fireEvent.click(upgradeButtons[1]);

    await waitFor(() => {
      expect(mockedInvoke).toHaveBeenCalledWith("upgrade_facility", {
        facility: "Medical",
      });
    });
    expect(onGameUpdate).toHaveBeenCalledWith(updatedState);
  });
});
