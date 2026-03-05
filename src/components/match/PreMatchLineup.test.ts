import { describe, it, expect } from "vitest";
import { getPositionOvr, parseFormationNeeds } from "./PreMatchLineup";
import type { EnginePlayerData } from "./types";

// ---------------------------------------------------------------------------
// Minimal fixture
// ---------------------------------------------------------------------------

const makePlayer = (overrides: Partial<EnginePlayerData> = {}): EnginePlayerData => ({
  id: "p1",
  name: "Test Player",
  position: "Midfielder",
  condition: 100,
  pace: 70, stamina: 70, strength: 70, agility: 70,
  passing: 70, shooting: 70, tackling: 70, dribbling: 70,
  defending: 70, positioning: 70, vision: 70, decisions: 70,
  composure: 70, aggression: 50, teamwork: 70,
  leadership: 50, handling: 70, reflexes: 70, aerial: 70,
  traits: [],
  ...overrides,
});

// ---------------------------------------------------------------------------
// getPositionOvr
// ---------------------------------------------------------------------------

describe("getPositionOvr", () => {
  it("calculates Goalkeeper OVR from handling, reflexes, aerial, positioning, composure", () => {
    const gk = makePlayer({ position: "Goalkeeper", handling: 80, reflexes: 80, aerial: 60, positioning: 70, composure: 60 });
    // (80*2 + 80*2 + 60 + 70 + 60) / 7 = 510/7 ≈ 73
    expect(getPositionOvr(gk)).toBe(Math.round((80*2 + 80*2 + 60 + 70 + 60) / 7));
  });

  it("calculates Defender OVR from defending, tackling, strength, positioning, aerial", () => {
    const def = makePlayer({ position: "Defender", defending: 80, tackling: 75, strength: 70, positioning: 65, aerial: 60 });
    expect(getPositionOvr(def)).toBe(Math.round((80*2 + 75*2 + 70 + 65 + 60) / 7));
  });

  it("calculates Midfielder OVR from passing, vision, decisions, stamina, dribbling, teamwork", () => {
    const mid = makePlayer({ position: "Midfielder", passing: 80, vision: 75, decisions: 70, stamina: 65, dribbling: 60, teamwork: 55 });
    expect(getPositionOvr(mid)).toBe(Math.round((80*2 + 75 + 70 + 65 + 60 + 55) / 7));
  });

  it("calculates Forward OVR from shooting, pace, dribbling, composure, strength, positioning", () => {
    const fwd = makePlayer({ position: "Forward", shooting: 85, pace: 80, dribbling: 75, composure: 70, strength: 65, positioning: 60 });
    expect(getPositionOvr(fwd)).toBe(Math.round((85*2 + 80 + 75 + 70 + 65 + 60) / 7));
  });

  it("returns 50 for unknown positions", () => {
    const unknown = makePlayer({ position: "Sweeper" });
    expect(getPositionOvr(unknown)).toBe(50);
  });
});

// ---------------------------------------------------------------------------
// parseFormationNeeds
// ---------------------------------------------------------------------------

describe("parseFormationNeeds", () => {
  it("parses standard 3-part formations", () => {
    expect(parseFormationNeeds("4-4-2")).toEqual({ Goalkeeper: 1, Defender: 4, Midfielder: 4, Forward: 2 });
    expect(parseFormationNeeds("4-3-3")).toEqual({ Goalkeeper: 1, Defender: 4, Midfielder: 3, Forward: 3 });
    expect(parseFormationNeeds("3-5-2")).toEqual({ Goalkeeper: 1, Defender: 3, Midfielder: 5, Forward: 2 });
  });

  it("parses 4-part formations", () => {
    expect(parseFormationNeeds("1-4-3-2")).toEqual({ Goalkeeper: 1, Defender: 4, Midfielder: 3, Forward: 2 });
  });

  it("returns default 4-4-2 for unparsable input", () => {
    expect(parseFormationNeeds("invalid")).toEqual({ Goalkeeper: 1, Defender: 4, Midfielder: 4, Forward: 2 });
    expect(parseFormationNeeds("")).toEqual({ Goalkeeper: 1, Defender: 4, Midfielder: 4, Forward: 2 });
  });
});
