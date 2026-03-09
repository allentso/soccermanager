import { DragEvent, useEffect, useMemo, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { GameStateData, PlayerData } from "../store/gameStore";
import { Card, Badge, ProgressBar } from "./ui";
import {
  Star,
  ArrowRightLeft,
  Users,
  Shield,
  Crosshair,
  Zap,
  Target,
  RefreshCw,
  Flag,
  AlertTriangle,
  User,
  ShoppingCart,
  Repeat,
  GitCompareArrows,
  ChevronUp,
  ChevronDown,
} from "lucide-react";
import {
  formatVal,
  positionBadgeVariant,
  calcOvr,
  calcAge,
} from "../lib/helpers";
import { TraitList } from "./TraitBadge";
import { useTranslation } from "react-i18next";
import { countryFlag } from "../lib/countries";
import ContextMenu from "./ContextMenu";
import CompareView from "./SquadCompareView";
import {
  applyLineupDrop,
  applyLineupSwap,
  buildActivePositionMap,
  buildPitchRows,
  buildPitchSlotRows,
  buildStartingXIIds,
  CORE_POSITIONS,
  getPitchSlotWidth,
  getPreferredPositions,
  isPlayerOutOfPosition,
  normalisePosition,
  positionCode,
  type DragState,
  type PitchSlotRow,
  type SquadSection,
} from "./SquadTab.helpers";

interface SquadTabProps {
  gameState: GameStateData;
  managerId: string;
  onSelectPlayer: (id: string) => void;
  onGameUpdate?: (g: GameStateData) => void;
}

const FORMATIONS = [
  "4-4-2",
  "4-3-3",
  "3-5-2",
  "4-5-1",
  "4-2-3-1",
  "3-4-3",
  "5-3-2",
  "4-1-4-1",
];
const PLAY_STYLES = [
  { id: "Balanced", icon: <Target className="w-3.5 h-3.5" /> },
  { id: "Attacking", icon: <Zap className="w-3.5 h-3.5" /> },
  { id: "Defensive", icon: <Shield className="w-3.5 h-3.5" /> },
  { id: "Possession", icon: <RefreshCw className="w-3.5 h-3.5" /> },
  { id: "Counter", icon: <Crosshair className="w-3.5 h-3.5" /> },
  { id: "HighPress", icon: <Flag className="w-3.5 h-3.5" /> },
];

const PLAY_STYLE_DESCRIPTION_FALLBACKS: Record<string, string> = {
  Balanced:
    "Keeps your team measured in and out of possession, with a steady shape and fewer extremes.",
  Attacking:
    "Pushes more bodies forward, creates extra support around the box, and asks your team to take more initiative.",
  Defensive:
    "Makes your team protect space first, stay compact, and reduce the risk of getting exposed behind the ball.",
  Possession:
    "Encourages your team to circulate the ball patiently, control the tempo, and look for cleaner openings.",
  Counter:
    "Invites your team to break forward quickly after regaining the ball, attacking space before the opponent resets.",
  HighPress:
    "Asks your team to close down earlier, win the ball higher up the pitch, and keep opponents under pressure.",
};
type SortSection = SquadSection | "mixed";
type FilterScope = "all" | "xi" | "bench" | "outOfPosition" | "injured";

export default function SquadTab({
  gameState,
  managerId,
  onSelectPlayer,
  onGameUpdate,
}: SquadTabProps) {
  const { t } = useTranslation();
  const myTeam = gameState.teams.find((t) => t.manager_id === managerId);
  const [swapSource, setSwapSource] = useState<{
    id: string;
    from: "xi" | "bench";
  } | null>(null);
  const [activeView, setActiveView] = useState<"lineup" | "roster" | "compare">(
    "lineup",
  );
  const [compareA, setCompareA] = useState<string | null>(null);
  const [compareB, setCompareB] = useState<string | null>(null);
  const [playerSearch, setPlayerSearch] = useState("");
  const [positionFilter, setPositionFilter] = useState("All");
  const [statusFilter, setStatusFilter] = useState<FilterScope>("all");
  const [dragState, setDragState] = useState<DragState | null>(null);
  const [hoveredSlot, setHoveredSlot] = useState<number | null>(null);
  const [pendingStartingXiIds, setPendingStartingXiIds] = useState<
    string[] | null
  >(null);
  const dragStateRef = useRef<DragState | null>(null);

  type SortKey = "pos" | "name" | "age" | "condition" | "morale" | "ovr";
  const [sortKey, setSortKey] = useState<SortKey>("pos");
  const [sortDir, setSortDir] = useState<"asc" | "desc">("asc");
  const toggleSort = (key: SortKey) => {
    if (sortKey === key) setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    else {
      setSortKey(key);
      setSortDir(key === "ovr" ? "desc" : "asc");
    }
  };

  if (!myTeam)
    return (
      <p className="text-gray-500 dark:text-gray-400">
        {t("common.unemployed")}
      </p>
    );

  const posOrder: Record<string, number> = {
    Goalkeeper: 1,
    Defender: 2,
    Midfielder: 3,
    Forward: 4,
  };
  const savedStartingXiKey = (myTeam.starting_xi_ids || []).join(",");
  const roster = gameState.players
    .filter((p) => p.team_id === myTeam.id)
    .sort(
      (a, b) =>
        (posOrder[normalisePosition(a.position)] || 99) -
          (posOrder[normalisePosition(b.position)] || 99) ||
        calcOvr(b) - calcOvr(a),
    );

  const formation = myTeam.formation || "4-4-2";
  const pitchRows = useMemo(() => buildPitchRows(formation), [formation]);
  const playersById = useMemo(
    () => new Map(roster.map((player) => [player.id, player])),
    [roster],
  );
  const activePlayStyle = myTeam.play_style || "Balanced";

  // Build starting XI from persistent IDs, fallback to auto-select
  const available = roster.filter((p) => !p.injury);
  const startingXiIds = useMemo(() => {
    const baseIds = buildStartingXIIds(
      available,
      myTeam.starting_xi_ids || [],
      formation,
    );

    if (!pendingStartingXiIds || pendingStartingXiIds.length === 0) {
      return baseIds;
    }

    const validPendingIds = pendingStartingXiIds.filter((id) =>
      playersById.has(id),
    );
    const used = new Set(validPendingIds);
    const fill = available
      .filter((player) => !used.has(player.id))
      .sort((a, b) => calcOvr(b) - calcOvr(a))
      .map((player) => player.id);

    return [...validPendingIds, ...fill].slice(0, 11);
  }, [
    available.map((p) => p.id).join(","),
    formation,
    savedStartingXiKey,
    (pendingStartingXiIds || []).join(","),
    roster.map((player) => player.id).join(","),
  ]);
  const startingXI = useMemo(
    () =>
      startingXiIds
        .map((id) => playersById.get(id))
        .filter((player): player is PlayerData => player != null),
    [playersById, startingXiIds],
  );

  useEffect(() => {
    if (!pendingStartingXiIds) return;
    if (savedStartingXiKey === pendingStartingXiIds.join(",")) {
      setPendingStartingXiIds(null);
    }
  }, [pendingStartingXiIds, savedStartingXiKey]);

  const pitchSlotRows = useMemo<PitchSlotRow[]>(
    () => buildPitchSlotRows(pitchRows, startingXiIds, playersById),
    [pitchRows, playersById, startingXiIds],
  );

  const xiIds = new Set(startingXiIds);
  const bench = roster.filter((p) => !xiIds.has(p.id));

  // Assign active position to XI players based on formation slot order
  const xiActivePosition = useMemo(
    () => buildActivePositionMap(pitchSlotRows),
    [pitchSlotRows],
  );

  // Sort helper
  const sortPlayers = (
    players: PlayerData[],
    section: SortSection,
  ): PlayerData[] => {
    const posOrd: Record<string, number> = {
      Goalkeeper: 1,
      Defender: 2,
      Midfielder: 3,
      Forward: 4,
    };
    const getPos = (p: PlayerData) => {
      if (section === "xi")
        return normalisePosition(xiActivePosition.get(p.id) || p.position);
      if (section === "mixed" && xiIds.has(p.id))
        return normalisePosition(xiActivePosition.get(p.id) || p.position);
      return normalisePosition(p.position);
    };
    const cmp = (a: PlayerData, b: PlayerData): number => {
      switch (sortKey) {
        case "pos":
          return (
            (posOrd[getPos(a)] || 99) - (posOrd[getPos(b)] || 99) ||
            calcOvr(b) - calcOvr(a)
          );
        case "name":
          return a.full_name.localeCompare(b.full_name);
        case "age":
          return calcAge(a.date_of_birth) - calcAge(b.date_of_birth);
        case "condition":
          return a.condition - b.condition;
        case "morale":
          return a.morale - b.morale;
        case "ovr":
          return calcOvr(a) - calcOvr(b);
        default:
          return 0;
      }
    };
    const sorted = [...players].sort(cmp);
    return sortDir === "desc" ? sorted.reverse() : sorted;
  };

  const persistStartingXI = async (playerIds: string[]) => {
    setPendingStartingXiIds(playerIds);
    try {
      const updated = await invoke<GameStateData>("set_starting_xi", {
        playerIds,
      });
      onGameUpdate?.(updated);
    } catch (err) {
      setPendingStartingXiIds(null);
      console.error("Failed to set starting XI:", err);
    }
  };

  const handleFormationChange = async (f: string) => {
    try {
      const updated = await invoke<GameStateData>("set_formation", {
        formation: f,
      });
      onGameUpdate?.(updated);
    } catch (err) {
      console.error("Failed to set formation:", err);
    }
  };

  const handlePlayStyleChange = async (ps: string) => {
    try {
      const updated = await invoke<GameStateData>("set_play_style", {
        playStyle: ps,
      });
      onGameUpdate?.(updated);
    } catch (err) {
      console.error("Failed to set play style:", err);
    }
  };

  const resetDragState = () => {
    dragStateRef.current = null;
    setDragState(null);
    setHoveredSlot(null);
  };

  const handleDragStart = (
    event: DragEvent<HTMLElement>,
    playerId: string,
    from: SquadSection,
    slotIndex: number | null = null,
  ) => {
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", playerId);
    const nextDragState = { playerId, from, slotIndex };
    dragStateRef.current = nextDragState;
    setDragState(nextDragState);
  };

  const handleSlotDrop = async (
    event: DragEvent<HTMLElement>,
    slotIndex: number,
  ) => {
    event.preventDefault();
    const draggedPlayerId = event.dataTransfer.getData("text/plain");
    const currentDragState = dragStateRef.current ?? dragState;
    const resolvedDragState =
      currentDragState ??
      (draggedPlayerId
        ? {
            playerId: draggedPlayerId,
            from: xiIds.has(draggedPlayerId) ? "xi" : "bench",
            slotIndex: xiIds.has(draggedPlayerId)
              ? startingXiIds.indexOf(draggedPlayerId)
              : null,
          }
        : null);

    if (!resolvedDragState) return;

    const nextXiIds = applyLineupDrop(
      startingXiIds,
      resolvedDragState,
      slotIndex,
    );
    if (nextXiIds.join(",") === startingXiIds.join(",")) {
      resetDragState();
      return;
    }

    await persistStartingXI(nextXiIds);
    resetDragState();
  };

  const handleSwapClick = async (playerId: string, from: "xi" | "bench") => {
    if (swapSource) {
      if (swapSource.id === playerId) {
        setSwapSource(null);
        return;
      }
      const newXiIds = applyLineupSwap(
        startingXiIds,
        swapSource,
        playerId,
        from,
      );
      if (!newXiIds) {
        setSwapSource(null);
        return;
      }
      await persistStartingXI(newXiIds);
      setSwapSource(null);
    } else {
      setSwapSource({ id: playerId, from });
    }
  };

  // A player is "out of position" if their natural position differs from their tactical role
  // and their natural position is not one of their alternate positions for that role
  const isOutOfPosition = (
    player: PlayerData,
    sec: "xi" | "bench",
  ): boolean => {
    if (sec !== "xi") return false;
    const currentPos = xiActivePosition.get(player.id) || player.position;
    return isPlayerOutOfPosition(player, currentPos);
  };

  const matchesFilters = (
    player: PlayerData,
    section: SquadSection,
  ): boolean => {
    const currentPos =
      section === "xi"
        ? normalisePosition(xiActivePosition.get(player.id) || player.position)
        : normalisePosition(player.position);
    const preferredPositions = getPreferredPositions(player);
    const search = playerSearch.trim().toLowerCase();

    if (search) {
      const searchable = [
        player.full_name,
        player.match_name,
        currentPos,
        ...preferredPositions,
        ...preferredPositions.map(positionCode),
      ]
        .join(" ")
        .toLowerCase();
      if (!searchable.includes(search)) return false;
    }

    if (
      positionFilter !== "All" &&
      currentPos !== positionFilter &&
      !preferredPositions.includes(positionFilter)
    )
      return false;

    switch (statusFilter) {
      case "xi":
        return section === "xi";
      case "bench":
        return section === "bench";
      case "outOfPosition":
        return section === "xi" && isOutOfPosition(player, section);
      case "injured":
        return Boolean(player.injury);
      default:
        return true;
    }
  };

  const filteredStartingXI = sortPlayers(
    startingXI.filter((player) => matchesFilters(player, "xi")),
    "xi",
  );
  const filteredBench = sortPlayers(
    bench.filter((player) => matchesFilters(player, "bench")),
    "bench",
  );
  const filteredRoster = sortPlayers(
    roster.filter((player) =>
      matchesFilters(player, xiIds.has(player.id) ? "xi" : "bench"),
    ),
    "mixed",
  );

  const renderPreferredPositionMeta = (player: PlayerData) => (
    <div className="text-xs text-gray-400 dark:text-gray-500 flex items-center gap-1.5 flex-wrap">
      <span className="text-sm leading-none">
        {countryFlag(player.nationality)}
      </span>
      {getPreferredPositions(player).map((position, index) => (
        <Badge
          key={`${player.id}-${position}`}
          variant={index === 0 ? positionBadgeVariant(position) : "neutral"}
          size="sm"
        >
          {positionCode(position)}
        </Badge>
      ))}
    </div>
  );

  const renderPlayerRow = (player: PlayerData, section: "xi" | "bench") => {
    const ovr = calcOvr(player);
    const age = calcAge(player.date_of_birth);
    const isSwapSource = swapSource?.id === player.id;
    const isSwapTarget = swapSource && swapSource.id !== player.id;
    const wrongPos = section === "xi" && isOutOfPosition(player, section);
    const activePos =
      section === "xi"
        ? xiActivePosition.get(player.id) || player.position
        : player.position;

    const contextItems = [
      {
        label: t("squad.viewProfile", "View profile"),
        icon: <User className="w-4 h-4" />,
        onClick: () => onSelectPlayer(player.id),
      },
      {
        label: t("squad.swapPlayer", "Swap player"),
        icon: <ArrowRightLeft className="w-4 h-4" />,
        onClick: () => handleSwapClick(player.id, section),
        disabled: !!(player.injury && section === "bench"),
      },
      { label: "", icon: undefined, onClick: () => {}, divider: true },
      {
        label: player.transfer_listed
          ? t("squad.removeFromTransferList", "Remove from transfer list")
          : t("squad.addToTransferList", "Add to transfer list"),
        icon: <ShoppingCart className="w-4 h-4" />,
        onClick: async () => {
          try {
            const updated = await invoke<GameStateData>(
              "toggle_transfer_list",
              { playerId: player.id },
            );
            onGameUpdate?.(updated);
          } catch {
            /* command may not exist yet */
          }
        },
      },
      {
        label: player.loan_listed
          ? t("squad.removeFromLoanList", "Remove from loan list")
          : t("squad.addToLoanList", "Add to loan list"),
        icon: <Repeat className="w-4 h-4" />,
        onClick: async () => {
          try {
            const updated = await invoke<GameStateData>("toggle_loan_list", {
              playerId: player.id,
            });
            onGameUpdate?.(updated);
          } catch {
            /* command may not exist yet */
          }
        },
      },
    ];

    return (
      <ContextMenu items={contextItems} key={player.id}>
        <tr
          className={`transition-colors group ${isSwapSource ? "bg-accent-500/10 dark:bg-accent-500/10" : isSwapTarget ? "hover:bg-primary-500/10 dark:hover:bg-primary-500/10 cursor-pointer" : wrongPos ? "bg-amber-500/5 dark:bg-amber-500/5" : "hover:bg-gray-50 dark:hover:bg-navy-700/50"}`}
        >
          <td className="py-2.5 px-4">
            <div className="flex items-center gap-1.5">
              <Badge
                variant={positionBadgeVariant(normalisePosition(activePos))}
                size="sm"
              >
                {positionCode(normalisePosition(activePos))}
              </Badge>
              {wrongPos && (
                <span
                  title={t(
                    "squad.outOfPositionTooltip",
                    "Playing outside the player's preferred role",
                  )}
                  className="text-amber-500"
                >
                  <AlertTriangle className="w-3.5 h-3.5" />
                </span>
              )}
            </div>
          </td>
          <td className="py-2.5 px-4">
            <button
              onClick={() => onSelectPlayer(player.id)}
              className="text-left"
            >
              <div className="font-semibold text-sm text-gray-900 dark:text-gray-100 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors">
                {player.full_name}
              </div>
              {renderPreferredPositionMeta(player)}
            </button>
          </td>
          <td className="py-2.5 px-4 text-sm text-gray-600 dark:text-gray-400 tabular-nums">
            {age}
          </td>
          <td className="py-2.5 px-4 w-28">
            <ProgressBar
              value={player.condition}
              variant="auto"
              size="sm"
              showLabel
            />
          </td>
          <td className="py-2.5 px-4 text-sm text-gray-500 dark:text-gray-400 tabular-nums">
            {player.morale}
          </td>
          <td className="py-2.5 px-4">
            {player.traits && player.traits.length > 0 ? (
              <TraitList traits={player.traits} size="xs" max={2} />
            ) : (
              <span className="text-xs text-gray-500">—</span>
            )}
          </td>
          <td className="py-2.5 px-4">
            <span
              className={`font-heading font-bold text-base tabular-nums ${
                ovr >= 75
                  ? "text-success-500 dark:text-success-400"
                  : ovr >= 55
                    ? "text-accent-600 dark:text-accent-400"
                    : "text-gray-500 dark:text-gray-400"
              }`}
            >
              {ovr}
            </span>
          </td>
          <td className="py-2.5 px-4">
            <div className="flex items-center gap-1.5">
              {player.injury && (
                <Badge variant="danger" size="sm">
                  {t("common.injured")}
                </Badge>
              )}
              {(!player.injury || section === "xi") && (
                <button
                  onClick={() => handleSwapClick(player.id, section)}
                  className={`p-1.5 rounded-lg transition-colors ${isSwapSource ? "bg-accent-500 text-white" : "text-gray-400 hover:text-primary-500 hover:bg-gray-100 dark:hover:bg-navy-600"}`}
                  title={t("squad.swapPlayer", "Swap player")}
                >
                  <ArrowRightLeft className="w-3.5 h-3.5" />
                </button>
              )}
            </div>
          </td>
        </tr>
      </ContextMenu>
    );
  };

  const SortHeader = ({
    col,
    label,
    className,
  }: {
    col: SortKey;
    label: string;
    className?: string;
  }) => (
    <th
      className={`py-2.5 px-4 font-heading font-bold uppercase tracking-wider cursor-pointer select-none hover:text-primary-400 transition-colors ${sortKey === col ? "text-primary-500 dark:text-primary-400" : "text-gray-500 dark:text-gray-400"} ${className || ""}`}
      onClick={() => toggleSort(col)}
    >
      <div className="flex items-center gap-1">
        {label}
        {sortKey === col ? (
          sortDir === "asc" ? (
            <ChevronUp className="w-3 h-3" />
          ) : (
            <ChevronDown className="w-3 h-3" />
          )
        ) : null}
      </div>
    </th>
  );

  const tableHead = (
    <thead>
      <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
        <SortHeader col="pos" label={t("squad.pos")} />
        <SortHeader col="name" label={t("common.name")} />
        <SortHeader col="age" label={t("common.age")} />
        <SortHeader col="condition" label={t("common.condition")} />
        <SortHeader col="morale" label={t("common.morale")} />
        <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
          {t("squad.traits")}
        </th>
        <SortHeader col="ovr" label={t("common.ovr")} />
        <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 w-12"></th>
      </tr>
    </thead>
  );

  const hasActiveFilters =
    playerSearch.trim().length > 0 ||
    positionFilter !== "All" ||
    statusFilter !== "all";
  const outOfPositionCount = startingXI.filter((player) =>
    isOutOfPosition(player, "xi"),
  ).length;
  const injuredCount = roster.filter((player) => player.injury).length;

  const filterControls = (
    <Card>
      <div className="p-4 grid grid-cols-1 lg:grid-cols-[minmax(0,1.3fr)_220px_220px_auto] gap-3 items-end">
        <div>
          <label className="text-xs font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-2 block">
            {t("common.search", "Search")}
          </label>
          <input
            type="text"
            value={playerSearch}
            onChange={(event) => setPlayerSearch(event.target.value)}
            placeholder={t(
              "squad.filterPlayers",
              "Filter by player name or position",
            )}
            className="w-full rounded-lg border border-gray-200 dark:border-navy-600 bg-white dark:bg-navy-800 px-3 py-2 text-sm text-gray-700 dark:text-gray-200 placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500/30"
          />
        </div>
        <div>
          <label className="text-xs font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-2 block">
            {t("squad.pos")}
          </label>
          <select
            value={positionFilter}
            onChange={(event) => setPositionFilter(event.target.value)}
            className="w-full rounded-lg border border-gray-200 dark:border-navy-600 bg-white dark:bg-navy-800 px-3 py-2 text-sm text-gray-700 dark:text-gray-200 focus:outline-none focus:ring-2 focus:ring-primary-500/30"
          >
            <option value="All">{t("common.all", "All")}</option>
            {CORE_POSITIONS.map((position) => (
              <option key={position} value={position}>
                {t(`common.posAbbr.${position}`, positionCode(position))}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="text-xs font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-2 block">
            {t("common.status", "Status")}
          </label>
          <select
            value={statusFilter}
            onChange={(event) =>
              setStatusFilter(event.target.value as FilterScope)
            }
            className="w-full rounded-lg border border-gray-200 dark:border-navy-600 bg-white dark:bg-navy-800 px-3 py-2 text-sm text-gray-700 dark:text-gray-200 focus:outline-none focus:ring-2 focus:ring-primary-500/30"
          >
            <option value="all">{t("common.allPlayers", "All players")}</option>
            <option value="xi">
              {t("preMatch.startingXI", "Starting XI")}
            </option>
            <option value="bench">
              {t("preMatch.substitutes", "Substitutes")}
            </option>
            <option value="outOfPosition">
              {t("squad.outOfPosition", "Out of position")}
            </option>
            <option value="injured">{t("common.injured", "Injured")}</option>
          </select>
        </div>
        <button
          type="button"
          onClick={() => {
            setPlayerSearch("");
            setPositionFilter("All");
            setStatusFilter("all");
          }}
          disabled={!hasActiveFilters}
          className={`px-3 py-2 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
            hasActiveFilters
              ? "bg-gray-100 dark:bg-navy-700 text-gray-600 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-navy-600"
              : "bg-gray-100 dark:bg-navy-700 text-gray-400 cursor-not-allowed"
          }`}
        >
          {t("common.clear", "Clear")}
        </button>
      </div>
      <div className="px-4 pb-4 flex flex-wrap gap-2">
        <Badge
          variant={outOfPositionCount > 0 ? "danger" : "success"}
          size="sm"
        >
          {outOfPositionCount} {t("squad.outOfPosition", "Out of position")}
        </Badge>
        <Badge variant={injuredCount > 0 ? "danger" : "neutral"} size="sm">
          {injuredCount} {t("common.injured", "Injured")}
        </Badge>
        <Badge variant="primary" size="sm">
          {filteredRoster.length} {t("squad.playersLabel", "players")}
        </Badge>
      </div>
    </Card>
  );

  return (
    <div className="max-w-6xl mx-auto flex flex-col gap-4">
      {/* View Tabs */}
      <div className="flex gap-1 bg-gray-100 dark:bg-navy-800 rounded-lg p-1 w-fit">
        <button
          onClick={() => setActiveView("lineup")}
          className={`flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
            activeView === "lineup"
              ? "bg-white dark:bg-navy-600 text-primary-600 dark:text-primary-400 shadow-sm"
              : "text-gray-500 dark:text-gray-400"
          }`}
        >
          <Star className="w-4 h-4" /> {t("preMatch.startingXI", "Starting XI")}
        </button>
        <button
          onClick={() => setActiveView("roster")}
          className={`flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
            activeView === "roster"
              ? "bg-white dark:bg-navy-600 text-primary-600 dark:text-primary-400 shadow-sm"
              : "text-gray-500 dark:text-gray-400"
          }`}
        >
          <Users className="w-4 h-4" /> {t("squad.fullRoster", "Full Roster")}
        </button>
        <button
          onClick={() => setActiveView("compare")}
          className={`flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
            activeView === "compare"
              ? "bg-white dark:bg-navy-600 text-primary-600 dark:text-primary-400 shadow-sm"
              : "text-gray-500 dark:text-gray-400"
          }`}
        >
          <GitCompareArrows className="w-4 h-4" />{" "}
          {t("squad.compare", "Compare")}
        </button>
      </div>

      {activeView === "compare" ? (
        <CompareView
          roster={roster}
          compareA={compareA}
          compareB={compareB}
          setCompareA={setCompareA}
          setCompareB={setCompareB}
        />
      ) : activeView === "lineup" ? (
        <>
          {/* Header with Formation & Play Style */}
          <div className="grid grid-cols-1 xl:grid-cols-[minmax(0,1.65fr)_minmax(320px,0.95fr)] gap-4 items-start">
            {/* Starting XI */}
            <Card className="overflow-hidden">
              <div className="p-4 border-b border-gray-100 dark:border-navy-600 flex flex-wrap justify-between items-center gap-3 bg-linear-to-r from-navy-700 to-navy-800 rounded-t-xl">
                <div>
                  <h3 className="text-sm font-heading font-bold text-white uppercase tracking-wide flex items-center gap-2">
                    <Star className="text-accent-400 w-4 h-4 fill-current" />
                    {t("preMatch.startingXI", "Starting XI")} — {formation}
                  </h3>
                  <p className="text-xs text-gray-400 mt-0.5">
                    {t(
                      "squad.dragHint",
                      "Drag bench players onto the pitch or swap starters between slots.",
                    )}
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <Badge
                    variant={outOfPositionCount > 0 ? "danger" : "success"}
                    size="sm"
                  >
                    {outOfPositionCount}{" "}
                    {t("squad.outOfPosition", "Out of position")}
                  </Badge>
                  {swapSource ? (
                    <button
                      onClick={() => setSwapSource(null)}
                      className="text-xs text-accent-400 font-heading font-bold uppercase tracking-wider hover:text-accent-300"
                    >
                      {t("common.cancel")}
                    </button>
                  ) : null}
                </div>
              </div>
              <div className="p-4 sm:p-6">
                <div className="bg-linear-to-b from-primary-700/20 to-primary-900/30 dark:from-primary-900/40 dark:to-navy-900/60 rounded-xl p-4 sm:p-5 min-h-[460px] sm:min-h-[520px] relative border border-primary-500/20 overflow-visible">
                  <div className="absolute inset-x-6 top-1/2 border-t border-white/10" />
                  <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-20 h-20 border border-white/10 rounded-full" />
                  <div className="absolute inset-x-[18%] bottom-4 h-[18%] border border-white/10 rounded-t-4xl border-b-0" />
                  <div className="absolute inset-x-[32%] bottom-4 h-[8%] border border-white/10 rounded-t-2xl border-b-0" />
                  {pitchSlotRows.map((row) => (
                    <div
                      key={row.label}
                      className="absolute left-1/2 grid justify-center gap-2 sm:gap-2.5"
                      style={{
                        top: row.y,
                        transform: "translate(-50%, -50%)",
                        gridTemplateColumns: `repeat(${row.slots.length}, minmax(0, ${getPitchSlotWidth(row.slots.length)}px))`,
                      }}
                    >
                      {row.slots.map((slot) => {
                        const player = slot.player;
                        const wrongPos = player
                          ? isPlayerOutOfPosition(player, slot.position)
                          : false;
                        const isHovered = hoveredSlot === slot.index;

                        return (
                          <div
                            key={`${row.label}-${slot.index}`}
                            data-testid={`pitch-slot-${slot.index}`}
                            className="w-full flex justify-center"
                            onDragOver={(event) => {
                              event.preventDefault();
                              event.dataTransfer.dropEffect = "move";
                              setHoveredSlot(slot.index);
                            }}
                            onDragLeave={() =>
                              setHoveredSlot((current) =>
                                current === slot.index ? null : current,
                              )
                            }
                            onDrop={(event) => {
                              void handleSlotDrop(event, slot.index);
                            }}
                          >
                            {player ? (
                              <button
                                type="button"
                                onClick={() => onSelectPlayer(player.id)}
                                draggable
                                data-testid={`pitch-player-${player.id}`}
                                onDragStart={(event) =>
                                  handleDragStart(
                                    event,
                                    player.id,
                                    "xi",
                                    slot.index,
                                  )
                                }
                                onDragEnd={resetDragState}
                                className={`w-full min-w-0 rounded-xl px-1.5 sm:px-2 py-2 border transition-all shadow-sm ${
                                  dragState?.playerId === player.id
                                    ? "opacity-70 ring-2 ring-white/20"
                                    : "hover:-translate-y-0.5 hover:shadow-md"
                                } ${
                                  isHovered
                                    ? "border-primary-300 bg-primary-500/10"
                                    : wrongPos
                                      ? "border-amber-300/60 bg-amber-500/10"
                                      : "border-white/10 bg-black/15"
                                } cursor-grab active:cursor-grabbing`}
                              >
                                <div
                                  className={`mx-auto mb-1.5 w-8 h-8 sm:w-9 sm:h-9 rounded-full flex items-center justify-center font-heading font-bold text-[11px] sm:text-xs border-2 ${
                                    wrongPos
                                      ? "bg-amber-500/85 border-amber-200 text-white"
                                      : player.condition >= 70
                                        ? "bg-primary-500/80 border-primary-200 text-white"
                                        : "bg-red-500/80 border-red-200 text-white"
                                  }`}
                                >
                                  {calcOvr(player)}
                                </div>
                                <div className="text-[9px] font-heading font-bold uppercase tracking-wider text-white/70 leading-none">
                                  {positionCode(slot.position)}
                                </div>
                                <div className="text-[10px] sm:text-[11px] font-semibold text-white truncate leading-tight mt-1">
                                  {player.match_name}
                                </div>
                                <div className="text-[9px] text-white/60 truncate leading-none mt-0.5">
                                  {player.condition}%
                                </div>
                              </button>
                            ) : (
                              <div
                                className={`w-full min-w-0 rounded-xl border border-dashed px-1.5 sm:px-2 py-3.5 sm:py-4 text-center ${
                                  isHovered
                                    ? "border-primary-300 bg-primary-500/10"
                                    : "border-white/20 bg-black/10"
                                }`}
                              >
                                <div className="text-[9px] font-heading font-bold uppercase tracking-wider text-white/70 leading-none">
                                  {positionCode(slot.position)}
                                </div>
                                <div className="text-[9px] text-white/50 mt-1 leading-tight">
                                  {t(
                                    "squad.dropPlayerHere",
                                    "Drop player here",
                                  )}
                                </div>
                              </div>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  ))}
                </div>
              </div>
              <div className="border-t border-gray-100 dark:border-navy-600 p-4">
                <div className="flex flex-wrap items-center justify-between gap-2 mb-3">
                  <div>
                    <h4 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 dark:text-gray-400">
                      {t("preMatch.substitutes", "Substitutes")}
                    </h4>
                    <p className="text-xs text-gray-400 dark:text-gray-500">
                      {t(
                        "squad.benchDragHint",
                        "Use the bench list to drag players directly onto the pitch.",
                      )}
                    </p>
                  </div>
                  <Badge variant="primary" size="sm">
                    {filteredBench.length} / {bench.length}{" "}
                    {t("squad.playersLabel", "players")}
                  </Badge>
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-2.5">
                  {filteredBench.map((player) => (
                    <button
                      key={player.id}
                      type="button"
                      data-testid={`bench-player-${player.id}`}
                      onClick={() => onSelectPlayer(player.id)}
                      draggable={!player.injury}
                      onDragStart={(event) => {
                        if (!player.injury)
                          handleDragStart(event, player.id, "bench");
                      }}
                      onDragEnd={resetDragState}
                      className={`rounded-xl border px-3 py-3 text-left transition-all ${
                        player.injury
                          ? "cursor-not-allowed opacity-60 border-gray-200 dark:border-navy-600 bg-gray-50 dark:bg-navy-800/60"
                          : dragState?.playerId === player.id
                            ? "border-accent-300 bg-accent-500/10 shadow-sm"
                            : "border-gray-200 dark:border-navy-600 hover:border-primary-300 hover:bg-primary-500/5 hover:shadow-sm"
                      }`}
                    >
                      <div className="flex items-start gap-3">
                        <span
                          className={`w-9 h-9 rounded-full shrink-0 flex items-center justify-center font-heading font-bold text-xs ${
                            calcOvr(player) >= 75
                              ? "bg-primary-500/20 text-primary-500"
                              : calcOvr(player) >= 55
                                ? "bg-accent-500/20 text-accent-500"
                                : "bg-gray-200 dark:bg-navy-600 text-gray-500"
                          }`}
                        >
                          {calcOvr(player)}
                        </span>
                        <div className="min-w-0 flex-1">
                          <div className="flex items-start justify-between gap-3">
                            <div className="min-w-0">
                              <div className="text-sm font-semibold text-gray-800 dark:text-gray-100 truncate">
                                {player.match_name}
                              </div>
                              <div className="text-[11px] text-gray-500 dark:text-gray-400 flex items-center gap-1.5 flex-wrap mt-1">
                                <Badge
                                  variant={positionBadgeVariant(
                                    normalisePosition(player.position),
                                  )}
                                  size="sm"
                                >
                                  {positionCode(player.position)}
                                </Badge>
                                {getPreferredPositions(player)
                                  .slice(0, 2)
                                  .map((position) => (
                                    <Badge
                                      key={`${player.id}-${position}`}
                                      variant="neutral"
                                      size="sm"
                                    >
                                      {positionCode(position)}
                                    </Badge>
                                  ))}
                              </div>
                            </div>
                            <span className="text-[11px] text-gray-400 dark:text-gray-500 shrink-0">
                              {player.condition}%
                            </span>
                          </div>
                          <div className="flex items-center gap-1.5 flex-wrap mt-2">
                            {!player.injury ? (
                              <Badge variant="primary" size="sm">
                                {t("squad.dragToPitch", "Drag to pitch")}
                              </Badge>
                            ) : null}
                            {player.injury ? (
                              <Badge variant="danger" size="sm">
                                {t("common.injured")}
                              </Badge>
                            ) : null}
                          </div>
                        </div>
                      </div>
                    </button>
                  ))}
                </div>
                {filteredBench.length === 0 ? (
                  <div className="text-sm text-gray-500 dark:text-gray-400">
                    {t(
                      "squad.noBenchMatches",
                      "No bench players match the current filters.",
                    )}
                  </div>
                ) : null}
              </div>
            </Card>

            <div className="flex flex-col gap-4">
              {/* Formation Card */}
              <Card>
                <div className="p-4">
                  <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 dark:text-gray-400 mb-3">
                    {t("tactics.formation")}
                  </h3>
                  <div className="grid grid-cols-2 sm:grid-cols-4 xl:grid-cols-2 gap-2">
                    {FORMATIONS.map((f) => (
                      <button
                        key={f}
                        onClick={() => handleFormationChange(f)}
                        className={`px-3 py-2 rounded-lg text-xs font-heading font-bold transition-all ${
                          formation === f
                            ? "bg-primary-500 text-white shadow-sm"
                            : "bg-gray-100 dark:bg-navy-700 text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-navy-600"
                        }`}
                      >
                        {f}
                      </button>
                    ))}
                  </div>
                </div>
              </Card>

              {/* Play Style Card */}
              <Card>
                <div className="p-4">
                  <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 dark:text-gray-400 mb-3">
                    {t("tactics.playStyle")}
                  </h3>
                  <div className="flex flex-wrap gap-1.5">
                    {PLAY_STYLES.map((s) => (
                      <button
                        key={s.id}
                        onClick={() => handlePlayStyleChange(s.id)}
                        className={`flex items-center gap-1.5 px-3 py-2 rounded-lg text-xs font-heading font-bold transition-all ${
                          activePlayStyle === s.id
                            ? "bg-primary-500 text-white shadow-sm"
                            : "bg-gray-100 dark:bg-navy-700 text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-navy-600"
                        }`}
                      >
                        {s.icon}
                        {t(`common.playStyles.${s.id}`)}
                      </button>
                    ))}
                  </div>
                  <div className="mt-3 rounded-xl border border-gray-200 dark:border-navy-600 bg-gray-50 dark:bg-navy-800/70 px-3 py-3">
                    <div className="text-[11px] font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-1">
                      {t("squad.playStyleImpactTitle", "What this changes")}
                    </div>
                    <p className="text-sm text-gray-600 dark:text-gray-300 leading-relaxed">
                      {t(
                        `squad.playStyleDescriptions.${activePlayStyle}`,
                        PLAY_STYLE_DESCRIPTION_FALLBACKS[activePlayStyle],
                      )}
                    </p>
                  </div>
                </div>
              </Card>
            </div>
          </div>

          {filterControls}

          <Card>
            <div className="p-4 border-b border-gray-100 dark:border-navy-600 bg-linear-to-r from-navy-700 to-navy-800 rounded-t-xl">
              <h3 className="text-sm font-heading font-bold text-white uppercase tracking-wide flex items-center gap-2">
                <Star className="text-accent-400 w-4 h-4 fill-current" />
                {t("preMatch.startingXI", "Starting XI")}
              </h3>
              <p className="text-xs text-gray-400 mt-0.5">
                {filteredStartingXI.length} / {startingXI.length}{" "}
                {t("squad.playersLabel", "players")}
              </p>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                {tableHead}
                <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                  {filteredStartingXI.map((p) => renderPlayerRow(p, "xi"))}
                </tbody>
              </table>
              {filteredStartingXI.length === 0 ? (
                <div className="p-6 text-center text-gray-500 dark:text-gray-400 text-sm">
                  {t(
                    "squad.noLineupMatches",
                    "No starters match the current filters.",
                  )}
                </div>
              ) : null}
            </div>
          </Card>

          {/* Bench */}
          <Card>
            <div className="p-4 border-b border-gray-100 dark:border-navy-600">
              <h3 className="text-sm font-heading font-bold text-gray-800 dark:text-gray-200 uppercase tracking-wide flex items-center gap-2">
                {t("preMatch.substitutes", "Substitutes")}
              </h3>
              <p className="text-xs text-gray-400 mt-0.5">
                {filteredBench.length} / {bench.length}{" "}
                {t("squad.playersLabel", "players")}
              </p>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                {tableHead}
                <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                  {filteredBench.map((p) => renderPlayerRow(p, "bench"))}
                </tbody>
              </table>
              {filteredBench.length === 0 ? (
                <div className="p-6 text-center text-gray-500 dark:text-gray-400 text-sm">
                  {t(
                    "squad.noBenchMatches",
                    "No bench players match the current filters.",
                  )}
                </div>
              ) : null}
            </div>
          </Card>
        </>
      ) : (
        <>
          {filterControls}

          {/* Full Roster view */}
          <Card>
            <div className="p-4 border-b border-gray-100 dark:border-navy-600 bg-linear-to-r from-navy-700 to-navy-800 rounded-t-xl">
              <h3 className="text-sm font-heading font-bold text-white uppercase tracking-wide flex items-center gap-2">
                <Users className="w-4 h-4 text-accent-400" />
                {t("squad.title", { team: myTeam.name })}
              </h3>
              <p className="text-xs text-gray-400 mt-0.5">
                {filteredRoster.length} / {roster.length}{" "}
                {t("squad.playersLabel", "players")}
              </p>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
                    <SortHeader col="pos" label={t("squad.pos")} />
                    <SortHeader col="name" label={t("common.name")} />
                    <SortHeader col="age" label={t("common.age")} />
                    <SortHeader col="condition" label={t("common.condition")} />
                    <SortHeader col="morale" label={t("common.morale")} />
                    <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                      {t("squad.traits")}
                    </th>
                    <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                      {t("common.value")}
                    </th>
                    <SortHeader col="ovr" label={t("common.ovr")} />
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                  {filteredRoster.map((player) => {
                    const ovr = calcOvr(player);
                    const age = calcAge(player.date_of_birth);
                    const inXI = xiIds.has(player.id);
                    const currentPos = inXI
                      ? xiActivePosition.get(player.id) || player.position
                      : player.position;
                    const wrongPos = inXI && isOutOfPosition(player, "xi");

                    return (
                      <tr
                        key={player.id}
                        onClick={() => onSelectPlayer(player.id)}
                        className="hover:bg-gray-50 dark:hover:bg-navy-700/50 transition-colors group cursor-pointer"
                      >
                        <td className="py-2.5 px-4">
                          <div className="flex items-center gap-1.5">
                            {inXI ? (
                              <span
                                className="w-1.5 h-1.5 rounded-full bg-primary-500"
                                title={t("preMatch.startingXI", "Starting XI")}
                              />
                            ) : null}
                            <Badge
                              variant={positionBadgeVariant(currentPos)}
                              size="sm"
                            >
                              {positionCode(currentPos)}
                            </Badge>
                            {wrongPos ? (
                              <span
                                className="text-amber-500"
                                title={t(
                                  "squad.outOfPositionTooltip",
                                  "Playing outside the player's preferred role",
                                )}
                              >
                                <AlertTriangle className="w-3.5 h-3.5" />
                              </span>
                            ) : null}
                          </div>
                        </td>
                        <td className="py-2.5 px-4">
                          <div className="font-semibold text-sm text-gray-900 dark:text-gray-100 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors">
                            {player.full_name}
                          </div>
                          {renderPreferredPositionMeta(player)}
                        </td>
                        <td className="py-2.5 px-4 text-sm text-gray-600 dark:text-gray-400 tabular-nums">
                          {age}
                        </td>
                        <td className="py-2.5 px-4 w-28">
                          <ProgressBar
                            value={player.condition}
                            variant="auto"
                            size="sm"
                            showLabel
                          />
                        </td>
                        <td className="py-2.5 px-4 text-sm text-gray-500 dark:text-gray-400 tabular-nums">
                          {player.morale}
                        </td>
                        <td className="py-2.5 px-4">
                          {player.traits && player.traits.length > 0 ? (
                            <TraitList
                              traits={player.traits}
                              size="xs"
                              max={2}
                            />
                          ) : (
                            <span className="text-xs text-gray-500">—</span>
                          )}
                        </td>
                        <td className="py-2.5 px-4 text-xs text-gray-600 dark:text-gray-400 font-medium">
                          {formatVal(player.market_value)}
                        </td>
                        <td className="py-2.5 px-4">
                          <span
                            className={`font-heading font-bold text-base tabular-nums ${
                              ovr >= 75
                                ? "text-success-500 dark:text-success-400"
                                : ovr >= 55
                                  ? "text-accent-600 dark:text-accent-400"
                                  : "text-gray-500 dark:text-gray-400"
                            }`}
                          >
                            {ovr}
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
              {filteredRoster.length === 0 ? (
                <div className="p-8 text-center text-gray-500 dark:text-gray-400 font-heading uppercase tracking-wider text-sm">
                  {t("squad.noPlayers")}
                </div>
              ) : null}
            </div>
          </Card>
        </>
      )}
    </div>
  );
}
