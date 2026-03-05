import { describe, it, expect } from "vitest";
import { getPlayerName, phaseLabel, calcOvr } from "./helpers";
import type { MatchSnapshot, EnginePlayerData, EngineTeamData } from "./types";

// ---------------------------------------------------------------------------
// Minimal fixtures
// ---------------------------------------------------------------------------

const makePlayer = (overrides: Partial<EnginePlayerData> = {}): EnginePlayerData => ({
  id: "p1",
  name: "Test Player",
  position: "Midfielder",
  condition: 100,
  pace: 70, stamina: 70, strength: 70, agility: 70,
  passing: 70, shooting: 70, tackling: 70, dribbling: 70,
  defending: 70, positioning: 70, vision: 70, decisions: 70,
  composure: 50, aggression: 50, teamwork: 50,
  leadership: 50, handling: 30, reflexes: 30, aerial: 50,
  traits: [],
  ...overrides,
});

const makeTeam = (overrides: Partial<EngineTeamData> = {}): EngineTeamData => ({
  id: "team1",
  name: "Test FC",
  formation: "4-4-2",
  play_style: "Balanced",
  players: [],
  ...overrides,
});

const makeSnapshot = (overrides: Partial<MatchSnapshot> = {}): MatchSnapshot => ({
  phase: "FirstHalf",
  current_minute: 25,
  home_score: 0,
  away_score: 0,
  possession: "Home",
  ball_zone: "Midfield",
  home_team: makeTeam({ id: "home1", players: [makePlayer({ id: "h1", name: "Home Player" })] }),
  away_team: makeTeam({ id: "away1", players: [makePlayer({ id: "a1", name: "Away Player" })] }),
  home_bench: [makePlayer({ id: "hb1", name: "Home Bench" })],
  away_bench: [makePlayer({ id: "ab1", name: "Away Bench" })],
  home_possession_pct: 55,
  away_possession_pct: 45,
  events: [],
  home_subs_made: 0,
  away_subs_made: 0,
  max_subs: 3,
  home_set_pieces: { free_kick_taker: null, corner_taker: null, penalty_taker: null, captain: null },
  away_set_pieces: { free_kick_taker: null, corner_taker: null, penalty_taker: null, captain: null },
  substitutions: [],
  allows_extra_time: false,
  home_yellows: {},
  away_yellows: {},
  sent_off: [],
  ...overrides,
});

// ---------------------------------------------------------------------------
// getPlayerName
// ---------------------------------------------------------------------------

describe("getPlayerName", () => {
  const snapshot = makeSnapshot();

  it("finds player in home team", () => {
    expect(getPlayerName(snapshot, "h1")).toBe("Home Player");
  });

  it("finds player in away team", () => {
    expect(getPlayerName(snapshot, "a1")).toBe("Away Player");
  });

  it("finds player on home bench", () => {
    expect(getPlayerName(snapshot, "hb1")).toBe("Home Bench");
  });

  it("finds player on away bench", () => {
    expect(getPlayerName(snapshot, "ab1")).toBe("Away Bench");
  });

  it("returns empty string for null id", () => {
    expect(getPlayerName(snapshot, null)).toBe("");
  });

  it("returns the id when player not found", () => {
    expect(getPlayerName(snapshot, "unknown_id")).toBe("unknown_id");
  });
});

// ---------------------------------------------------------------------------
// phaseLabel
// ---------------------------------------------------------------------------

describe("phaseLabel", () => {
  it("maps all known phases", () => {
    expect(phaseLabel("PreKickOff")).toBe("Pre-Match");
    expect(phaseLabel("FirstHalf")).toBe("1st Half");
    expect(phaseLabel("HalfTime")).toBe("Half Time");
    expect(phaseLabel("SecondHalf")).toBe("2nd Half");
    expect(phaseLabel("FullTime")).toBe("Full Time");
    expect(phaseLabel("ExtraTimeFirstHalf")).toBe("ET 1st Half");
    expect(phaseLabel("ExtraTimeHalfTime")).toBe("ET Half Time");
    expect(phaseLabel("ExtraTimeSecondHalf")).toBe("ET 2nd Half");
    expect(phaseLabel("ExtraTimeEnd")).toBe("ET End");
    expect(phaseLabel("PenaltyShootout")).toBe("Penalties");
    expect(phaseLabel("Finished")).toBe("Final");
  });

  it("returns the input for unknown phases", () => {
    expect(phaseLabel("SomeOtherPhase")).toBe("SomeOtherPhase");
  });
});

// ---------------------------------------------------------------------------
// calcOvr (match version — averages all attrs)
// ---------------------------------------------------------------------------

describe("calcOvr (match)", () => {
  it("averages all attribute values", () => {
    expect(calcOvr({ pace: 80, shooting: 60, passing: 70 })).toBe(70);
  });

  it("rounds to nearest integer", () => {
    expect(calcOvr({ pace: 71, shooting: 72 })).toBe(72); // 143/2 = 71.5 → 72
  });

  it("returns 0 for empty attributes", () => {
    expect(calcOvr({})).toBe(0);
  });
});
