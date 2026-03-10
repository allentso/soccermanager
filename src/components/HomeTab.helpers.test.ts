import { describe, expect, it } from "vitest";

import type {
  GameStateData,
  MessageData,
  PlayerData,
  StaffData,
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

function createStaff(overrides: Partial<StaffData> = {}): StaffData {
  return {
    id: "staff-1",
    first_name: "Pat",
    last_name: "Coach",
    role: "Coach",
    nationality: "BR",
    date_of_birth: "1980-01-01",
    attributes: {
      coaching: 50,
      judging_ability: 50,
      judging_potential: 50,
      physiotherapy: 50,
    },
    specialization: null,
    wage: 0,
    contract_end: null,
    team_id: "team-1",
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
  it("does not mark training complete when the team is still on default training settings", function (): void {
    const state = getOnboardingCompletionState(createGameState());

    expect(state.hasConfiguredTraining).toBe(false);
  });

  it("marks training complete when any training setting changes from the real defaults", function (): void {
    const gameState = createGameState({
      teams: [
        createTeam({
          training_focus: "Technical",
        }),
      ],
    });

    const state = getOnboardingCompletionState(gameState);

    expect(state.hasConfiguredTraining).toBe(true);
  });

  it("marks squad review complete when the welcome message is read", function (): void {
    const gameState = createGameState({
      messages: [
        createMessage({
          id: "welcome_1",
          category: "Welcome",
          read: true,
        }),
      ],
    });

    const state = getOnboardingCompletionState(gameState);

    expect(state.hasReviewedSquad).toBe(true);
  });

  it("marks squad review complete when the manager has saved a starting xi", function (): void {
    const gameState = createGameState({
      teams: [
        createTeam({
          starting_xi_ids: ["p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8", "p9", "p10", "p11"],
        }),
      ],
    });

    const state = getOnboardingCompletionState(gameState);

    expect(state.hasReviewedSquad).toBe(true);
  });

  it("marks inbox complete only when onboarding messages are read", function (): void {
    const gameState = createGameState({
      messages: [
        createMessage({
          id: "welcome_1",
          category: "Welcome",
          read: true,
        }),
        createMessage({
          id: "season_1",
          category: "LeagueInfo",
          read: true,
        }),
        createMessage({
          id: "later-news",
          category: "System",
          read: false,
        }),
      ],
    });

    const state = getOnboardingCompletionState(gameState);

    expect(state.hasReadInbox).toBe(true);
  });

  it("marks core staff complete only when both coach and physio are hired", function (): void {
    const incompleteState = getOnboardingCompletionState(
      createGameState({
        staff: [createStaff({ role: "Coach" })],
      }),
    );
    const completeState = getOnboardingCompletionState(
      createGameState({
        staff: [
          createStaff({ id: "staff-1", role: "Coach" }),
          createStaff({
            id: "staff-2",
            role: "Physio",
            first_name: "Sam",
            last_name: "Physio",
          }),
        ],
      }),
    );

    expect(incompleteState.hasHiredCoreStaff).toBe(false);
    expect(completeState.hasHiredCoreStaff).toBe(true);
  });

  it("hides onboarding after the first week", function (): void {
    const gameState = createGameState({
      clock: {
        current_date: "2025-01-10T00:00:00Z",
        start_date: "2025-01-01T00:00:00Z",
      },
    });

    const state = getOnboardingCompletionState(gameState);

    expect(state.showOnboarding).toBe(false);
  });
});
