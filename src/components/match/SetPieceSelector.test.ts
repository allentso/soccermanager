import { describe, it, expect } from "vitest";
import { getSetPieceStats } from "./SetPieceSelector";
import type { PlayerData } from "../../store/gameStore";

// ---------------------------------------------------------------------------
// Minimal fixture
// ---------------------------------------------------------------------------

const makePlayer = (overrides: Partial<PlayerData> = {}): PlayerData => ({
  id: "p1",
  match_name: "Test Player",
  full_name: "Test Player Full",
  date_of_birth: "1996-01-15",
  nationality: "GB",
  position: "Midfielder",
  attributes: {
    pace: 70, stamina: 70, strength: 70, agility: 70,
    passing: 75, shooting: 80, tackling: 60, dribbling: 70,
    defending: 60, positioning: 65, vision: 72, decisions: 68,
    composure: 50, aggression: 50, teamwork: 50,
    leadership: 50, handling: 30, reflexes: 30, aerial: 50,
  },
  condition: 100,
  morale: 80,
  injury: null,
  team_id: "team_1",
  contract_end: "2028-06-30",
  wage: 10000,
  market_value: 5000000,
  stats: {
    appearances: 0, goals: 0, assists: 0, clean_sheets: 0,
    yellow_cards: 0, red_cards: 0, avg_rating: 0, minutes_played: 0,
  },
  career: [],
  transfer_listed: false,
  loan_listed: false,
  transfer_offers: [],
  traits: [],
  ...overrides,
});

// ---------------------------------------------------------------------------
// getSetPieceStats
// ---------------------------------------------------------------------------

describe("getSetPieceStats", () => {
  const player = makePlayer();
  const a = player.attributes;

  it("penalty: weights shooting*2, decisions, vision", () => {
    const result = getSetPieceStats("penalty", player);
    expect(result.score).toBe(Math.round((a.shooting * 2 + a.decisions + a.vision) / 4));
    expect(result.stats).toEqual([
      { label: "SHO", value: a.shooting },
      { label: "DEC", value: a.decisions },
    ]);
  });

  it("freekick: weights shooting, passing, vision equally", () => {
    const result = getSetPieceStats("freekick", player);
    expect(result.score).toBe(Math.round((a.shooting + a.passing + a.vision) / 3));
    expect(result.stats).toEqual([
      { label: "SHO", value: a.shooting },
      { label: "PAS", value: a.passing },
      { label: "VIS", value: a.vision },
    ]);
  });

  it("corner: weights passing*2, vision", () => {
    const result = getSetPieceStats("corner", player);
    expect(result.score).toBe(Math.round((a.passing * 2 + a.vision) / 3));
    expect(result.stats).toEqual([
      { label: "PAS", value: a.passing },
      { label: "VIS", value: a.vision },
    ]);
  });

  it("captain: weights decisions, vision, positioning equally", () => {
    const result = getSetPieceStats("captain", player);
    expect(result.score).toBe(Math.round((a.decisions + a.vision + a.positioning) / 3));
    expect(result.stats).toEqual([
      { label: "DEC", value: a.decisions },
      { label: "VIS", value: a.vision },
      { label: "POS", value: a.positioning },
    ]);
  });

  it("unknown role: returns score 0 and empty stats", () => {
    const result = getSetPieceStats("throw_in", player);
    expect(result.score).toBe(0);
    expect(result.stats).toEqual([]);
  });
});
