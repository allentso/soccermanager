import { MatchEvent, MatchSnapshot } from "./types";

export const EVENT_ICONS: Record<string, { icon: string; color: string; important: boolean }> = {
  Goal:            { icon: "⚽", color: "text-accent-400", important: true },
  PenaltyGoal:     { icon: "⚽", color: "text-accent-400", important: true },
  PenaltyMiss:     { icon: "❌", color: "text-red-400", important: true },
  YellowCard:      { icon: "🟨", color: "text-yellow-400", important: true },
  RedCard:         { icon: "🟥", color: "text-red-500", important: true },
  SecondYellow:    { icon: "🟥", color: "text-red-500", important: true },
  Substitution:    { icon: "🔄", color: "text-blue-400", important: true },
  Injury:          { icon: "🏥", color: "text-red-400", important: true },
  KickOff:         { icon: "▶️", color: "text-gray-400", important: true },
  HalfTime:        { icon: "⏸️", color: "text-gray-400", important: true },
  SecondHalfStart: { icon: "▶️", color: "text-gray-400", important: true },
  FullTime:        { icon: "🏁", color: "text-gray-400", important: true },
  ShotSaved:       { icon: "🧤", color: "text-green-400", important: false },
  ShotOffTarget:   { icon: "↗️", color: "text-gray-500", important: false },
  ShotBlocked:     { icon: "🛡️", color: "text-gray-500", important: false },
  Corner:          { icon: "🚩", color: "text-gray-500", important: false },
  FreeKick:        { icon: "📐", color: "text-gray-500", important: false },
  Foul:            { icon: "⚠️", color: "text-yellow-600", important: false },
  PenaltyAwarded:  { icon: "⚡", color: "text-accent-400", important: true },
};

export function getEventDisplay(evt: MatchEvent) {
  return EVENT_ICONS[evt.event_type] || { icon: "•", color: "text-gray-400", important: false };
}

export function getPlayerName(snapshot: MatchSnapshot, playerId: string | null): string {
  if (!playerId) return "";
  for (const p of snapshot.home_team.players) {
    if (p.id === playerId) return p.name;
  }
  for (const p of snapshot.away_team.players) {
    if (p.id === playerId) return p.name;
  }
  return playerId;
}

export function phaseLabel(phase: string): string {
  switch (phase) {
    case "PreKickOff": return "Pre-Match";
    case "FirstHalf": return "1st Half";
    case "HalfTime": return "Half Time";
    case "SecondHalf": return "2nd Half";
    case "FullTime": return "Full Time";
    case "ExtraTimeFirstHalf": return "ET 1st Half";
    case "ExtraTimeHalfTime": return "ET Half Time";
    case "ExtraTimeSecondHalf": return "ET 2nd Half";
    case "ExtraTimeEnd": return "ET End";
    case "PenaltyShootout": return "Penalties";
    case "Finished": return "Final";
    default: return phase;
  }
}

export function calcOvr(attrs: Record<string, number>): number {
  const vals = Object.values(attrs);
  if (vals.length === 0) return 0;
  return Math.round(vals.reduce((a, b) => a + b, 0) / vals.length);
}
