import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { useState } from "react";
import { beforeEach } from "vitest";
import { describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
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
      if (key === "common.renewContract") return "Renew Contract";
      if (key === "common.cancel") return "Cancel";
      if (key === "common.done") return "Done";
      if (key === "common.submit") return "Submit";
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
      if (key === "playerProfile.renewalTitle") return "Renew Contract";
      if (key === "playerProfile.renewalWage") return "Offered Wage";
      if (key === "playerProfile.renewalLength") return "Contract Length";
      if (key === "playerProfile.renewalLengthYears")
        return `${params?.count} years`;
      if (key === "playerProfile.renewalSubmit") return "Submit Offer";
      if (key === "playerProfile.renewalBudgetWarning")
        return "Exceeds wage budget";
      if (key === "playerProfile.renewalInvalidWage")
        return "Enter a valid weekly wage";
      if (key === "playerProfile.renewalAccepted") return "Offer accepted";
      if (key === "playerProfile.renewalRejected") return "Offer rejected";
      if (key === "playerProfile.renewalCounter")
        return `Wants more: €${params?.wage}/wk for ${params?.years} years`;
      if (key === "playerProfile.renewalBlocked")
        return "Talks are blocked after your earlier decision";
      if (key === "playerProfile.delegateRenewal")
        return "Delegate to Assistant";
      if (key === "playerProfile.renewalDelegateMissingReport")
        return "Assistant report did not include this player.";
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

vi.mock("../utils/backendI18n", () => ({
  resolveBackendText: (
    _key?: string,
    fallback?: string,
    _params?: Record<string, string>,
  ) => fallback ?? "",
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

function RenewalHarness({ initialPlayer }: { initialPlayer?: PlayerData }) {
  const [gameState, setGameState] = useState<GameStateData>(
    createGameState(initialPlayer ?? createPlayer()),
  );

  return (
    <PlayerProfile
      player={gameState.players[0]}
      gameState={gameState}
      isOwnClub
      onClose={vi.fn()}
      onGameUpdate={setGameState}
    />
  );
}

describe("PlayerProfile contract surfaces", () => {
  beforeEach(() => {
    vi.mocked(invoke).mockReset();
  });

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

  it("validates renewal offers before submission", async () => {
    vi.mocked(invoke).mockResolvedValue(createGameState(createPlayer()));

    render(<RenewalHarness />);

    fireEvent.click(screen.getByRole("button", { name: "Renew Contract" }));

    fireEvent.change(screen.getByLabelText("Offered Wage"), {
      target: { value: "0" },
    });

    expect(screen.getByText("Enter a valid weekly wage")).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("Offered Wage"), {
      target: { value: "60000" },
    });

    expect(screen.getByText("Exceeds wage budget")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Submit Offer" })).toBeDisabled();
  });

  it("submits a renewal offer and refreshes contract data when accepted", async () => {
    const updatedPlayer = createPlayer({
      contract_end: "2029-08-01",
      wage: 15000,
    });
    const updatedGame = createGameState(updatedPlayer);

    vi.mocked(invoke).mockResolvedValue({
      outcome: "accepted",
      game: updatedGame,
      suggested_wage: null,
      suggested_years: null,
      session_status: "agreed",
      is_terminal: true,
    });

    render(<RenewalHarness />);

    fireEvent.click(screen.getByRole("button", { name: "Renew Contract" }));
    fireEvent.change(screen.getByLabelText("Offered Wage"), {
      target: { value: "15000" },
    });
    fireEvent.change(screen.getByLabelText("Contract Length"), {
      target: { value: "3" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Submit Offer" }));

    await waitFor(() => {
      expect(invoke).toHaveBeenCalledWith("propose_renewal", {
        playerId: "player-1",
        weeklyWage: 15000,
        contractYears: 3,
      });
    });

    await waitFor(() => {
      expect(screen.getByText("Offer accepted")).toBeInTheDocument();
      expect(screen.getByText("Expires 2029-08-01")).toBeInTheDocument();
      expect(screen.getAllByText("€15,000/wk").length).toBeGreaterThan(0);
      expect(screen.getByText("Stable")).toBeInTheDocument();
      expect(screen.getByRole("button", { name: "Done" })).toBeInTheDocument();
      expect(
        screen.queryByRole("button", { name: "Submit Offer" }),
      ).not.toBeInTheDocument();
    });
  });

  it("shows a rejected state when the renewal offer is turned down", async () => {
    vi.mocked(invoke).mockResolvedValue({
      outcome: "rejected",
      game: createGameState(createPlayer()),
      suggested_wage: null,
      suggested_years: null,
      session_status: "stalled",
      is_terminal: false,
    });

    render(<RenewalHarness />);

    fireEvent.click(screen.getByRole("button", { name: "Renew Contract" }));
    fireEvent.change(screen.getByLabelText("Offered Wage"), {
      target: { value: "12000" },
    });
    fireEvent.change(screen.getByLabelText("Contract Length"), {
      target: { value: "2" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Submit Offer" }));

    await waitFor(() => {
      expect(screen.getByText("Offer rejected")).toBeInTheDocument();
    });
  });

  it("shows improved terms when the player wants more", async () => {
    vi.mocked(invoke).mockResolvedValue({
      outcome: "counter_offer",
      game: createGameState(createPlayer()),
      suggested_wage: 16000,
      suggested_years: 4,
      session_status: "open",
      is_terminal: false,
    });

    render(<RenewalHarness />);

    fireEvent.click(screen.getByRole("button", { name: "Renew Contract" }));
    fireEvent.change(screen.getByLabelText("Offered Wage"), {
      target: { value: "13000" },
    });
    fireEvent.change(screen.getByLabelText("Contract Length"), {
      target: { value: "2" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Submit Offer" }));

    await waitFor(() => {
      expect(
        screen.getByText("Wants more: €16000/wk for 4 years"),
      ).toBeInTheDocument();
    });
  });

  it("can delegate a single renewal attempt to the assistant", async () => {
    const delegatedPlayer = createPlayer({
      contract_end: "2029-08-01",
      wage: 14000,
    });
    const updatedGame = createGameState(delegatedPlayer);

    vi.mocked(invoke).mockResolvedValue({
      game: updatedGame,
      report: {
        success_count: 1,
        failure_count: 0,
        stalled_count: 0,
        cases: [
          {
            player_id: "player-1",
            player_name: "John Smith",
            status: "successful",
            agreed_wage: 14000,
            agreed_years: 3,
            note: "I was able to close this one without needing you to step in.",
          },
        ],
      },
    });

    render(<RenewalHarness />);

    fireEvent.click(screen.getByRole("button", { name: "Renew Contract" }));
    fireEvent.click(
      screen.getByRole("button", { name: "Delegate to Assistant" }),
    );

    await waitFor(() => {
      expect(invoke).toHaveBeenCalledWith("delegate_renewals", {
        playerIds: ["player-1"],
        maxWageIncreasePct: 35,
        maxContractYears: 3,
      });
    });

    await waitFor(() => {
      expect(screen.getByText("Offer accepted")).toBeInTheDocument();
      expect(screen.getByRole("button", { name: "Done" })).toBeInTheDocument();
    });
  });

  it("shows a localized error when the assistant report omits the player", async () => {
    vi.mocked(invoke).mockResolvedValue({
      game: createGameState(createPlayer()),
      report: {
        success_count: 0,
        failure_count: 0,
        stalled_count: 0,
        cases: [],
      },
    });

    render(<RenewalHarness />);

    fireEvent.click(screen.getByRole("button", { name: "Renew Contract" }));
    fireEvent.click(
      screen.getByRole("button", { name: "Delegate to Assistant" }),
    );

    await waitFor(() => {
      expect(
        screen.getByText("Assistant report did not include this player."),
      ).toBeInTheDocument();
    });
  });
});
