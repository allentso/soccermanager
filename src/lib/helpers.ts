import { TeamData, FixtureData, PlayerData } from "../store/gameStore";

export function getTeamName(teams: TeamData[], id: string | null): string {
  if (!id) return "Free Agent";
  return teams.find(t => t.id === id)?.name ?? "Unknown";
}

export function getTeamShort(teams: TeamData[], id: string): string {
  return teams.find(t => t.id === id)?.short_name ?? "???";
}

export function findNextFixture(fixtures: FixtureData[], teamId: string): FixtureData | undefined {
  return fixtures.find(f =>
    f.status === "Scheduled" && (f.home_team_id === teamId || f.away_team_id === teamId)
  );
}

export function formatMatchDate(dateStr: string): string {
  const d = new Date(dateStr + "T00:00:00");
  return d.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
}

export function calcOvr(p: PlayerData): number {
  const a = p.attributes;
  return Math.round(
    (a.pace + a.stamina + a.strength + a.passing + a.shooting +
      a.tackling + a.dribbling + a.defending + a.positioning +
      a.vision + a.decisions) / 11
  );
}

export function calcAge(dob: string): number {
  return 2026 - new Date(dob).getFullYear();
}

export function formatVal(v: number): string {
  if (v >= 1_000_000) return `€${(v / 1_000_000).toFixed(1)}M`;
  if (v >= 1_000) return `€${(v / 1_000).toFixed(0)}K`;
  return `€${v}`;
}

export function positionBadgeVariant(pos: string): "accent" | "primary" | "success" | "danger" {
  switch (pos) {
    case "Goalkeeper": return "accent";
    case "Defender": return "primary";
    case "Midfielder": return "success";
    case "Forward": return "danger";
    default: return "primary";
  }
}
