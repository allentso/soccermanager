import { TeamData, FixtureData, LeagueData, PlayerData } from "../store/gameStore";

const POSITION_ALIASES: Record<string, string> = {
  gk: "Goalkeeper",
  goalkeeper: "Goalkeeper",
  defender: "Defender",
  def: "Defender",
  midfielder: "Midfielder",
  mid: "Midfielder",
  forward: "Forward",
  fwd: "Forward",
  wingback: "Defender",
  winger: "Forward",
  rb: "RightBack",
  rightback: "RightBack",
  cb: "CenterBack",
  centerback: "CenterBack",
  centreback: "CenterBack",
  lb: "LeftBack",
  leftback: "LeftBack",
  rwb: "RightWingBack",
  rightwingback: "RightWingBack",
  lwb: "LeftWingBack",
  leftwingback: "LeftWingBack",
  dm: "DefensiveMidfielder",
  defensivemidfielder: "DefensiveMidfielder",
  cm: "CentralMidfielder",
  centralmidfielder: "CentralMidfielder",
  am: "AttackingMidfielder",
  attackingmidfielder: "AttackingMidfielder",
  rm: "RightMidfielder",
  rightmidfielder: "RightMidfielder",
  lm: "LeftMidfielder",
  leftmidfielder: "LeftMidfielder",
  rw: "RightWinger",
  rightwinger: "RightWinger",
  lw: "LeftWinger",
  leftwinger: "LeftWinger",
  st: "Striker",
  striker: "Striker",
};

const POSITION_GROUPS: Record<string, string> = {
  Goalkeeper: "Goalkeeper",
  Defender: "Defender",
  Midfielder: "Midfielder",
  Forward: "Forward",
  RightBack: "Defender",
  CenterBack: "Defender",
  LeftBack: "Defender",
  RightWingBack: "Defender",
  LeftWingBack: "Defender",
  DefensiveMidfielder: "Midfielder",
  CentralMidfielder: "Midfielder",
  AttackingMidfielder: "Midfielder",
  RightMidfielder: "Midfielder",
  LeftMidfielder: "Midfielder",
  RightWinger: "Forward",
  LeftWinger: "Forward",
  Striker: "Forward",
};

function normalisePositionKey(value: string): string {
  return value.toLowerCase().replace(/[^a-z]/g, "");
}

export function canonicalPosition(position: string): string {
  const trimmed = position.trim();
  if (!trimmed) return trimmed;
  return POSITION_ALIASES[normalisePositionKey(trimmed)] || trimmed;
}

function exactPosition(position: string): string {
  switch (canonicalPosition(position)) {
    case "Defender":
      return "CenterBack";
    case "Midfielder":
      return "CentralMidfielder";
    case "Forward":
      return "Striker";
    default:
      return canonicalPosition(position);
  }
}

function positionGroup(position: string): string {
  const canonical = canonicalPosition(position);
  return POSITION_GROUPS[canonical] || canonical;
}

function weightedAverage(values: Array<[number, number]>): number {
  return values.reduce((sum, [value, weight]) => sum + value * weight, 0) / 100;
}

function primaryPosition(player: PlayerData): string {
  const preferred = canonicalPosition(player.natural_position || player.position);
  if (["Defender", "Midfielder", "Forward", "Goalkeeper"].includes(preferred)) {
    return exactPosition(player.position || preferred);
  }
  return exactPosition(preferred);
}

function compatibilityPenalty(player: PlayerData, position: string): number {
  const exact = exactPosition(position);
  const primary = primaryPosition(player);
  if (primary === exact) return 0;

  const alternates = (player.alternate_positions || []).map(exactPosition);
  if (alternates.includes(exact)) return 4;
  if (positionGroup(primary) === positionGroup(exact)) return 8;
  return 14;
}

function sideForPosition(position: string): "Left" | "Right" | null {
  switch (exactPosition(position)) {
    case "LeftBack":
    case "LeftWingBack":
    case "LeftMidfielder":
    case "LeftWinger":
      return "Left";
    case "RightBack":
    case "RightWingBack":
    case "RightMidfielder":
    case "RightWinger":
      return "Right";
    default:
      return null;
  }
}

function footednessPenalty(player: PlayerData, position: string): number {
  const side = sideForPosition(position);
  if (!side) return 0;

  const footedness = player.footedness || "Right";
  if (footedness === "Both" || footedness === side) return 0;

  const weakFoot = Math.max(1, Math.min(5, player.weak_foot ?? 2));
  return Math.max(0, 10 - weakFoot * 2);
}

function weightedPositionScore(player: PlayerData, position: string): number {
  const a = player.attributes;
  switch (exactPosition(position)) {
    case "Goalkeeper":
      return weightedAverage([
        [a.handling, 28],
        [a.reflexes, 28],
        [a.aerial, 14],
        [a.positioning, 10],
        [a.decisions, 10],
        [a.composure, 5],
        [a.strength, 5],
      ]);
    case "RightBack":
    case "LeftBack":
      return weightedAverage([
        [a.pace, 18],
        [a.stamina, 16],
        [a.tackling, 17],
        [a.defending, 16],
        [a.positioning, 12],
        [a.passing, 10],
        [a.dribbling, 6],
        [a.decisions, 5],
      ]);
    case "CenterBack":
      return weightedAverage([
        [a.defending, 24],
        [a.tackling, 18],
        [a.positioning, 18],
        [a.strength, 14],
        [a.aerial, 12],
        [a.decisions, 8],
        [a.composure, 6],
      ]);
    case "RightWingBack":
    case "LeftWingBack":
      return weightedAverage([
        [a.pace, 18],
        [a.stamina, 18],
        [a.tackling, 14],
        [a.defending, 12],
        [a.passing, 13],
        [a.dribbling, 11],
        [a.vision, 7],
        [a.decisions, 7],
      ]);
    case "DefensiveMidfielder":
      return weightedAverage([
        [a.tackling, 18],
        [a.positioning, 18],
        [a.decisions, 16],
        [a.passing, 14],
        [a.defending, 12],
        [a.stamina, 10],
        [a.vision, 7],
        [a.strength, 5],
      ]);
    case "CentralMidfielder":
      return weightedAverage([
        [a.passing, 20],
        [a.vision, 16],
        [a.decisions, 16],
        [a.stamina, 12],
        [a.dribbling, 10],
        [a.positioning, 9],
        [a.teamwork, 9],
        [a.tackling, 8],
      ]);
    case "AttackingMidfielder":
      return weightedAverage([
        [a.vision, 20],
        [a.passing, 18],
        [a.dribbling, 16],
        [a.decisions, 14],
        [a.shooting, 10],
        [a.positioning, 8],
        [a.composure, 8],
        [a.pace, 6],
      ]);
    case "RightMidfielder":
    case "LeftMidfielder":
      return weightedAverage([
        [a.pace, 17],
        [a.stamina, 16],
        [a.passing, 15],
        [a.dribbling, 14],
        [a.vision, 10],
        [a.decisions, 10],
        [a.positioning, 10],
        [a.tackling, 8],
      ]);
    case "RightWinger":
    case "LeftWinger":
      return weightedAverage([
        [a.pace, 22],
        [a.dribbling, 22],
        [a.passing, 14],
        [a.shooting, 12],
        [a.vision, 10],
        [a.decisions, 8],
        [a.positioning, 6],
        [a.stamina, 6],
      ]);
    case "Striker":
      return weightedAverage([
        [a.shooting, 26],
        [a.positioning, 18],
        [a.decisions, 14],
        [a.pace, 12],
        [a.dribbling, 10],
        [a.strength, 8],
        [a.composure, 8],
        [a.aerial, 4],
      ]);
    default:
      return weightedAverage([
        [a.pace, 10],
        [a.stamina, 10],
        [a.strength, 10],
        [a.passing, 10],
        [a.shooting, 10],
        [a.tackling, 10],
        [a.dribbling, 10],
        [a.defending, 10],
        [a.positioning, 10],
        [a.vision, 5],
        [a.decisions, 5],
      ]);
  }
}

function criticalPenalty(player: PlayerData, position: string): number {
  const a = player.attributes;
  let criticalMin = 50;

  switch (exactPosition(position)) {
    case "Goalkeeper":
      criticalMin = Math.min(a.handling, a.reflexes, a.positioning);
      break;
    case "RightBack":
    case "LeftBack":
      criticalMin = Math.min(a.tackling, a.defending, a.positioning);
      break;
    case "CenterBack":
      criticalMin = Math.min(a.defending, a.tackling, a.positioning);
      break;
    case "RightWingBack":
    case "LeftWingBack":
      criticalMin = Math.min(a.pace, a.stamina, a.tackling);
      break;
    case "DefensiveMidfielder":
      criticalMin = Math.min(a.tackling, a.positioning, a.passing);
      break;
    case "CentralMidfielder":
      criticalMin = Math.min(a.passing, a.vision, a.decisions);
      break;
    case "AttackingMidfielder":
      criticalMin = Math.min(a.vision, a.passing, a.dribbling);
      break;
    case "RightMidfielder":
    case "LeftMidfielder":
      criticalMin = Math.min(a.pace, a.passing, a.stamina);
      break;
    case "RightWinger":
    case "LeftWinger":
      criticalMin = Math.min(a.pace, a.dribbling, a.passing);
      break;
    case "Striker":
      criticalMin = Math.min(a.shooting, a.positioning, a.decisions);
      break;
  }

  return criticalMin >= 45 ? 0 : (45 - criticalMin) * 0.6;
}

export function getTeamName(teams: TeamData[], id: string | null): string {
  if (!id) return "Free Agent";
  return teams.find(t => t.id === id)?.name ?? "Unknown";
}

export function getTeamShort(teams: TeamData[], id: string): string {
  return teams.find(t => t.id === id)?.short_name ?? "???";
}

export function isCompetitiveFixture(fixture: FixtureData): boolean {
  return !fixture.competition || fixture.competition === "League";
}

export function getCompetitiveFixtures(fixtures: FixtureData[]): FixtureData[] {
  return fixtures.filter(isCompetitiveFixture);
}

export function findNextFixture(fixtures: FixtureData[], teamId: string): FixtureData | undefined {
  return fixtures.find(f =>
    f.status === "Scheduled" && (f.home_team_id === teamId || f.away_team_id === teamId)
  );
}

export function expectedFixtureCount(teamCount: number): number | null {
  if (teamCount >= 2 && teamCount % 2 === 0) {
    return teamCount * (teamCount - 1);
  }

  return null;
}

export function hasFullLeagueSchedule(league: LeagueData): boolean {
  const expectedCount = expectedFixtureCount(league.standings.length);

  if (expectedCount === null) {
    return false;
  }

  return getCompetitiveFixtures(league.fixtures).length === expectedCount;
}

export function isSeasonComplete(league: LeagueData | null | undefined): boolean {
  if (!league || !hasFullLeagueSchedule(league)) {
    return false;
  }

  return getCompetitiveFixtures(league.fixtures).every((fixture) => fixture.status === "Completed");
}

const LANG_LOCALE: Record<string, string> = { en: "en-US", es: "es-ES", pt: "pt-BR", fr: "fr-FR", de: "de-DE", it: "it-IT" };

export function getLocale(lang?: string): string {
  if (!lang) return "en-US";
  return LANG_LOCALE[lang] || lang;
}

function parseDateInput(dateStr: string): Date | null {
  const value = /^\d{4}-\d{2}-\d{2}$/.test(dateStr)
    ? new Date(`${dateStr}T00:00:00`)
    : new Date(dateStr);

  if (Number.isNaN(value.getTime())) {
    return null;
  }

  return value;
}

export function formatMatchDate(dateStr: string, locale?: string): string {
  const d = parseDateInput(dateStr);
  if (!d) return dateStr;
  return d.toLocaleDateString(getLocale(locale), { weekday: "short", month: "short", day: "numeric" });
}

export function formatDate(dateStr: string, locale?: string, opts?: Intl.DateTimeFormatOptions): string {
  const d = parseDateInput(dateStr);
  if (!d) return dateStr;
  return d.toLocaleDateString(getLocale(locale), opts || { year: "numeric", month: "long", day: "numeric" });
}

export function formatDateFull(dateStr: string, locale?: string): string {
  const d = parseDateInput(dateStr);
  if (!d) return dateStr;
  return d.toLocaleDateString(getLocale(locale), { weekday: "long", year: "numeric", month: "long", day: "numeric" });
}

export function formatDateShort(dateStr: string, locale?: string): string {
  const d = parseDateInput(dateStr);
  if (!d) return dateStr;
  return d.toLocaleDateString(getLocale(locale), { month: "short", day: "numeric" });
}

export function calcOvr(player: PlayerData, position?: string): number {
  const targetPosition = position ? exactPosition(position) : primaryPosition(player);
  const weightedScore = weightedPositionScore(player, targetPosition);
  const penalty = criticalPenalty(player, targetPosition);
  const fitPenalty = position ? compatibilityPenalty(player, targetPosition) : 0;
  const sidePenalty = position ? footednessPenalty(player, targetPosition) : 0;

  return Math.round(
    Math.max(1, Math.min(99, weightedScore - penalty - fitPenalty - sidePenalty)),
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
    case "Goalkeeper":
      return "accent";
    case "Defender":
    case "RightBack":
    case "CenterBack":
    case "LeftBack":
    case "RightWingBack":
    case "LeftWingBack":
      return "primary";
    case "Midfielder":
    case "DefensiveMidfielder":
    case "CentralMidfielder":
    case "AttackingMidfielder":
    case "RightMidfielder":
    case "LeftMidfielder":
      return "success";
    case "Forward":
    case "RightWinger":
    case "LeftWinger":
    case "Striker":
      return "danger";
    default:
      return "primary";
  }
}
