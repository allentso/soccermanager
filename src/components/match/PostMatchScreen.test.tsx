import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import PostMatchScreen from "./PostMatchScreen";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
}));

vi.mock("react-i18next", () => ({
  useTranslation: () => ({
    t: (key: string, params?: Record<string, string | number>) => {
      if (key === "schedule.matchday") {
        return `Matchday ${params?.number}`;
      }
      if (key === "match.roundSummaryUnavailable") {
        return "Round summary unavailable.";
      }
      if (key === "match.roundSummary") {
        return "Round Summary";
      }
      if (key === "home.leagueTable") {
        return "League Table";
      }
      if (key === "home.topScorers") {
        return "Top Scorers";
      }
      if (key === "home.noGoals") {
        return "No goals scored yet.";
      }
      if (key === "common.none") {
        return "None";
      }
      if (params?.team) {
        return `${key}:${params.team}`;
      }
      return key;
    },
  }),
}));

function makeSnapshot() {
  return {
    phase: "FullTime",
    current_minute: 90,
    home_score: 2,
    away_score: 1,
    possession: "Home" as const,
    ball_zone: "Midfield",
    home_team: {
      id: "team1",
      name: "Alpha FC",
      formation: "4-4-2",
      play_style: "Balanced",
      players: [
        {
          id: "p1",
          name: "Alice",
          position: "Forward",
          condition: 90,
          pace: 70,
          stamina: 70,
          strength: 70,
          agility: 70,
          passing: 70,
          shooting: 70,
          tackling: 40,
          dribbling: 70,
          defending: 40,
          positioning: 70,
          vision: 70,
          decisions: 70,
          composure: 70,
          aggression: 50,
          teamwork: 70,
          leadership: 60,
          handling: 20,
          reflexes: 20,
          aerial: 50,
          traits: [],
        },
      ],
    },
    away_team: {
      id: "team2",
      name: "Beta FC",
      formation: "4-4-2",
      play_style: "Balanced",
      players: [
        {
          id: "p2",
          name: "Bob",
          position: "Forward",
          condition: 90,
          pace: 70,
          stamina: 70,
          strength: 70,
          agility: 70,
          passing: 70,
          shooting: 70,
          tackling: 40,
          dribbling: 70,
          defending: 40,
          positioning: 70,
          vision: 70,
          decisions: 70,
          composure: 70,
          aggression: 50,
          teamwork: 70,
          leadership: 60,
          handling: 20,
          reflexes: 20,
          aerial: 50,
          traits: [],
        },
      ],
    },
    home_bench: [],
    away_bench: [],
    home_possession_pct: 52,
    away_possession_pct: 48,
    events: [],
    home_subs_made: 0,
    away_subs_made: 0,
    max_subs: 5,
    home_set_pieces: {
      free_kick_taker: null,
      corner_taker: null,
      penalty_taker: null,
      captain: null,
    },
    away_set_pieces: {
      free_kick_taker: null,
      corner_taker: null,
      penalty_taker: null,
      captain: null,
    },
    substitutions: [],
    allows_extra_time: false,
    home_yellows: {},
    away_yellows: {},
    sent_off: [],
  };
}

function makeGameState() {
  return {
    clock: {
      current_date: "2026-08-01",
      start_date: "2026-08-01",
    },
    manager: {
      id: "mgr1",
      first_name: "Alex",
      last_name: "Manager",
      date_of_birth: "1980-01-01",
      nationality: "GB",
      reputation: 50,
      satisfaction: 50,
      fan_approval: 50,
      team_id: "team1",
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
    teams: [
      {
        id: "team1",
        name: "Alpha FC",
        short_name: "ALP",
        country: "England",
        city: "Alpha",
        stadium_name: "Alpha Park",
        stadium_capacity: 20000,
        finance: 1000000,
        manager_id: "mgr1",
        reputation: 50,
        wage_budget: 100000,
        transfer_budget: 500000,
        season_income: 0,
        season_expenses: 0,
        formation: "4-4-2",
        play_style: "Balanced",
        training_focus: "Physical",
        training_intensity: "Medium",
        training_schedule: "Balanced",
        founded_year: 1900,
        colors: { primary: "#00ff00", secondary: "#ffffff" },
        starting_xi_ids: [],
        match_roles: {
          captain: null,
          vice_captain: null,
          penalty_taker: null,
          free_kick_taker: null,
          corner_taker: null,
        },
        form: ["W", "W", "D"],
        history: [],
      },
      {
        id: "team2",
        name: "Beta FC",
        short_name: "BET",
        country: "England",
        city: "Beta",
        stadium_name: "Beta Park",
        stadium_capacity: 20000,
        finance: 1000000,
        manager_id: null,
        reputation: 50,
        wage_budget: 100000,
        transfer_budget: 500000,
        season_income: 0,
        season_expenses: 0,
        formation: "4-4-2",
        play_style: "Balanced",
        training_focus: "Physical",
        training_intensity: "Medium",
        training_schedule: "Balanced",
        founded_year: 1900,
        colors: { primary: "#0000ff", secondary: "#ffffff" },
        starting_xi_ids: [],
        match_roles: {
          captain: null,
          vice_captain: null,
          penalty_taker: null,
          free_kick_taker: null,
          corner_taker: null,
        },
        form: ["L", "D", "W"],
        history: [],
      },
    ],
    players: [],
    staff: [],
    messages: [],
    news: [],
    league: null,
    scouting_assignments: [],
    board_objectives: [],
  };
}

describe("PostMatchScreen", function (): void {
  it("renders the round summary mini table and scorer list when summary data exists", function (): void {
    render(
      <PostMatchScreen
        snapshot={makeSnapshot()}
        gameState={makeGameState()}
        userSide="Home"
        isSpectator={false}
        importantEvents={[]}
        roundSummary={{
          matchday: 4,
          is_complete: true,
          pending_fixture_count: 0,
          completed_results: [
            {
              fixture_id: "fx1",
              home_team_id: "team1",
              home_team_name: "Alpha FC",
              away_team_id: "team2",
              away_team_name: "Beta FC",
              home_goals: 2,
              away_goals: 1,
            },
          ],
          standings_delta: [
            {
              team_id: "team1",
              team_name: "Alpha FC",
              previous_position: 2,
              current_position: 1,
              points: 12,
              points_delta: 3,
            },
            {
              team_id: "team2",
              team_name: "Beta FC",
              previous_position: 1,
              current_position: 2,
              points: 10,
              points_delta: 0,
            },
          ],
          notable_upset: null,
          top_scorer_delta: [
            {
              player_id: "p1",
              player_name: "Alice",
              team_id: "team1",
              previous_rank: 2,
              current_rank: 1,
              previous_goals: 4,
              current_goals: 6,
            },
          ],
        }}
        onPressConference={() => {}}
        onFinish={() => {}}
      />,
    );

    expect(screen.getByText("Matchday 4")).toBeInTheDocument();
    expect(screen.getByText("Alpha FC 2 - 1 Beta FC")).toBeInTheDocument();
    expect(screen.getByText("1. Alpha FC")).toBeInTheDocument();
    expect(screen.getByText("1. Alice")).toBeInTheDocument();
  });

  it("renders a friendly empty state when the round summary is null", function (): void {
    render(
      <PostMatchScreen
        snapshot={makeSnapshot()}
        gameState={makeGameState()}
        userSide="Home"
        isSpectator={false}
        importantEvents={[]}
        roundSummary={null}
        onPressConference={() => {}}
        onFinish={() => {}}
      />,
    );

    expect(screen.getByText("Round summary unavailable.")).toBeInTheDocument();
  });
});
