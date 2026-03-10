import type { PlayerData } from "../store/gameStore";
import { calcOvr } from "../lib/helpers";

export type SquadSection = "xi" | "bench";
export type DragState = {
  playerId: string;
  from: SquadSection;
  slotIndex: number | null;
};

export type PitchRow = { label: string; y: string; positions: string[] };
export type PitchSlot = {
  index: number;
  position: string;
  player: PlayerData | null;
};
export type PitchSlotRow = PitchRow & { slots: PitchSlot[] };

export const CORE_POSITIONS = [
  "Goalkeeper",
  "Defender",
  "Midfielder",
  "Forward",
] as const;

const POSITION_CODES: Record<string, string> = {
  Goalkeeper: "GK",
  Defender: "DEF",
  Midfielder: "MID",
  Forward: "FWD",
};

export function parseFormationSlots(formation: string): {
  def: number;
  mid: number;
  fwd: number;
} {
  const parts = formation.split("-").map(Number);
  if (parts.length === 4) {
    return { def: parts[0], mid: parts[1] + parts[2], fwd: parts[3] };
  }
  if (parts.length === 3) {
    return { def: parts[0], mid: parts[1], fwd: parts[2] };
  }
  return { def: 4, mid: 4, fwd: 2 };
}

export function normalisePosition(position: string): string {
  const trimmed = position.trim();
  if (!trimmed) return trimmed;

  const lower = trimmed.toLowerCase();
  if (lower.includes("keep")) return "Goalkeeper";
  if (lower.includes("mid")) return "Midfielder";
  if (
    lower.includes("back") ||
    lower.includes("defender") ||
    lower.includes("centre-half") ||
    lower.includes("center-half")
  )
    return "Defender";
  if (lower.includes("wing")) return "Midfielder";
  if (
    lower.includes("forw") ||
    lower.includes("strik") ||
    lower.includes("att")
  ) {
    return "Forward";
  }

  return trimmed;
}

export function positionCode(position: string): string {
  const normalized = normalisePosition(position);
  return (
    POSITION_CODES[normalized] || normalized.substring(0, 3).toUpperCase()
  );
}

export function getPreferredPositions(player: PlayerData): string[] {
  return [
    ...new Set(
      [
        player.natural_position || player.position,
        ...(player.alternate_positions || []),
      ]
        .filter(Boolean)
        .map(normalisePosition),
    ),
  ];
}

export function buildPitchRows(formation: string): PitchRow[] {
  const parts = formation
    .split("-")
    .map(Number)
    .filter((value) => !Number.isNaN(value));

  if (parts.length === 4) {
    return [
      { label: "GK", y: "90%", positions: ["Goalkeeper"] },
      { label: "DEF", y: "70%", positions: Array(parts[0]).fill("Defender") },
      { label: "DM", y: "50%", positions: Array(parts[1]).fill("Midfielder") },
      { label: "AM", y: "30%", positions: Array(parts[2]).fill("Midfielder") },
      { label: "FWD", y: "10%", positions: Array(parts[3]).fill("Forward") },
    ];
  }

  const slots = parseFormationSlots(formation);
  return [
    { label: "GK", y: "90%", positions: ["Goalkeeper"] },
    { label: "DEF", y: "70%", positions: Array(slots.def).fill("Defender") },
    { label: "MID", y: "50%", positions: Array(slots.mid).fill("Midfielder") },
    { label: "FWD", y: "30%", positions: Array(slots.fwd).fill("Forward") },
  ];
}

export function buildStartingXIIds(
  available: PlayerData[],
  savedIds: string[],
  formation: string,
): string[] {
  const slots = parseFormationSlots(formation);
  const byId = new Map(available.map((player) => [player.id, player]));
  const validSavedIds: string[] = [];
  const used = new Set<string>();

  for (const id of savedIds) {
    const player = byId.get(id);
    if (player && !used.has(id)) {
      validSavedIds.push(id);
      used.add(id);
    }
  }

  if (validSavedIds.length >= 8) {
    const remaining = available
      .filter((player) => !used.has(player.id))
      .sort((a, b) => calcOvr(b) - calcOvr(a))
      .map((player) => player.id);
    return [...validSavedIds, ...remaining].slice(0, 11);
  }

  const xi: string[] = [];
  const pick = (position: string, count: number) => {
    const candidates = available
      .filter(
        (player) =>
          normalisePosition(player.position) === position && !used.has(player.id),
      )
      .sort((a, b) => calcOvr(b) - calcOvr(a));

    for (let index = 0; index < count && index < candidates.length; index += 1) {
      xi.push(candidates[index].id);
      used.add(candidates[index].id);
    }
  };

  pick("Goalkeeper", 1);
  pick("Defender", slots.def);
  pick("Midfielder", slots.mid);
  pick("Forward", slots.fwd);

  const remaining = available
    .filter((player) => !used.has(player.id))
    .sort((a, b) => calcOvr(b) - calcOvr(a))
    .map((player) => player.id);

  return [...xi, ...remaining].slice(0, 11);
}

export function buildPitchSlotRows(
  rows: PitchRow[],
  xiIds: string[],
  playersById: Map<string, PlayerData>,
): PitchSlotRow[] {
  let slotIndex = 0;
  return rows.map((row) => ({
    ...row,
    slots: row.positions.map((position) => {
      const slot: PitchSlot = {
        index: slotIndex,
        position,
        player: playersById.get(xiIds[slotIndex]) ?? null,
      };
      slotIndex += 1;
      return slot;
    }),
  }));
}

export function buildActivePositionMap(
  pitchSlotRows: PitchSlotRow[],
): Map<string, string> {
  const map = new Map<string, string>();
  pitchSlotRows.forEach((row) => {
    row.slots.forEach((slot) => {
      if (slot.player) {
        map.set(slot.player.id, normalisePosition(slot.position));
      }
    });
  });
  return map;
}

export function isPlayerOutOfPosition(
  player: PlayerData,
  currentPos: string,
): boolean {
  const normalizedCurrentPos = normalisePosition(currentPos);
  return !getPreferredPositions(player).includes(normalizedCurrentPos);
}

export function applyLineupDrop(
  currentXiIds: string[],
  dragState: DragState,
  slotIndex: number,
): string[] {
  const nextXiIds = [...currentXiIds];

  if (slotIndex < 0 || slotIndex >= nextXiIds.length) {
    return nextXiIds;
  }

  if (dragState.from === "xi") {
    const fromIndex =
      dragState.slotIndex ?? nextXiIds.indexOf(dragState.playerId);
    if (fromIndex < 0 || fromIndex === slotIndex) {
      return nextXiIds;
    }
    [nextXiIds[fromIndex], nextXiIds[slotIndex]] = [
      nextXiIds[slotIndex],
      nextXiIds[fromIndex],
    ];
    return nextXiIds;
  }

  const existingIndex = nextXiIds.indexOf(dragState.playerId);
  if (existingIndex === slotIndex) {
    return nextXiIds;
  }
  if (existingIndex >= 0) {
    nextXiIds.splice(existingIndex, 1);
    if (existingIndex < slotIndex) {
      slotIndex -= 1;
    }
    nextXiIds.splice(slotIndex, 0, dragState.playerId);
    return nextXiIds.slice(0, currentXiIds.length);
  }
  if (slotIndex >= nextXiIds.length) {
    nextXiIds.push(dragState.playerId);
  } else {
    nextXiIds[slotIndex] = dragState.playerId;
  }
  return nextXiIds.slice(0, currentXiIds.length);
}

export function applyLineupSwap(
  currentXiIds: string[],
  swapSource: { id: string; from: SquadSection },
  playerId: string,
  from: SquadSection,
): string[] | null {
  if (swapSource.from === "xi" && from === "bench") {
    return currentXiIds.map((id) => (id === swapSource.id ? playerId : id));
  }

  if (swapSource.from === "bench" && from === "xi") {
    return currentXiIds.map((id) => (id === playerId ? swapSource.id : id));
  }

  if (swapSource.from === "xi" && from === "xi") {
    const firstIndex = currentXiIds.indexOf(swapSource.id);
    const secondIndex = currentXiIds.indexOf(playerId);
    if (firstIndex < 0 || secondIndex < 0 || firstIndex === secondIndex) {
      return currentXiIds;
    }
    const nextXiIds = [...currentXiIds];
    nextXiIds[firstIndex] = playerId;
    nextXiIds[secondIndex] = swapSource.id;
    return nextXiIds;
  }

  return null;
}
