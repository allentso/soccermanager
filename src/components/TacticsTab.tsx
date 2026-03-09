import { DragEvent, useEffect, useMemo, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { GameStateData, PlayerData } from "../store/gameStore";
import { Badge, Card, ProgressBar, Select } from "./ui";
import {
  AlertTriangle,
  ChevronDown,
  ChevronUp,
  Crosshair,
  Flag,
  RefreshCw,
  Shield,
  Star,
  Target,
  Zap,
} from "lucide-react";
import { calcAge, calcOvr, positionBadgeVariant } from "../lib/helpers";
import { TraitList } from "./TraitBadge";
import { useTranslation } from "react-i18next";
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
import TacticsPlayerFocusPanel from "./TacticsPlayerFocusPanel";

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

interface TacticsTabProps {
  gameState: GameStateData;
  onSelectPlayer: (id: string) => void;
  onGameUpdate: (g: GameStateData) => void;
}

type SortKey = "pos" | "name" | "age" | "condition" | "morale" | "ovr";

export default function TacticsTab({
  gameState,
  onSelectPlayer,
  onGameUpdate,
}: TacticsTabProps) {
  const { t } = useTranslation();
  const myTeam = gameState.teams.find(
    (team) => team.id === gameState.manager.team_id,
  );
  const [playerSearch, setPlayerSearch] = useState("");
  const [positionFilter, setPositionFilter] = useState("All");
  const [sortKey, setSortKey] = useState<SortKey>("pos");
  const [sortDir, setSortDir] = useState<"asc" | "desc">("asc");
  const [dragState, setDragState] = useState<DragState | null>(null);
  const [hoveredSlot, setHoveredSlot] = useState<number | null>(null);
  const [pendingStartingXiIds, setPendingStartingXiIds] = useState<
    string[] | null
  >(null);
  const [selectedPitchPlayerId, setSelectedPitchPlayerId] = useState<
    string | null
  >(null);
  const [hoveredPitchPlayerId, setHoveredPitchPlayerId] = useState<
    string | null
  >(null);
  const dragStateRef = useRef<DragState | null>(null);

  if (!myTeam) {
    return (
      <p className="text-gray-500 dark:text-gray-400">{t("common.noTeam")}</p>
    );
  }

  const posOrder: Record<string, number> = {
    Goalkeeper: 1,
    Defender: 2,
    Midfielder: 3,
    Forward: 4,
  };

  const roster = gameState.players
    .filter((player) => player.team_id === myTeam.id)
    .sort(
      (a, b) =>
        (posOrder[normalisePosition(a.position)] || 99) -
          (posOrder[normalisePosition(b.position)] || 99) ||
        calcOvr(b) - calcOvr(a),
    );

  const formation = myTeam.formation || "4-4-2";
  const activePlayStyle = myTeam.play_style || "Balanced";
  const savedStartingXiKey = (myTeam.starting_xi_ids || []).join(",");
  const playersById = useMemo(
    () => new Map(roster.map((player) => [player.id, player])),
    [roster],
  );
  const available = roster.filter((player) => !player.injury);
  const pitchRows = useMemo(() => buildPitchRows(formation), [formation]);

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
    available.map((player) => player.id).join(","),
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
  const bench = roster.filter((player) => !xiIds.has(player.id));
  const xiActivePosition = useMemo(
    () => buildActivePositionMap(pitchSlotRows),
    [pitchSlotRows],
  );

  const selectedPitchPlayer = selectedPitchPlayerId
    ? playersById.get(selectedPitchPlayerId) || null
    : null;
  const comparePlayer =
    selectedPitchPlayerId &&
    hoveredPitchPlayerId &&
    selectedPitchPlayerId !== hoveredPitchPlayerId
      ? playersById.get(hoveredPitchPlayerId) || null
      : null;

  const toggleSort = (key: SortKey) => {
    if (sortKey === key) {
      setSortDir((current) => (current === "asc" ? "desc" : "asc"));
      return;
    }

    setSortKey(key);
    setSortDir(key === "ovr" ? "desc" : "asc");
  };

  const sortPlayers = (
    players: PlayerData[],
    section: SquadSection,
  ): PlayerData[] => {
    const getPos = (player: PlayerData) =>
      section === "xi"
        ? normalisePosition(xiActivePosition.get(player.id) || player.position)
        : normalisePosition(player.position);

    const sorted = [...players].sort((a, b) => {
      switch (sortKey) {
        case "pos":
          return (
            (posOrder[getPos(a)] || 99) - (posOrder[getPos(b)] || 99) ||
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
    });

    return sortDir === "desc" ? sorted.reverse() : sorted;
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
    ) {
      return false;
    }

    return true;
  };

  const filteredStartingXI = useMemo(
    () =>
      sortPlayers(
        startingXI.filter((player) => matchesFilters(player, "xi")),
        "xi",
      ),
    [
      startingXI,
      playerSearch,
      positionFilter,
      sortKey,
      sortDir,
      xiActivePosition,
    ],
  );
  const filteredBench = useMemo(
    () =>
      sortPlayers(
        bench.filter((player) => matchesFilters(player, "bench")),
        "bench",
      ),
    [bench, playerSearch, positionFilter, sortKey, sortDir],
  );

  const outOfPositionCount = startingXI.filter((player) => {
    const currentPos = xiActivePosition.get(player.id) || player.position;
    return isPlayerOutOfPosition(player, currentPos);
  }).length;

  const persistStartingXI = async (playerIds: string[]) => {
    setPendingStartingXiIds(playerIds);
    try {
      const updated = await invoke<GameStateData>("set_starting_xi", {
        playerIds,
      });
      onGameUpdate(updated);
    } catch (error) {
      setPendingStartingXiIds(null);
      console.error("Failed to set starting XI:", error);
    }
  };

  const handleFormationChange = async (nextFormation: string) => {
    try {
      const updated = await invoke<GameStateData>("set_formation", {
        formation: nextFormation,
      });
      onGameUpdate(updated);
    } catch (error) {
      console.error("Failed to set formation:", error);
    }
  };

  const handlePlayStyleChange = async (playStyle: string) => {
    try {
      const updated = await invoke<GameStateData>("set_play_style", {
        playStyle,
      });
      onGameUpdate(updated);
    } catch (error) {
      console.error("Failed to set play style:", error);
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
    setSelectedPitchPlayerId(null);
    setHoveredPitchPlayerId(null);
    resetDragState();
  };

  const handlePitchPlayerClick = async (playerId: string) => {
    if (!selectedPitchPlayerId) {
      setSelectedPitchPlayerId(playerId);
      setHoveredPitchPlayerId(null);
      return;
    }

    if (selectedPitchPlayerId === playerId) {
      setSelectedPitchPlayerId(null);
      setHoveredPitchPlayerId(null);
      return;
    }

    const nextXiIds = applyLineupSwap(
      startingXiIds,
      { id: selectedPitchPlayerId, from: "xi" },
      playerId,
      "xi",
    );

    if (!nextXiIds || nextXiIds.join(",") === startingXiIds.join(",")) {
      setSelectedPitchPlayerId(null);
      setHoveredPitchPlayerId(null);
      return;
    }

    await persistStartingXI(nextXiIds);
    setSelectedPitchPlayerId(null);
    setHoveredPitchPlayerId(null);
  };

  const renderPreferredPositionMeta = (player: PlayerData) => (
    <div className="text-xs text-gray-400 dark:text-gray-500 flex items-center gap-1.5 flex-wrap">
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

  const SortHeader = ({ col, label }: { col: SortKey; label: string }) => (
    <th
      className={`py-2.5 px-4 font-heading font-bold uppercase tracking-wider cursor-pointer select-none hover:text-primary-400 transition-colors ${sortKey === col ? "text-primary-500 dark:text-primary-400" : "text-gray-500 dark:text-gray-400"}`}
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
        <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
          {t("common.actions", "Actions")}
        </th>
      </tr>
    </thead>
  );

  const renderTableRow = (player: PlayerData, section: SquadSection) => {
    const ovr = calcOvr(player);
    const age = calcAge(player.date_of_birth);
    const activePos =
      section === "xi"
        ? xiActivePosition.get(player.id) || player.position
        : player.position;
    const wrongPos =
      section === "xi" && isPlayerOutOfPosition(player, activePos);
    const isSelected = selectedPitchPlayerId === player.id;

    return (
      <tr
        key={player.id}
        data-testid={`${section}-player-${player.id}`}
        draggable={!player.injury}
        onDragStart={(event) =>
          !player.injury
            ? handleDragStart(
                event,
                player.id,
                section,
                section === "xi" ? startingXiIds.indexOf(player.id) : null,
              )
            : undefined
        }
        onDragEnd={resetDragState}
        onClick={() => onSelectPlayer(player.id)}
        className={`transition-colors group cursor-pointer ${isSelected ? "bg-primary-500/10 dark:bg-primary-500/10" : "hover:bg-gray-50 dark:hover:bg-navy-700/50"}`}
      >
        <td className="py-2.5 px-4">
          <div className="flex items-center gap-1.5">
            <Badge
              variant={positionBadgeVariant(normalisePosition(activePos))}
              size="sm"
            >
              {positionCode(normalisePosition(activePos))}
            </Badge>
            {wrongPos ? (
              <span
                title={t(
                  "squad.outOfPositionTooltip",
                  "Playing outside the player's preferred role",
                )}
                className="text-amber-500"
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
          <div className="flex flex-wrap gap-1.5">
            {section === "bench" && !player.injury ? (
              <Badge variant="primary" size="sm">
                {t("squad.dragToPitch", "Drag to pitch")}
              </Badge>
            ) : null}
            {player.injury ? (
              <Badge variant="danger" size="sm">
                {t("common.injured", "Injured")}
              </Badge>
            ) : null}
          </div>
        </td>
      </tr>
    );
  };

  return (
    <div className="max-w-6xl mx-auto flex flex-col gap-4">
      <div className="grid grid-cols-1 xl:grid-cols-[minmax(0,1.65fr)_minmax(320px,0.95fr)] gap-4 items-start">
        <Card className="overflow-hidden">
          <div className="p-4 border-b border-gray-100 dark:border-navy-600 flex flex-wrap justify-between items-center gap-3 bg-linear-to-r from-navy-700 to-navy-800 rounded-t-xl">
            <div>
              <h3 className="text-sm font-heading font-bold text-white uppercase tracking-wide flex items-center gap-2">
                <Star className="text-accent-400 w-4 h-4 fill-current" />
                {t("preMatch.startingXI", "Starting XI")} — {formation}
              </h3>
              <p className="text-xs text-gray-400 mt-0.5">
                {t(
                  "tactics.pitchInteractionHint",
                  "Drag from the bench table, click a starter to inspect them, and click another starter to swap positions.",
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
              {selectedPitchPlayer ? (
                <button
                  type="button"
                  onClick={() => {
                    setSelectedPitchPlayerId(null);
                    setHoveredPitchPlayerId(null);
                  }}
                  className="text-xs text-accent-400 font-heading font-bold uppercase tracking-wider hover:text-accent-300"
                >
                  {t("common.clear", "Clear")}
                </button>
              ) : null}
            </div>
          </div>
          <div className="p-4 sm:p-6">
            <div className="bg-linear-to-b from-primary-700/20 to-primary-900/30 dark:from-primary-900/40 dark:to-navy-900/60 rounded-xl p-4 sm:p-5 min-h-115 sm:min-h-130 relative border border-primary-500/20 overflow-visible">
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
                    const isSelected = player?.id === selectedPitchPlayerId;
                    const isComparing = player?.id === hoveredPitchPlayerId;

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
                            onClick={() =>
                              void handlePitchPlayerClick(player.id)
                            }
                            onMouseEnter={() => {
                              if (
                                selectedPitchPlayerId &&
                                selectedPitchPlayerId !== player.id
                              ) {
                                setHoveredPitchPlayerId(player.id);
                              }
                            }}
                            onMouseLeave={() => {
                              setHoveredPitchPlayerId((current) =>
                                current === player.id ? null : current,
                              );
                            }}
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
                              isSelected
                                ? "border-accent-300 bg-accent-500/15 ring-2 ring-accent-300/40"
                                : isComparing
                                  ? "border-primary-300 bg-primary-500/12 ring-2 ring-primary-300/30"
                                  : isHovered
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
                              {t("squad.dropPlayerHere", "Drop player here")}
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
        </Card>

        <div className="flex flex-col gap-4">
          <Card>
            <div className="p-4">
              <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 dark:text-gray-400 mb-3">
                {t("tactics.formation")}
              </h3>
              <div className="grid grid-cols-2 sm:grid-cols-4 xl:grid-cols-2 gap-2">
                {FORMATIONS.map((nextFormation) => (
                  <button
                    key={nextFormation}
                    onClick={() => void handleFormationChange(nextFormation)}
                    className={`px-3 py-2 rounded-lg text-xs font-heading font-bold transition-all ${
                      formation === nextFormation
                        ? "bg-primary-500 text-white shadow-sm"
                        : "bg-gray-100 dark:bg-navy-700 text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-navy-600"
                    }`}
                  >
                    {nextFormation}
                  </button>
                ))}
              </div>
            </div>
          </Card>

          <Card>
            <div className="p-4">
              <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 dark:text-gray-400 mb-3">
                {t("tactics.playStyle")}
              </h3>
              <div className="flex flex-wrap gap-1.5">
                {PLAY_STYLES.map((style) => (
                  <button
                    key={style.id}
                    onClick={() => void handlePlayStyleChange(style.id)}
                    className={`flex items-center gap-1.5 px-3 py-2 rounded-lg text-xs font-heading font-bold transition-all ${
                      activePlayStyle === style.id
                        ? "bg-primary-500 text-white shadow-sm"
                        : "bg-gray-100 dark:bg-navy-700 text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-navy-600"
                    }`}
                  >
                    {style.icon}
                    {t(`common.playStyles.${style.id}`)}
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

          <TacticsPlayerFocusPanel
            selectedPlayer={selectedPitchPlayer}
            comparePlayer={comparePlayer}
          />
        </div>
      </div>

      <Card>
        <div className="p-4 grid grid-cols-1 lg:grid-cols-[minmax(0,1.3fr)_220px_auto] gap-3 items-end">
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
            <Select
              value={positionFilter}
              onChange={(event) => setPositionFilter(event.target.value)}
              fullWidth
            >
              <option value="All">{t("common.all", "All")}</option>
              {CORE_POSITIONS.map((position) => (
                <option key={position} value={position}>
                  {t(`common.posAbbr.${position}`, positionCode(position))}
                </option>
              ))}
            </Select>
          </div>
          <button
            type="button"
            onClick={() => {
              setPlayerSearch("");
              setPositionFilter("All");
            }}
            disabled={
              playerSearch.trim().length === 0 && positionFilter === "All"
            }
            className={`px-3 py-2 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
              playerSearch.trim().length > 0 || positionFilter !== "All"
                ? "bg-gray-100 dark:bg-navy-700 text-gray-600 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-navy-600"
                : "bg-gray-100 dark:bg-navy-700 text-gray-400 cursor-not-allowed"
            }`}
          >
            {t("common.clear", "Clear")}
          </button>
        </div>
      </Card>

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
              {filteredStartingXI.map((player) => renderTableRow(player, "xi"))}
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
              {filteredBench.map((player) => renderTableRow(player, "bench"))}
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
    </div>
  );
}
