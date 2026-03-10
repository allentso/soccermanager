import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { formatDate, formatWeeklyAmount } from "../lib/helpers";
import { PlayerData, TeamData, GameStateData } from "../store/gameStore";
import { Card, CardHeader, CardBody, Badge, ProgressBar } from "./ui";
import {
  ArrowLeft,
  Shield,
  TrendingUp,
  Calendar,
  Briefcase,
  DollarSign,
  Heart,
  Activity,
  AlertTriangle,
  ScanSearch,
} from "lucide-react";
import { TraitList } from "./TraitBadge";
import { useTranslation } from "react-i18next";
import { countryFlag, countryName } from "../lib/countries";

interface PlayerProfileProps {
  player: PlayerData;
  gameState: GameStateData;
  isOwnClub: boolean;
  onClose: () => void;
  onSelectTeam?: (id: string) => void;
  onGameUpdate?: (g: GameStateData) => void;
}

function getTeamNameLocal(
  teams: TeamData[],
  id: string | null,
  freeAgent: string,
  unknown: string,
): string {
  if (!id) return freeAgent;
  return teams.find((t) => t.id === id)?.name ?? unknown;
}

function calcOvr(p: PlayerData): number {
  const a = p.attributes;
  return Math.round(
    (a.pace +
      a.stamina +
      a.strength +
      a.passing +
      a.shooting +
      a.tackling +
      a.dribbling +
      a.defending +
      a.positioning +
      a.vision +
      a.decisions) /
      11,
  );
}

function calcAge(dob: string): number {
  const birth = new Date(dob);
  const now = new Date("2026-07-01");
  let age = now.getFullYear() - birth.getFullYear();
  if (
    now.getMonth() < birth.getMonth() ||
    (now.getMonth() === birth.getMonth() && now.getDate() < birth.getDate())
  ) {
    age--;
  }
  return age;
}

function formatValue(val: number): string {
  if (val >= 1_000_000) return `€${(val / 1_000_000).toFixed(1)}M`;
  if (val >= 1_000) return `€${(val / 1_000).toFixed(0)}K`;
  return `€${val}`;
}

function formatWage(val: number, weeklySuffix: string): string {
  return formatWeeklyAmount(`€${val.toLocaleString()}`, weeklySuffix);
}

const positionBadgeVariant = (
  pos: string,
): "accent" | "primary" | "success" | "danger" => {
  switch (pos) {
    case "Goalkeeper":
      return "accent";
    case "Defender":
      return "primary";
    case "Midfielder":
      return "success";
    case "Forward":
      return "danger";
    default:
      return "primary";
  }
};

function attrColor(val: number): string {
  if (val >= 80) return "text-primary-500 dark:text-primary-400";
  if (val >= 60) return "text-accent-600 dark:text-accent-400";
  if (val >= 40) return "text-gray-600 dark:text-gray-400";
  return "text-red-500 dark:text-red-400";
}

export default function PlayerProfile({
  player,
  gameState,
  isOwnClub,
  onClose,
  onSelectTeam,
  onGameUpdate,
}: PlayerProfileProps) {
  const { t, i18n } = useTranslation();
  const weeklySuffix = t("finances.perWeekSuffix", "/wk");

  const resolveInjuryName = (injuryName: string): string => {
    if (injuryName.includes(".")) {
      return t(injuryName, { defaultValue: injuryName });
    }

    return t(`common.injuries.${injuryName}`, { defaultValue: injuryName });
  };

  if (!player) {
    return null;
  }

  const [scoutStatus, setScoutStatus] = useState<
    "idle" | "sending" | "sent" | "error"
  >("idle");
  const [scoutError, setScoutError] = useState<string | null>(null);
  const ovr = calcOvr(player);
  const age = calcAge(player.date_of_birth);
  const teamName = getTeamNameLocal(
    gameState.teams,
    player.team_id,
    t("common.freeAgent"),
    t("common.unknown"),
  );

  const isGK = player.position === "Goalkeeper";

  const attrGroups = [
    {
      label: t("common.attrGroups.physical"),
      attrs: [
        { name: t("common.attributes.pace"), value: player.attributes.pace },
        {
          name: t("common.attributes.stamina"),
          value: player.attributes.stamina,
        },
        {
          name: t("common.attributes.strength"),
          value: player.attributes.strength,
        },
        {
          name: t("common.attributes.agility"),
          value: player.attributes.agility,
        },
      ],
    },
    {
      label: t("common.attrGroups.technical"),
      attrs: [
        {
          name: t("common.attributes.passing"),
          value: player.attributes.passing,
        },
        {
          name: t("common.attributes.shooting"),
          value: player.attributes.shooting,
        },
        {
          name: t("common.attributes.tackling"),
          value: player.attributes.tackling,
        },
        {
          name: t("common.attributes.dribbling"),
          value: player.attributes.dribbling,
        },
        {
          name: t("common.attributes.defending"),
          value: player.attributes.defending,
        },
      ],
    },
    {
      label: t("common.attrGroups.mental"),
      attrs: [
        {
          name: t("common.attributes.positioning"),
          value: player.attributes.positioning,
        },
        {
          name: t("common.attributes.vision"),
          value: player.attributes.vision,
        },
        {
          name: t("common.attributes.decisions"),
          value: player.attributes.decisions,
        },
        {
          name: t("common.attributes.composure"),
          value: player.attributes.composure,
        },
        {
          name: t("common.attributes.aggression"),
          value: player.attributes.aggression,
        },
        {
          name: t("common.attributes.teamwork"),
          value: player.attributes.teamwork,
        },
        {
          name: t("common.attributes.leadership"),
          value: player.attributes.leadership,
        },
      ],
    },
    ...(isGK
      ? [
          {
            label: t("common.attrGroups.goalkeeper"),
            attrs: [
              {
                name: t("common.attributes.handling"),
                value: player.attributes.handling,
              },
              {
                name: t("common.attributes.reflexes"),
                value: player.attributes.reflexes,
              },
              {
                name: t("common.attributes.aerial"),
                value: player.attributes.aerial,
              },
            ],
          },
        ]
      : []),
  ];

  return (
    <div className="max-w-6xl mx-auto">
      {/* Back button */}
      <button
        onClick={onClose}
        className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-800 dark:hover:text-gray-200 transition-colors mb-4"
      >
        <ArrowLeft className="w-4 h-4" />
        <span className="font-heading font-bold uppercase tracking-wider">
          {t("common.back")}
        </span>
      </button>

      {/* Hero header */}
      <Card accent="primary" className="mb-5">
        <div className="bg-gradient-to-r from-navy-700 to-navy-800 p-8 rounded-t-xl">
          <div className="flex items-start gap-6">
            <div
              className={`w-24 h-24 rounded-2xl flex items-center justify-center font-heading font-bold text-4xl border-2 ${
                ovr >= 75
                  ? "bg-primary-500/20 text-primary-400 border-primary-500/30"
                  : ovr >= 55
                    ? "bg-accent-500/20 text-accent-400 border-accent-500/30"
                    : "bg-gray-500/20 text-gray-400 border-gray-500/30"
              }`}
            >
              {ovr}
            </div>
            <div className="flex-1">
              <h2 className="text-3xl font-heading font-bold text-white uppercase tracking-wide">
                {player.full_name}
              </h2>
              <div className="flex items-center gap-3 mt-2">
                <Badge
                  variant={positionBadgeVariant(
                    player.natural_position || player.position,
                  )}
                >
                  {player.natural_position || player.position}
                </Badge>
                {player.alternate_positions?.map((ap) => (
                  <span key={ap} title={`Can also play ${ap}`}>
                    <Badge variant="neutral">{ap}</Badge>
                  </span>
                ))}
                <span className="text-gray-400 text-sm">
                  <span className="mr-1">
                    {countryFlag(player.nationality)}
                  </span>
                  {countryName(player.nationality, i18n.language)}
                </span>
                <span className="text-gray-500">•</span>
                <span className="text-gray-400 text-sm">
                  {t("common.age")} {age}
                </span>
              </div>
              <p className="text-gray-400 text-sm mt-2 flex items-center gap-1.5">
                <Shield className="w-4 h-4" />
                {player.team_id ? (
                  <button
                    onClick={() => onSelectTeam?.(player.team_id!)}
                    className="hover:text-primary-400 transition-colors underline underline-offset-2"
                  >
                    {teamName}
                  </button>
                ) : (
                  <span>{teamName}</span>
                )}
              </p>
              {player.traits && player.traits.length > 0 && (
                <div className="mt-3">
                  <TraitList traits={player.traits} size="sm" />
                </div>
              )}
            </div>

            {/* Scout button for non-own players */}
            {!isOwnClub &&
              onGameUpdate &&
              (() => {
                const scouts = gameState.staff.filter(
                  (s) =>
                    s.role === "Scout" &&
                    s.team_id === gameState.manager.team_id,
                );
                const alreadyScouting = (
                  gameState.scouting_assignments || []
                ).some((a) => a.player_id === player.id);
                const allBusy =
                  scouts.length > 0 &&
                  scouts.every((s) =>
                    (gameState.scouting_assignments || []).some(
                      (a) => a.scout_id === s.id,
                    ),
                  );
                const canScout =
                  scouts.length > 0 &&
                  !alreadyScouting &&
                  !allBusy &&
                  scoutStatus !== "sent";
                return (
                  <div className="mt-3">
                    {scouts.length === 0 ? (
                      <p className="text-xs text-gray-500">
                        Hire a scout to evaluate players
                      </p>
                    ) : alreadyScouting || scoutStatus === "sent" ? (
                      <span className="text-xs text-primary-400 font-heading font-bold uppercase tracking-wider flex items-center gap-1.5">
                        <ScanSearch className="w-3.5 h-3.5" /> Scouting in
                        progress
                      </span>
                    ) : (
                      <button
                        disabled={!canScout || scoutStatus === "sending"}
                        onClick={async () => {
                          const availableScout = scouts.find(
                            (s) =>
                              !(gameState.scouting_assignments || []).some(
                                (a) => a.scout_id === s.id,
                              ),
                          );
                          if (!availableScout) return;
                          setScoutStatus("sending");
                          setScoutError(null);
                          try {
                            const updated = await invoke<GameStateData>(
                              "send_scout",
                              {
                                scoutId: availableScout.id,
                                playerId: player.id,
                              },
                            );
                            onGameUpdate(updated);
                            setScoutStatus("sent");
                          } catch (err) {
                            setScoutError(String(err));
                            setScoutStatus("error");
                          }
                        }}
                        className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-primary-500/20 text-primary-400 hover:bg-primary-500/30 transition-colors text-xs font-heading font-bold uppercase tracking-wider disabled:opacity-50"
                      >
                        <ScanSearch className="w-3.5 h-3.5" />
                        {scoutStatus === "sending"
                          ? "Sending..."
                          : "Scout Player"}
                      </button>
                    )}
                    {scoutError && (
                      <p className="text-xs text-red-400 mt-1">{scoutError}</p>
                    )}
                  </div>
                );
              })()}

            {/* Key stats in header */}
            <div className="hidden md:grid grid-cols-2 gap-3">
              <div className="bg-white/5 rounded-xl px-5 py-3 text-center min-w-[100px]">
                <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">
                  {t("common.condition")}
                </p>
                <p
                  className={`font-heading font-bold text-xl mt-0.5 ${player.condition >= 70 ? "text-primary-400" : "text-red-400"}`}
                >
                  {player.condition}%
                </p>
              </div>
              <div className="bg-white/5 rounded-xl px-5 py-3 text-center min-w-[100px]">
                <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">
                  {t("common.morale")}
                </p>
                <p
                  className={`font-heading font-bold text-xl mt-0.5 ${player.morale >= 70 ? "text-primary-400" : "text-accent-400"}`}
                >
                  {player.morale}%
                </p>
              </div>
              <div className="bg-white/5 rounded-xl px-5 py-3 text-center min-w-[100px]">
                <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">
                  {t("common.value")}
                </p>
                <p className="font-heading font-bold text-xl mt-0.5 text-white">
                  {formatValue(player.market_value)}
                </p>
              </div>
              <div className="bg-white/5 rounded-xl px-5 py-3 text-center min-w-[100px]">
                <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">
                  {t("common.wage")}
                </p>
                <p className="font-heading font-bold text-xl mt-0.5 text-white">
                  {formatWage(player.wage, weeklySuffix)}
                </p>
              </div>
            </div>
          </div>
        </div>

        {/* Mobile-only quick stats */}
        <div className="grid grid-cols-4 gap-px bg-gray-200 dark:bg-navy-600 md:hidden">
          <QuickStat
            label={t("common.condition")}
            value={`${player.condition}%`}
            color={player.condition >= 70 ? "text-primary-500" : "text-red-500"}
          />
          <QuickStat
            label={t("common.morale")}
            value={`${player.morale}%`}
            color={player.morale >= 70 ? "text-primary-500" : "text-accent-500"}
          />
          <QuickStat
            label={t("common.value")}
            value={formatValue(player.market_value)}
            color="text-gray-700 dark:text-gray-200"
          />
          <QuickStat
            label={t("common.wage")}
            value={formatWage(player.wage, weeklySuffix)}
            color="text-gray-700 dark:text-gray-200"
          />
        </div>
      </Card>

      {/* Injury banner */}
      {player.injury && (
        <Card accent="danger" className="mb-5">
          <CardBody>
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-red-500/10 flex items-center justify-center">
                <AlertTriangle className="w-5 h-5 text-red-500" />
              </div>
              <div>
                <p className="font-semibold text-sm text-red-600 dark:text-red-400">
                  {resolveInjuryName(player.injury.name)}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400">
                  {t("playerProfile.daysRemaining", {
                    count: player.injury.days_remaining,
                  })}
                </p>
              </div>
            </div>
          </CardBody>
        </Card>
      )}

      {/* Main content grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
        {/* Contract & Personal Info */}
        <Card>
          <CardHeader>{t("playerProfile.contractInfo")}</CardHeader>
          <CardBody>
            <div className="flex flex-col gap-3">
              <InfoRow
                icon={<Calendar className="w-4 h-4" />}
                label={t("playerProfile.dateOfBirth")}
                value={formatDate(player.date_of_birth, i18n.language)}
              />
              <InfoRow
                icon={<Briefcase className="w-4 h-4" />}
                label={t("common.contract")}
                value={
                  player.contract_end
                    ? t("finances.until", {
                        year: player.contract_end.substring(0, 4),
                      })
                    : t("playerProfile.noContract")
                }
              />
              <InfoRow
                icon={<DollarSign className="w-4 h-4" />}
                label={t("finances.marketValue")}
                value={formatValue(player.market_value)}
              />
              <InfoRow
                icon={<TrendingUp className="w-4 h-4" />}
                label={t("playerProfile.weeklyWage")}
                value={formatWage(player.wage, weeklySuffix)}
              />
              <InfoRow
                icon={<Heart className="w-4 h-4" />}
                label={t("common.condition")}
                value={`${player.condition}%`}
              />
              <InfoRow
                icon={<Activity className="w-4 h-4" />}
                label={t("common.morale")}
                value={`${player.morale}%`}
              />
            </div>
          </CardBody>
        </Card>

        {/* Attributes — takes 2 cols */}
        <Card className="lg:col-span-2">
          <CardHeader>{t("playerProfile.attributes")}</CardHeader>
          <CardBody>
            {isOwnClub ? (
              <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                {attrGroups.map((group) => (
                  <div key={group.label}>
                    <h4 className="font-heading font-bold text-xs uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-3 pb-2 border-b border-gray-100 dark:border-navy-600">
                      {group.label}
                    </h4>
                    <div className="flex flex-col gap-2.5">
                      {group.attrs.map((attr) => (
                        <div
                          key={attr.name}
                          className="flex items-center gap-3"
                        >
                          <span className="text-sm text-gray-600 dark:text-gray-400 w-24">
                            {attr.name}
                          </span>
                          <ProgressBar
                            value={attr.value}
                            variant="auto"
                            size="sm"
                            className="flex-1"
                          />
                          <span
                            className={`font-heading font-bold text-sm w-8 text-right tabular-nums ${attrColor(attr.value)}`}
                          >
                            {attr.value}
                          </span>
                        </div>
                      ))}
                      <div className="pt-1 border-t border-gray-100 dark:border-navy-600 flex items-center gap-3">
                        <span className="text-sm text-gray-500 dark:text-gray-400 w-24 font-semibold">
                          {t("common.average")}
                        </span>
                        <span className="flex-1" />
                        <span className="font-heading font-bold text-sm w-8 text-right tabular-nums text-gray-700 dark:text-gray-200">
                          {Math.round(
                            group.attrs.reduce((s, a) => s + a.value, 0) /
                              group.attrs.length,
                          )}
                        </span>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-center py-8">
                <div className="w-14 h-14 rounded-full bg-gray-100 dark:bg-navy-700 flex items-center justify-center mx-auto mb-4">
                  <Shield className="w-7 h-7 text-gray-400 dark:text-gray-500" />
                </div>
                <p className="text-sm text-gray-500 dark:text-gray-400 font-medium">
                  {t("playerProfile.attributesHidden")}
                </p>
                <p className="text-xs text-gray-400 dark:text-gray-500 mt-1 max-w-xs mx-auto">
                  {t("playerProfile.scoutToView")}
                </p>
                <div className="mt-6 grid grid-cols-1 md:grid-cols-3 gap-6 text-left">
                  {attrGroups.map((group) => (
                    <div key={group.label}>
                      <h4 className="font-heading font-bold text-xs uppercase tracking-wider text-gray-400 dark:text-gray-500 mb-2">
                        {group.label}
                      </h4>
                      {group.attrs.map((attr) => (
                        <div
                          key={attr.name}
                          className="flex items-center gap-3 mb-1.5"
                        >
                          <span className="text-xs text-gray-400 dark:text-gray-500 w-24">
                            {attr.name}
                          </span>
                          <div className="flex-1 h-2 bg-gray-200 dark:bg-navy-600 rounded-full overflow-hidden">
                            <div
                              className="h-full bg-gray-300 dark:bg-navy-500 rounded-full"
                              style={{ width: `${Math.random() * 60 + 20}%` }}
                            />
                          </div>
                          <span className="text-xs text-gray-400 dark:text-gray-500 w-6 text-right">
                            ??
                          </span>
                        </div>
                      ))}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </CardBody>
        </Card>

        {/* Season Stats */}
        <Card className="lg:col-span-2">
          <CardHeader>{t("playerProfile.seasonStats")}</CardHeader>
          <CardBody>
            <div className="grid grid-cols-4 md:grid-cols-8 gap-3">
              <StatBox
                label={t("playerProfile.apps")}
                value={player.stats.appearances}
              />
              <StatBox
                label={t("playerProfile.goals")}
                value={player.stats.goals}
              />
              <StatBox
                label={t("playerProfile.assists")}
                value={player.stats.assists}
              />
              <StatBox
                label={t("playerProfile.mins")}
                value={player.stats.minutes_played}
              />
              <StatBox
                label={t("playerProfile.cleanSheets")}
                value={player.stats.clean_sheets}
              />
              <StatBox
                label={t("playerProfile.yellows")}
                value={player.stats.yellow_cards}
              />
              <StatBox
                label={t("playerProfile.reds")}
                value={player.stats.red_cards}
              />
              <StatBox
                label={t("playerProfile.avgRating")}
                value={
                  player.stats.avg_rating > 0
                    ? player.stats.avg_rating.toFixed(1)
                    : "-"
                }
              />
            </div>
          </CardBody>
        </Card>

        {/* Career history */}
        <Card>
          <CardHeader>{t("playerProfile.careerHistory")}</CardHeader>
          <CardBody>
            {player.career.length > 0 ? (
              <div className="flex flex-col gap-2">
                {player.career.map((entry, i) => (
                  <div
                    key={i}
                    className="flex items-center justify-between text-sm py-2 border-b border-gray-100 dark:border-navy-600 last:border-0"
                  >
                    <div>
                      <span className="font-semibold text-gray-800 dark:text-gray-200">
                        {entry.team_name}
                      </span>
                      <span className="text-gray-400 dark:text-gray-500 ml-2 text-xs">
                        {entry.season}/{entry.season + 1}
                      </span>
                    </div>
                    <div className="text-xs text-gray-500 dark:text-gray-400 flex gap-3">
                      <span>
                        {t("playerProfile.nApps", { count: entry.appearances })}
                      </span>
                      <span>
                        {t("playerProfile.nGoals", { count: entry.goals })}
                      </span>
                      <span>
                        {t("playerProfile.nAssists", { count: entry.assists })}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-sm text-gray-400 dark:text-gray-500 text-center py-4">
                {t("playerProfile.noCareer")}
              </p>
            )}
          </CardBody>
        </Card>
      </div>
    </div>
  );
}

function QuickStat({
  label,
  value,
  color,
}: {
  label: string;
  value: string;
  color: string;
}) {
  return (
    <div className="bg-white dark:bg-navy-800 p-3 text-center">
      <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase tracking-wider">
        {label}
      </p>
      <p className={`font-heading font-bold text-lg mt-0.5 ${color}`}>
        {value}
      </p>
    </div>
  );
}

function InfoRow({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
}) {
  return (
    <div className="flex items-center gap-3 py-2 border-b border-gray-100 dark:border-navy-600 last:border-0">
      <div className="text-gray-400 dark:text-gray-500">{icon}</div>
      <span className="text-sm text-gray-500 dark:text-gray-400 flex-1">
        {label}
      </span>
      <span className="text-sm font-semibold text-gray-800 dark:text-gray-200">
        {value}
      </span>
    </div>
  );
}

function StatBox({ label, value }: { label: string; value: number | string }) {
  return (
    <div className="text-center p-2.5 bg-gray-50 dark:bg-navy-700 rounded-lg">
      <p className="font-heading font-bold text-lg text-gray-800 dark:text-gray-100 tabular-nums">
        {value}
      </p>
      <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase tracking-wider">
        {label}
      </p>
    </div>
  );
}
