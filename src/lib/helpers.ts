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

const LANG_LOCALE: Record<string, string> = { en: "en-US", es: "es-ES", pt: "pt-BR", fr: "fr-FR", de: "de-DE", it: "it-IT" };

export function getLocale(lang?: string): string {
  if (!lang) return "en-US";
  return LANG_LOCALE[lang] || lang;
}

export function formatMatchDate(dateStr: string, locale?: string): string {
  const d = new Date(dateStr + "T00:00:00");
  return d.toLocaleDateString(getLocale(locale), { weekday: "short", month: "short", day: "numeric" });
}

export function formatDate(dateStr: string, locale?: string, opts?: Intl.DateTimeFormatOptions): string {
  const d = new Date(dateStr);
  return d.toLocaleDateString(getLocale(locale), opts || { year: "numeric", month: "long", day: "numeric" });
}

export function formatDateFull(dateStr: string, locale?: string): string {
  const d = new Date(dateStr);
  return d.toLocaleDateString(getLocale(locale), { weekday: "long", year: "numeric", month: "long", day: "numeric" });
}

export function formatDateShort(dateStr: string, locale?: string): string {
  const d = new Date(dateStr);
  return d.toLocaleDateString(getLocale(locale), { month: "short", day: "numeric" });
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

export function formatWeeklyAmount(
  formattedAmount: string,
  weeklySuffix: string,
): string {
  return `${formattedAmount}${weeklySuffix}`;
}

export type ContractRiskLevel = "critical" | "warning" | "stable";

export function getDaysUntil(targetDate: string, currentDate: string): number {
  const millisecondsPerDay = 1000 * 60 * 60 * 24;
  return Math.ceil(
    (new Date(targetDate).getTime() - new Date(currentDate).getTime()) /
      millisecondsPerDay,
  );
}

export function getContractRiskLevel(
  contractEnd: string | null,
  currentDate: string,
): ContractRiskLevel {
  if (!contractEnd) return "stable";

  const daysUntilExpiry = getDaysUntil(contractEnd, currentDate);

  if (daysUntilExpiry <= 180) return "critical";
  if (daysUntilExpiry <= 365) return "warning";
  return "stable";
}

export function getContractRiskBadgeVariant(
  level: ContractRiskLevel,
): "accent" | "success" | "danger" {
  if (level === "critical") return "danger";
  if (level === "warning") return "accent";
  return "success";
}

export function getContractYearsRemaining(
  contractEnd: string | null,
  currentDate: string,
): string {
  if (!contractEnd) return "—";

  const daysUntilExpiry = Math.max(0, getDaysUntil(contractEnd, currentDate));
  return (daysUntilExpiry / 365).toFixed(1);
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
