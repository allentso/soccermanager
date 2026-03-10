import { describe, expect, it } from "vitest";

import type {
  GameStateData,
  MessageData,
  PlayerData,
  TeamData,
} from "../store/gameStore";
import { getOnboardingCompletionState } from "./HomeTab.helpers";

function createTeam(overrides: Partial<TeamData> = {}): TeamData {
  return {
    id: "team-1",
    name: "Alpha FC",
    short_name: "ALP",
    country: "BR",
    city: "Rio",
    stadium_name: "Alpha Arena",
    stadium_capacity: 50000,
    finance: 0,
    manager_id: "manager-1",
    reputation: 50,
    wage_budget: 0,
    transfer_budget: 0,
    season_income: 0,
    season_expenses: 0,
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
    wage: 0,
    market_value: 0,
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

function createMessage(overrides: Partial<MessageData> = {}): MessageData {
  return {
    id: "message-1",
    subject: "Subject",
    body: "Body",
    sender: "Sender",
    sender_role: "Role",
    date: "2025-01-10",
    read: false,
    category: "System",
    priority: "Normal",
    actions: [],
    context: {
      team_id: null,
      player_id: null,
      fixture_id: null,
      match_result: null,
    },
    ...overrides,
  };
}

function createGameState(overrides: Partial<GameStateData> = {}): GameStateData {
  return {
    clock: {
      current_date: "2025-01-03T00:00:00Z",
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
    teams: [createTeam()],
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
    ...overrides,
  };
}

describe("HomeTab.helpers", function (): void {
  it("starts with no visited onboarding pages and no read inbox step", function (): void {
    const state = getOnboardingCompletionState(createGameState(), new Set<string>());

    expect(state.hasVisitedSquadPage).toBe(false);
    expect(state.hasVisitedStaffPage).toBe(false);
    expect(state.hasVisitedTacticsPage).toBe(false);
    expect(state.hasVisitedTrainingPage).toBe(false);
    expect(state.hasReadInbox).toBe(false);
    expect(state.completedSteps).toBe(0);
  });

  it("marks visited onboarding pages as done", function (): void {
    const state = getOnboardingCompletionState(
      createGameState(),
      new Set<string>(["Squad", "Tactics"]),
    );

    expect(state.hasVisitedSquadPage).toBe(true);
    expect(state.hasVisitedTacticsPage).toBe(true);
    expect(state.hasVisitedStaffPage).toBe(false);
    expect(state.hasVisitedTrainingPage).toBe(false);
    expect(state.completedSteps).toBe(2);
  });

  it("marks inbox complete after at least one message is read", function (): void {
    const gameState = createGameState({
      messages: [
        createMessage({
          id: "message-1",
          read: true,
        }),
        createMessage({
          id: "message-2",
          category: "System",
          read: false,
        }),
      ],
    });

    const state = getOnboardingCompletionState(gameState, new Set<string>());

    expect(state.hasReadInbox).toBe(true);
  });

  it("counts page visits together with the inbox step", function (): void {
    const gameState = createGameState({
      messages: [
        createMessage({
          id: "message-1",
          read: true,
        }),
      ],
    });
    const state = getOnboardingCompletionState(
      gameState,
      new Set<string>(["Squad", "Staff", "Training"]),
    );

    expect(state.completedSteps).toBe(4);
  });

  it("hides onboarding after the first week", function (): void {
    const gameState = createGameState({
      clock: {
        current_date: "2025-01-10T00:00:00Z",
        start_date: "2025-01-01T00:00:00Z",
      },
    });

    const state = getOnboardingCompletionState(gameState, new Set<string>());

    expect(state.showOnboarding).toBe(false);
  });
});
