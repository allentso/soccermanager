import { useState, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { GameStateData } from "../store/gameStore";
import { Card, CardHeader, CardBody, ProgressBar, Select } from "./ui";
import {
  HeartPulse,
  Crosshair,
  Brain,
  Shield,
  Zap,
  BedDouble,
  Gauge,
  Flame,
  Scale,
  Feather,
  AlertTriangle,
  Info,
  Plus,
  Trash2,
  Users,
} from "lucide-react";
import { useTranslation } from "react-i18next";

interface TrainingTabProps {
  gameState: GameStateData;
  onGameUpdate?: (state: GameStateData) => void;
}

const TRAINING_FOCUS_IDS = [
  "Physical",
  "Technical",
  "Tactical",
  "Defending",
  "Attacking",
  "Recovery",
] as const;
const TRAINING_FOCUS_ICONS: Record<string, React.ReactNode> = {
  Physical: <HeartPulse className="w-6 h-6" />,
  Technical: <Crosshair className="w-6 h-6" />,
  Tactical: <Brain className="w-6 h-6" />,
  Defending: <Shield className="w-6 h-6" />,
  Attacking: <Zap className="w-6 h-6" />,
  Recovery: <BedDouble className="w-6 h-6" />,
};
const TRAINING_FOCUS_ATTRS: Record<string, string[]> = {
  Physical: ["pace", "stamina", "strength", "agility"],
  Technical: ["passing", "shooting", "dribbling"],
  Tactical: ["positioning", "vision", "decisions", "composure"],
  Defending: ["tackling", "defending", "strength", "positioning"],
  Attacking: ["shooting", "dribbling", "pace"],
  Recovery: [],
};

const INTENSITY_IDS = ["Low", "Medium", "High"] as const;
const INTENSITY_COLORS: Record<string, string> = {
  Low: "text-blue-500",
  Medium: "text-accent-500",
  High: "text-red-500",
};

const SCHEDULE_IDS = ["Intense", "Balanced", "Light"] as const;
const SCHEDULE_ICONS: Record<string, React.ReactNode> = {
  Intense: <Flame className="w-5 h-5" />,
  Balanced: <Scale className="w-5 h-5" />,
  Light: <Feather className="w-5 h-5" />,
};
const SCHEDULE_COLORS: Record<string, string> = {
  Intense: "text-red-500",
  Balanced: "text-primary-500",
  Light: "text-blue-500",
};

// Which days are training days per schedule (Mon=0..Sun=6)
const SCHEDULE_TRAINING_DAYS: Record<string, number[]> = {
  Intense: [0, 1, 2, 3, 4, 5], // Mon-Sat
  Balanced: [0, 1, 3, 4], // Mon, Tue, Thu, Fri
  Light: [1, 3], // Tue, Thu
};

const DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

function getWeekdayFromDate(dateStr: string): number {
  const d = new Date(dateStr);
  // JS: 0=Sun..6=Sat → convert to 0=Mon..6=Sun
  return (d.getUTCDay() + 6) % 7;
}

export default function TrainingTab({
  gameState,
  onGameUpdate,
}: TrainingTabProps) {
  const { t } = useTranslation();
  const myTeam = gameState.teams.find(
    (tm) => tm.id === gameState.manager.team_id,
  );
  if (!myTeam)
    return (
      <p className="text-gray-500 dark:text-gray-400">{t("common.noTeam")}</p>
    );

  const currentFocus = myTeam.training_focus || "Physical";
  const currentIntensity = myTeam.training_intensity || "Medium";
  const currentSchedule = myTeam.training_schedule || "Balanced";
  const [isSaving, setIsSaving] = useState(false);

  const roster = [...gameState.players.filter((p) => p.team_id === myTeam.id)];
  const avgCondition =
    roster.length > 0
      ? Math.round(roster.reduce((s, p) => s + p.condition, 0) / roster.length)
      : 0;
  const avgMorale =
    roster.length > 0
      ? Math.round(roster.reduce((s, p) => s + p.morale, 0) / roster.length)
      : 0;
  const exhaustedCount = roster.filter((p) => p.condition < 40).length;
  const criticalCount = roster.filter((p) => p.condition < 25).length;

  const todayWeekday = getWeekdayFromDate(gameState.clock.current_date);
  const trainingDays =
    SCHEDULE_TRAINING_DAYS[currentSchedule] || SCHEDULE_TRAINING_DAYS.Balanced;
  const isTodayTraining = trainingDays.includes(todayWeekday);

  const handleSetTraining = async (focus: string, intensity: string) => {
    setIsSaving(true);
    try {
      const updated = await invoke<GameStateData>("set_training", {
        focus,
        intensity,
      });
      onGameUpdate?.(updated);
    } catch (err) {
      console.error("Failed to set training:", err);
    } finally {
      setIsSaving(false);
    }
  };

  const handleSetSchedule = async (schedule: string) => {
    setIsSaving(true);
    try {
      const updated = await invoke<GameStateData>("set_training_schedule", {
        schedule,
      });
      onGameUpdate?.(updated);
    } catch (err) {
      console.error("Failed to set schedule:", err);
    } finally {
      setIsSaving(false);
    }
  };

  const activeFocusAttrs = TRAINING_FOCUS_ATTRS[currentFocus] || [];

  // Staff advice logic
  const getStaffAdvice = (): {
    level: "ok" | "warn" | "critical";
    message: string;
  } | null => {
    if (criticalCount >= 3) {
      const scheduleAdvice =
        currentSchedule === "Intense"
          ? "Switch to a Balanced or Light schedule immediately."
          : currentSchedule === "Balanced"
            ? "Consider a Light schedule or Recovery focus."
            : "Set focus to Recovery until fitness improves.";
      return {
        level: "critical",
        message: `Fitness crisis! ${criticalCount} players in critical condition. ${scheduleAdvice}`,
      };
    }
    if (avgCondition < 50 || exhaustedCount >= 4) {
      const scheduleAdvice =
        currentSchedule === "Intense"
          ? "A Balanced schedule would give more recovery time."
          : currentSchedule === "Balanced"
            ? "A Light schedule could help the squad bounce back."
            : "Recovery focus would maximise fitness recovery.";
      return {
        level: "warn",
        message: `Squad is tired (avg ${avgCondition}%, ${exhaustedCount} below 40%). ${scheduleAdvice}`,
      };
    }
    if (
      avgCondition >= 80 &&
      currentSchedule === "Light" &&
      currentFocus !== "Recovery"
    ) {
      return {
        level: "ok",
        message:
          "Squad fitness is high. You could switch to Balanced or Intense for more development.",
      };
    }
    return null;
  };

  const staffAdvice = getStaffAdvice();

  return (
    <div className="max-w-6xl mx-auto grid grid-cols-1 lg:grid-cols-3 gap-5">
      {/* Left column: Schedule + Focus + Intensity */}
      <div className="lg:col-span-2 flex flex-col gap-5">
        {/* Staff advice banner */}
        {staffAdvice && (
          <div
            className={`flex items-start gap-3 p-4 rounded-xl border-2 ${
              staffAdvice.level === "critical"
                ? "bg-red-50 dark:bg-red-500/10 border-red-300 dark:border-red-500/40"
                : staffAdvice.level === "warn"
                  ? "bg-amber-50 dark:bg-amber-500/10 border-amber-300 dark:border-amber-500/40"
                  : "bg-blue-50 dark:bg-blue-500/10 border-blue-300 dark:border-blue-500/40"
            }`}
          >
            {staffAdvice.level === "critical" ? (
              <AlertTriangle className="w-5 h-5 text-red-500 flex-shrink-0 mt-0.5" />
            ) : staffAdvice.level === "warn" ? (
              <AlertTriangle className="w-5 h-5 text-amber-500 flex-shrink-0 mt-0.5" />
            ) : (
              <Info className="w-5 h-5 text-blue-500 flex-shrink-0 mt-0.5" />
            )}
            <div>
              <p
                className={`text-xs font-heading font-bold uppercase tracking-wider mb-0.5 ${
                  staffAdvice.level === "critical"
                    ? "text-red-600 dark:text-red-400"
                    : staffAdvice.level === "warn"
                      ? "text-amber-600 dark:text-amber-400"
                      : "text-blue-600 dark:text-blue-400"
                }`}
              >
                {staffAdvice.level === "critical"
                  ? t("training.staffAlert")
                  : staffAdvice.level === "warn"
                    ? t("training.staffWarning")
                    : t("training.staffSuggestion")}
              </p>
              <p className="text-sm text-gray-700 dark:text-gray-300">
                {staffAdvice.message}
              </p>
            </div>
          </div>
        )}

        {/* Weekly schedule selector */}
        <Card accent="accent">
          <CardHeader>{t("training.weeklySchedule")}</CardHeader>
          <CardBody>
            <div className="flex gap-3 mb-4">
              {SCHEDULE_IDS.map((sId) => (
                <button
                  key={sId}
                  disabled={isSaving}
                  onClick={() => handleSetSchedule(sId)}
                  className={`flex-1 p-3 rounded-xl text-left transition-all border-2 ${
                    currentSchedule === sId
                      ? "border-primary-500 bg-primary-50 dark:bg-primary-500/10 shadow-md shadow-primary-500/10"
                      : "border-gray-200 dark:border-navy-600 hover:border-gray-300 dark:hover:border-navy-500"
                  } ${isSaving ? "opacity-60 pointer-events-none" : ""}`}
                >
                  <div className={`mb-1.5 ${SCHEDULE_COLORS[sId]}`}>
                    {SCHEDULE_ICONS[sId]}
                  </div>
                  <p className="font-heading font-bold text-sm uppercase tracking-wider text-gray-800 dark:text-gray-200">
                    {t(`training.schedules.${sId}.label`)}
                  </p>
                  <p className="text-[10px] text-gray-500 dark:text-gray-400 mt-0.5">
                    {t(`training.schedules.${sId}.desc`)}
                  </p>
                </button>
              ))}
            </div>

            {/* Weekly calendar visualization */}
            <div className="grid grid-cols-7 gap-1.5">
              {DAY_KEYS.map((dayKey, i) => {
                const isTraining = trainingDays.includes(i);
                const isToday = i === todayWeekday;
                return (
                  <div
                    key={dayKey}
                    className={`text-center py-2 rounded-lg transition-all ${
                      isToday
                        ? "ring-2 ring-accent-400 dark:ring-accent-500"
                        : ""
                    } ${
                      isTraining
                        ? "bg-primary-100 dark:bg-primary-500/15 text-primary-700 dark:text-primary-300"
                        : "bg-gray-50 dark:bg-navy-700/50 text-gray-400 dark:text-gray-500"
                    }`}
                  >
                    <p className="text-[10px] font-heading font-bold uppercase tracking-wider mb-0.5">
                      {t(`training.days.${dayKey}`)}
                    </p>
                    <p className="text-xs font-bold">
                      {isTraining ? t("training.train") : t("training.rest")}
                    </p>
                  </div>
                );
              })}
            </div>

            <p className="text-xs text-gray-400 dark:text-gray-500 mt-3">
              {t(`training.schedules.${currentSchedule}.detail`)}{" "}
              <span
                dangerouslySetInnerHTML={{
                  __html: t("training.todayIs", {
                    day: t(`training.days.${DAY_KEYS[todayWeekday]}`),
                    type: isTodayTraining
                      ? t("training.aTrainingDay")
                      : t("training.aRestDay"),
                  }),
                }}
              />
            </p>
          </CardBody>
        </Card>

        {/* Training focus selection */}
        <Card accent="primary">
          <CardHeader>{t("training.trainingFocus")}</CardHeader>
          <CardBody>
            <div className="grid grid-cols-3 gap-3">
              {TRAINING_FOCUS_IDS.map((fId) => (
                <button
                  key={fId}
                  disabled={isSaving}
                  onClick={() => handleSetTraining(fId, currentIntensity)}
                  className={`p-4 rounded-xl text-left transition-all border-2 ${
                    currentFocus === fId
                      ? "border-primary-500 bg-primary-50 dark:bg-primary-500/10 shadow-md shadow-primary-500/10"
                      : "border-gray-200 dark:border-navy-600 hover:border-gray-300 dark:hover:border-navy-500"
                  } ${isSaving ? "opacity-60 pointer-events-none" : ""}`}
                >
                  <div className="mb-2 text-gray-600 dark:text-gray-300">
                    {TRAINING_FOCUS_ICONS[fId]}
                  </div>
                  <p className="font-heading font-bold text-sm uppercase tracking-wider text-gray-800 dark:text-gray-200">
                    {t(`training.focuses.${fId}.label`)}
                  </p>
                  <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                    {t(`training.focuses.${fId}.desc`)}
                  </p>
                  {TRAINING_FOCUS_ATTRS[fId].length > 0 && (
                    <div className="flex flex-wrap gap-1 mt-2">
                      {TRAINING_FOCUS_ATTRS[fId].map((a) => (
                        <span
                          key={a}
                          className="text-[10px] bg-gray-100 dark:bg-navy-700 text-gray-500 dark:text-gray-400 px-1.5 py-0.5 rounded font-heading uppercase tracking-wider"
                        >
                          {t(`common.attributes.${a}`)}
                        </span>
                      ))}
                    </div>
                  )}
                </button>
              ))}
            </div>

            {/* Intensity selector */}
            <div className="mt-5 pt-4 border-t border-gray-100 dark:border-navy-700">
              <div className="flex items-center gap-2 mb-3">
                <Gauge className="w-4 h-4 text-gray-500 dark:text-gray-400" />
                <span className="text-xs font-heading font-bold uppercase tracking-widest text-gray-600 dark:text-gray-400">
                  {t("training.intensity")}
                </span>
              </div>
              <div className="flex gap-3">
                {INTENSITY_IDS.map((iId) => (
                  <button
                    key={iId}
                    disabled={isSaving}
                    onClick={() => handleSetTraining(currentFocus, iId)}
                    className={`flex-1 p-3 rounded-lg text-left transition-all border-2 ${
                      currentIntensity === iId
                        ? "border-primary-500 bg-primary-50 dark:bg-primary-500/10"
                        : "border-gray-200 dark:border-navy-600 hover:border-gray-300 dark:hover:border-navy-500"
                    } ${isSaving ? "opacity-60 pointer-events-none" : ""}`}
                  >
                    <p
                      className={`font-heading font-bold text-sm uppercase tracking-wider ${INTENSITY_COLORS[iId]}`}
                    >
                      {t(`training.intensities.${iId}.label`)}
                    </p>
                    <p className="text-[10px] text-gray-500 dark:text-gray-400 mt-0.5">
                      {t(`training.intensities.${iId}.desc`)}
                    </p>
                  </button>
                ))}
              </div>
            </div>

            <p className="text-xs text-gray-400 dark:text-gray-500 mt-4">
              {t("training.trainingAppliedNote")}
              {activeFocusAttrs.length > 0 && (
                <>
                  {" "}
                  <span
                    dangerouslySetInnerHTML={{
                      __html: t("training.currentlyTraining", {
                        attrs: activeFocusAttrs
                          .map((a) => t(`common.attributes.${a}`))
                          .join(", "),
                        intensity: t(
                          `training.intensities.${currentIntensity}.label`,
                        ),
                      }),
                    }}
                  />
                </>
              )}
              {currentFocus === "Recovery" && (
                <> {t("training.recoveryNote")}</>
              )}
            </p>
          </CardBody>
        </Card>

        {/* Training Groups */}
        <TrainingGroupsCard
          gameState={gameState}
          onGameUpdate={onGameUpdate}
          roster={roster}
          isSaving={isSaving}
          setIsSaving={setIsSaving}
        />
      </div>

      {/* Right column: Fitness overview */}
      <div className="flex flex-col gap-5">
        <Card accent="accent">
          <CardHeader>{t("training.squadFitness")}</CardHeader>
          <CardBody>
            <div className="flex flex-col gap-3">
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-gray-600 dark:text-gray-400">
                    {t("training.avgCondition")}
                  </span>
                  <span className="font-heading font-bold text-gray-800 dark:text-gray-100">
                    {avgCondition}%
                  </span>
                </div>
                <ProgressBar value={avgCondition} variant="auto" size="md" />
              </div>
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-gray-600 dark:text-gray-400">
                    {t("training.avgMorale")}
                  </span>
                  <span className="font-heading font-bold text-gray-800 dark:text-gray-100">
                    {avgMorale}%
                  </span>
                </div>
                <ProgressBar value={avgMorale} variant="auto" size="md" />
              </div>
              {(exhaustedCount > 0 || criticalCount > 0) && (
                <div className="mt-1 pt-2 border-t border-gray-100 dark:border-navy-700">
                  {criticalCount > 0 && (
                    <p className="text-xs text-red-500 dark:text-red-400 flex items-center gap-1">
                      <AlertTriangle className="w-3 h-3" />{" "}
                      {t("training.criticalCondition", {
                        count: criticalCount,
                      })}
                    </p>
                  )}
                  {exhaustedCount > 0 && (
                    <p className="text-xs text-amber-500 dark:text-amber-400 flex items-center gap-1 mt-0.5">
                      <AlertTriangle className="w-3 h-3" />{" "}
                      {t("training.exhaustedPlayers", {
                        count: exhaustedCount,
                      })}
                    </p>
                  )}
                </div>
              )}
            </div>
          </CardBody>
        </Card>

        <Card>
          <CardHeader>{t("training.playerFitness")}</CardHeader>
          <CardBody className="p-0 max-h-64 overflow-y-auto">
            <div className="divide-y divide-gray-100 dark:divide-navy-600">
              {roster
                .sort((a, b) => a.condition - b.condition)
                .map((p) => (
                  <div key={p.id} className="flex items-center px-4 py-2 gap-3">
                    <span
                      className={`text-sm font-medium flex-1 truncate ${
                        p.condition < 25
                          ? "text-red-600 dark:text-red-400"
                          : p.condition < 40
                            ? "text-amber-600 dark:text-amber-400"
                            : "text-gray-800 dark:text-gray-200"
                      }`}
                    >
                      {p.match_name}
                    </span>
                    <ProgressBar
                      value={p.condition}
                      variant="auto"
                      size="sm"
                      showLabel
                      className="w-24"
                    />
                  </div>
                ))}
            </div>
          </CardBody>
        </Card>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Training Groups sub-component
// ---------------------------------------------------------------------------

interface TrainingGroup {
  id: string;
  name: string;
  focus: string;
  player_ids: string[];
}

interface TrainingGroupsCardProps {
  gameState: GameStateData;
  onGameUpdate?: (state: GameStateData) => void;
  roster: GameStateData["players"];
  isSaving: boolean;
  setIsSaving: (v: boolean) => void;
}

function TrainingGroupsCard({
  gameState,
  onGameUpdate,
  roster,
  isSaving,
  setIsSaving,
}: TrainingGroupsCardProps) {
  const { t } = useTranslation();
  const myTeam = gameState.teams.find(
    (tm) => tm.id === gameState.manager.team_id,
  );
  const groups: TrainingGroup[] = (myTeam as any)?.training_groups ?? [];
  const teamFocus = myTeam?.training_focus || "Physical";

  const saveGroups = useCallback(
    async (newGroups: TrainingGroup[]) => {
      setIsSaving(true);
      try {
        const updated = await invoke<GameStateData>("set_training_groups", {
          groups: newGroups,
        });
        onGameUpdate?.(updated);
      } catch (err) {
        console.error("Failed to save training groups:", err);
      } finally {
        setIsSaving(false);
      }
    },
    [onGameUpdate, setIsSaving],
  );

  const addGroup = () => {
    if (groups.length >= 5) return;
    const idx = groups.length;
    const defaultName = t(
      `training.groups.defaultGroupNames.${idx}`,
      `Group ${idx + 1}`,
    );
    const newGroup: TrainingGroup = {
      id: `grp_${Date.now()}`,
      name: defaultName,
      focus: "Physical",
      player_ids: [],
    };
    saveGroups([...groups, newGroup]);
  };

  const removeGroup = (groupId: string) => {
    saveGroups(groups.filter((g) => g.id !== groupId));
  };

  const updateGroupFocus = (groupId: string, focus: string) => {
    saveGroups(groups.map((g) => (g.id === groupId ? { ...g, focus } : g)));
  };

  const updateGroupName = (groupId: string, name: string) => {
    saveGroups(groups.map((g) => (g.id === groupId ? { ...g, name } : g)));
  };

  // Set individual player training focus override (or clear it)
  const setPlayerFocus = async (playerId: string, focus: string) => {
    setIsSaving(true);
    try {
      const updated = await invoke<GameStateData>("set_player_training_focus", {
        playerId,
        focus: focus || null,
      });
      onGameUpdate?.(updated);
    } catch (err) {
      console.error("Failed to set player training focus:", err);
    } finally {
      setIsSaving(false);
    }
  };

  // Assign player to a group (or remove from all groups if groupId is "")
  const setPlayerGroup = (playerId: string, groupId: string) => {
    // Remove from any current group
    let newGroups = groups.map((g) => ({
      ...g,
      player_ids: g.player_ids.filter((pid) => pid !== playerId),
    }));
    // Add to the target group if specified
    if (groupId) {
      newGroups = newGroups.map((g) =>
        g.id === groupId
          ? { ...g, player_ids: [...g.player_ids, playerId] }
          : g,
      );
    }
    saveGroups(newGroups);
  };

  // Lookup: player ID → group
  const playerGroupMap = new Map<string, TrainingGroup>();
  for (const g of groups) {
    for (const pid of g.player_ids) {
      playerGroupMap.set(pid, g);
    }
  }

  // Sort roster: by position then name
  const posOrd: Record<string, number> = {
    Goalkeeper: 1,
    Defender: 2,
    Midfielder: 3,
    Forward: 4,
  };
  const sortedRoster = [...roster].sort((a, b) => {
    const pa = posOrd[a.natural_position || a.position] || 99;
    const pb = posOrd[b.natural_position || b.position] || 99;
    return pa - pb || a.match_name.localeCompare(b.match_name);
  });

  return (
    <Card>
      <CardHeader
        action={
          groups.length < 5 ? (
            <button
              onClick={addGroup}
              disabled={isSaving}
              className="flex items-center gap-1.5 text-xs font-heading font-bold uppercase tracking-wider text-primary-500 hover:text-primary-400 transition-colors disabled:opacity-50"
            >
              <Plus className="w-4 h-4" /> {t("training.groups.addGroup")}
            </button>
          ) : null
        }
      >
        {t("training.groups.trainingGroups")}
      </CardHeader>
      <CardBody>
        {/* Group chips with inline editing */}
        {groups.length > 0 && (
          <div className="flex flex-wrap gap-2 mb-4">
            {groups.map((group) => {
              const count = group.player_ids.length;
              return (
                <div
                  key={group.id}
                  className="flex items-center gap-2 bg-gray-50 dark:bg-navy-700/50 border border-gray-200 dark:border-navy-600 rounded-lg px-3 py-1.5"
                >
                  <div className="text-gray-400 dark:text-gray-500">
                    {TRAINING_FOCUS_ICONS[group.focus] ? (
                      <span className="[&>svg]:w-4 [&>svg]:h-4">
                        {TRAINING_FOCUS_ICONS[group.focus]}
                      </span>
                    ) : (
                      <Users className="w-4 h-4" />
                    )}
                  </div>
                  <input
                    type="text"
                    value={group.name}
                    onChange={(e) => updateGroupName(group.id, e.target.value)}
                    className="bg-transparent text-xs font-heading font-bold uppercase tracking-wider text-gray-800 dark:text-gray-200 border-none outline-none w-20"
                  />
                  <Select
                    value={group.focus}
                    onChange={(e) => updateGroupFocus(group.id, e.target.value)}
                    disabled={isSaving}
                    variant="muted"
                    selectSize="xs"
                    className="w-28"
                  >
                    {TRAINING_FOCUS_IDS.map((fId) => (
                      <option key={fId} value={fId}>
                        {t(`training.focuses.${fId}.label`)}
                      </option>
                    ))}
                  </Select>
                  <span className="text-[10px] text-gray-400 tabular-nums">
                    {count}
                  </span>
                  <button
                    onClick={() => removeGroup(group.id)}
                    disabled={isSaving}
                    className="text-red-400 hover:text-red-500 transition-colors disabled:opacity-50"
                    title={t("training.groups.removeGroup")}
                  >
                    <Trash2 className="w-3 h-3" />
                  </button>
                </div>
              );
            })}
          </div>
        )}

        {groups.length === 0 ? (
          <p className="text-sm text-gray-500 dark:text-gray-400 mb-3">
            {t("training.groups.noGroups")}
          </p>
        ) : (
          /* Player roster table with inline group assignment */
          <div className="overflow-x-auto rounded-lg border border-gray-200 dark:border-navy-600">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="bg-gray-50 dark:bg-navy-700/50">
                  <th className="py-2 px-3 text-[10px] font-heading font-bold uppercase tracking-widest text-gray-500 dark:text-gray-400">
                    {t("common.player")}
                  </th>
                  <th className="py-2 px-3 text-[10px] font-heading font-bold uppercase tracking-widest text-gray-500 dark:text-gray-400">
                    {t("common.position")}
                  </th>
                  <th className="py-2 px-3 text-[10px] font-heading font-bold uppercase tracking-widest text-gray-500 dark:text-gray-400">
                    {t("training.groups.group")}
                  </th>
                  <th className="py-2 px-3 text-[10px] font-heading font-bold uppercase tracking-widest text-gray-500 dark:text-gray-400">
                    {t("training.effectiveFocus")}
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                {sortedRoster.map((p) => {
                  const pg = playerGroupMap.get(p.id);
                  const hasIndividualFocus = !!p.training_focus;
                  const effectiveFocus =
                    p.training_focus || (pg ? pg.focus : teamFocus);
                  return (
                    <tr
                      key={p.id}
                      className="hover:bg-gray-50 dark:hover:bg-navy-700/30 transition-colors"
                    >
                      <td className="py-1.5 px-3 text-sm font-medium text-gray-800 dark:text-gray-200 truncate max-w-[160px]">
                        {p.match_name}
                      </td>
                      <td className="py-1.5 px-3 text-xs text-gray-500 dark:text-gray-400">
                        {(p.natural_position || p.position)
                          .substring(0, 3)
                          .toUpperCase()}
                      </td>
                      <td className="py-1.5 px-3">
                        <Select
                          value={pg?.id || ""}
                          onChange={(e) => setPlayerGroup(p.id, e.target.value)}
                          disabled={isSaving}
                          variant="muted"
                          selectSize="xs"
                          fullWidth
                          wrapperClassName="w-full max-w-[120px]"
                        >
                          <option value="">
                            {t("training.groups.teamDefault")}
                          </option>
                          {groups.map((g) => (
                            <option key={g.id} value={g.id}>
                              {g.name}
                            </option>
                          ))}
                        </Select>
                      </td>
                      <td className="py-1.5 px-3">
                        <Select
                          value={p.training_focus || ""}
                          onChange={(e) => setPlayerFocus(p.id, e.target.value)}
                          disabled={isSaving}
                          variant={
                            hasIndividualFocus ? "highlighted" : "placeholder"
                          }
                          selectSize="xs"
                          fullWidth
                          wrapperClassName="w-full max-w-[110px]"
                        >
                          <option value="">
                            {t(`training.focuses.${effectiveFocus}.label`)} ↩
                          </option>
                          {TRAINING_FOCUS_IDS.map((fId) => (
                            <option key={fId} value={fId}>
                              {t(`training.focuses.${fId}.label`)}
                            </option>
                          ))}
                        </Select>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        <p className="text-xs text-gray-400 dark:text-gray-500 mt-3">
          {t("training.groups.trainingGroupsDesc")}
        </p>
      </CardBody>
    </Card>
  );
}
