import { useState, useMemo } from "react";
import { invoke } from "@tauri-apps/api/core";
import { GameStateData, PlayerData } from "../store/gameStore";
import { Card, Badge, ProgressBar } from "./ui";
import { Star, ArrowRightLeft, Users, Shield, Crosshair, Zap, Target, RefreshCw, Flag } from "lucide-react";
import { formatVal, positionBadgeVariant, calcOvr, calcAge } from "../lib/helpers";
import { TraitList } from "./TraitBadge";
import { useTranslation } from "react-i18next";

interface SquadTabProps {
  gameState: GameStateData;
  managerId: string;
  onSelectPlayer: (id: string) => void;
  onGameUpdate?: (g: GameStateData) => void;
}

const FORMATIONS = ["4-4-2", "4-3-3", "3-5-2", "4-5-1", "4-2-3-1", "3-4-3"];
const PLAY_STYLES = [
  { id: "Balanced", icon: <Target className="w-3.5 h-3.5" /> },
  { id: "Attacking", icon: <Zap className="w-3.5 h-3.5" /> },
  { id: "Defensive", icon: <Shield className="w-3.5 h-3.5" /> },
  { id: "Possession", icon: <RefreshCw className="w-3.5 h-3.5" /> },
  { id: "Counter", icon: <Crosshair className="w-3.5 h-3.5" /> },
  { id: "HighPress", icon: <Flag className="w-3.5 h-3.5" /> },
];

function parseFormationSlots(formation: string): { def: number; mid: number; fwd: number } {
  const parts = formation.split('-').map(Number);
  if (parts.length === 4) return { def: parts[0], mid: parts[1] + parts[2], fwd: parts[3] };
  if (parts.length === 3) return { def: parts[0], mid: parts[1], fwd: parts[2] };
  return { def: 4, mid: 4, fwd: 2 };
}

export default function SquadTab({ gameState, managerId, onSelectPlayer, onGameUpdate }: SquadTabProps) {
  const { t } = useTranslation();
  const myTeam = gameState.teams.find(t => t.manager_id === managerId);
  const [swapSource, setSwapSource] = useState<{ id: string; from: "xi" | "bench" } | null>(null);
  const [activeView, setActiveView] = useState<"lineup" | "roster">("lineup");

  if (!myTeam) return <p className="text-gray-500 dark:text-gray-400">{t('common.unemployed')}</p>;

  const posOrder: Record<string, number> = { "Goalkeeper": 1, "Defender": 2, "Midfielder": 3, "Forward": 4 };
  const roster = gameState.players
    .filter(p => p.team_id === myTeam.id)
    .sort((a, b) => (posOrder[a.position] || 99) - (posOrder[b.position] || 99) || calcOvr(b) - calcOvr(a));

  const formation = myTeam.formation || "4-4-2";
  const slots = parseFormationSlots(formation);

  // Build starting XI: best available by position for current formation
  const available = roster.filter(p => !p.injury);
  const startingXI = useMemo(() => {
    const xi: PlayerData[] = [];
    const used = new Set<string>();
    const pick = (pos: string, count: number) => {
      const candidates = available.filter(p => p.position === pos && !used.has(p.id)).sort((a, b) => calcOvr(b) - calcOvr(a));
      for (let i = 0; i < count && i < candidates.length; i++) {
        xi.push(candidates[i]);
        used.add(candidates[i].id);
      }
    };
    pick("Goalkeeper", 1);
    pick("Defender", slots.def);
    pick("Midfielder", slots.mid);
    pick("Forward", slots.fwd);
    return xi;
  }, [available.map(p => p.id).join(','), formation]);

  const xiIds = new Set(startingXI.map(p => p.id));
  const bench = roster.filter(p => !xiIds.has(p.id));

  const handleFormationChange = async (f: string) => {
    try {
      const updated = await invoke<GameStateData>("set_formation", { formation: f });
      onGameUpdate?.(updated);
    } catch (err) {
      console.error("Failed to set formation:", err);
    }
  };

  const handlePlayStyleChange = async (ps: string) => {
    try {
      const updated = await invoke<GameStateData>("set_play_style", { playStyle: ps });
      onGameUpdate?.(updated);
    } catch (err) {
      console.error("Failed to set play style:", err);
    }
  };

  const handleSwapClick = (playerId: string, from: "xi" | "bench") => {
    if (swapSource) {
      if (swapSource.id === playerId) {
        setSwapSource(null);
        return;
      }
      // Swap is just visual — user navigates to see their preferred lineup
      setSwapSource(null);
    } else {
      setSwapSource({ id: playerId, from });
    }
  };

  const renderPlayerRow = (player: PlayerData, section: "xi" | "bench") => {
    const ovr = calcOvr(player);
    const age = calcAge(player.date_of_birth);
    const isSwapSource = swapSource?.id === player.id;
    const isSwapTarget = swapSource && swapSource.id !== player.id;

    return (
      <tr
        key={player.id}
        className={`transition-colors group ${isSwapSource ? 'bg-accent-500/10 dark:bg-accent-500/10' : isSwapTarget ? 'hover:bg-primary-500/10 dark:hover:bg-primary-500/10 cursor-pointer' : 'hover:bg-gray-50 dark:hover:bg-navy-700/50'}`}
      >
        <td className="py-2.5 px-4">
          <Badge variant={positionBadgeVariant(player.position)} size="sm">
            {player.position.substring(0, 3).toUpperCase()}
          </Badge>
        </td>
        <td className="py-2.5 px-4">
          <button onClick={() => onSelectPlayer(player.id)} className="text-left">
            <div className="font-semibold text-sm text-gray-900 dark:text-gray-100 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors">{player.full_name}</div>
            <div className="text-xs text-gray-400 dark:text-gray-500">{player.nationality}</div>
          </button>
        </td>
        <td className="py-2.5 px-4 text-sm text-gray-600 dark:text-gray-400 tabular-nums">{age}</td>
        <td className="py-2.5 px-4 w-28">
          <ProgressBar value={player.condition} variant="auto" size="sm" showLabel />
        </td>
        <td className="py-2.5 px-4 text-sm text-gray-500 dark:text-gray-400 tabular-nums">{player.morale}</td>
        <td className="py-2.5 px-4">
          {player.traits && player.traits.length > 0 ? (
            <TraitList traits={player.traits} size="xs" max={2} />
          ) : (
            <span className="text-xs text-gray-500">—</span>
          )}
        </td>
        <td className="py-2.5 px-4">
          <span className={`font-heading font-bold text-base tabular-nums ${
            ovr >= 75 ? 'text-success-500 dark:text-success-400' :
            ovr >= 55 ? 'text-accent-600 dark:text-accent-400' :
            'text-gray-500 dark:text-gray-400'
          }`}>{ovr}</span>
        </td>
        <td className="py-2.5 px-4">
          {player.injury ? (
            <Badge variant="danger" size="sm">{t('common.injured')}</Badge>
          ) : (
            <button
              onClick={() => handleSwapClick(player.id, section)}
              className={`p-1.5 rounded-lg transition-colors ${isSwapSource ? 'bg-accent-500 text-white' : 'text-gray-400 hover:text-primary-500 hover:bg-gray-100 dark:hover:bg-navy-600'}`}
              title="Swap player"
            >
              <ArrowRightLeft className="w-3.5 h-3.5" />
            </button>
          )}
        </td>
      </tr>
    );
  };

  const tableHead = (
    <thead>
      <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
        <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('squad.pos')}</th>
        <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('common.name')}</th>
        <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('common.age')}</th>
        <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('common.condition')}</th>
        <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('common.morale')}</th>
        <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('squad.traits')}</th>
        <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('common.ovr')}</th>
        <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 w-12"></th>
      </tr>
    </thead>
  );

  return (
    <div className="max-w-6xl mx-auto flex flex-col gap-4">
      {/* Header with Formation & Play Style */}
      <div className="flex flex-wrap gap-4">
        {/* Formation Card */}
        <Card className="flex-1 min-w-[280px]">
          <div className="p-4">
            <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 dark:text-gray-400 mb-3">{t('tactics.formation')}</h3>
            <div className="flex flex-wrap gap-1.5">
              {FORMATIONS.map(f => (
                <button
                  key={f}
                  onClick={() => handleFormationChange(f)}
                  className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold transition-all ${
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
        <Card className="flex-1 min-w-[280px]">
          <div className="p-4">
            <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 dark:text-gray-400 mb-3">{t('tactics.playStyle')}</h3>
            <div className="flex flex-wrap gap-1.5">
              {PLAY_STYLES.map(s => (
                <button
                  key={s.id}
                  onClick={() => handlePlayStyleChange(s.id)}
                  className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-heading font-bold transition-all ${
                    myTeam.play_style === s.id
                      ? "bg-primary-500 text-white shadow-sm"
                      : "bg-gray-100 dark:bg-navy-700 text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-navy-600"
                  }`}
                >
                  {s.icon}
                  {t(`common.playStyles.${s.id}`)}
                </button>
              ))}
            </div>
          </div>
        </Card>
      </div>

      {/* View Tabs */}
      <div className="flex gap-1 bg-gray-100 dark:bg-navy-800 rounded-lg p-1 w-fit">
        <button
          onClick={() => setActiveView("lineup")}
          className={`flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
            activeView === "lineup" ? "bg-white dark:bg-navy-600 text-primary-600 dark:text-primary-400 shadow-sm" : "text-gray-500 dark:text-gray-400"
          }`}
        >
          <Star className="w-4 h-4" /> {t('preMatch.startingXI', 'Starting XI')}
        </button>
        <button
          onClick={() => setActiveView("roster")}
          className={`flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
            activeView === "roster" ? "bg-white dark:bg-navy-600 text-primary-600 dark:text-primary-400 shadow-sm" : "text-gray-500 dark:text-gray-400"
          }`}
        >
          <Users className="w-4 h-4" /> {t('squad.fullRoster', 'Full Roster')}
        </button>
      </div>

      {activeView === "lineup" ? (
        <>
          {/* Starting XI */}
          <Card>
            <div className="p-4 border-b border-gray-100 dark:border-navy-600 flex justify-between items-center bg-gradient-to-r from-navy-700 to-navy-800 rounded-t-xl">
              <div>
                <h3 className="text-sm font-heading font-bold text-white uppercase tracking-wide flex items-center gap-2">
                  <Star className="text-accent-400 w-4 h-4 fill-current" />
                  {t('preMatch.startingXI', 'Starting XI')} — {formation}
                </h3>
                <p className="text-xs text-gray-400 mt-0.5">{startingXI.length} / 11 {t('squad.selected', 'selected')}</p>
              </div>
              {swapSource && (
                <button onClick={() => setSwapSource(null)} className="text-xs text-accent-400 font-heading font-bold uppercase tracking-wider hover:text-accent-300">
                  {t('common.cancel')}
                </button>
              )}
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                {tableHead}
                <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                  {startingXI.map(p => renderPlayerRow(p, "xi"))}
                </tbody>
              </table>
            </div>
          </Card>

          {/* Bench */}
          <Card>
            <div className="p-4 border-b border-gray-100 dark:border-navy-600">
              <h3 className="text-sm font-heading font-bold text-gray-800 dark:text-gray-200 uppercase tracking-wide flex items-center gap-2">
                {t('preMatch.substitutes', 'Substitutes')}
              </h3>
              <p className="text-xs text-gray-400 mt-0.5">{bench.length} {t('squad.playersLabel', 'players')}</p>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                {tableHead}
                <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                  {bench.map(p => renderPlayerRow(p, "bench"))}
                </tbody>
              </table>
              {bench.length === 0 && (
                <div className="p-6 text-center text-gray-500 dark:text-gray-400 text-sm">{t('squad.noBench', 'No bench players.')}</div>
              )}
            </div>
          </Card>
        </>
      ) : (
        /* Full Roster view */
        <Card>
          <div className="p-4 border-b border-gray-100 dark:border-navy-600 bg-gradient-to-r from-navy-700 to-navy-800 rounded-t-xl">
            <h3 className="text-sm font-heading font-bold text-white uppercase tracking-wide flex items-center gap-2">
              <Users className="w-4 h-4 text-accent-400" />
              {t('squad.title', { team: myTeam.name })}
            </h3>
            <p className="text-xs text-gray-400 mt-0.5">{t('squad.playerCount', { count: roster.length })}</p>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
                  <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('squad.pos')}</th>
                  <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('common.name')}</th>
                  <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('common.age')}</th>
                  <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('common.condition')}</th>
                  <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('common.morale')}</th>
                  <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('squad.traits')}</th>
                  <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('common.value')}</th>
                  <th className="py-2.5 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">{t('common.ovr')}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                {roster.map(player => {
                  const ovr = calcOvr(player);
                  const age = calcAge(player.date_of_birth);
                  const inXI = xiIds.has(player.id);
                  return (
                    <tr key={player.id} onClick={() => onSelectPlayer(player.id)} className="hover:bg-gray-50 dark:hover:bg-navy-700/50 transition-colors group cursor-pointer">
                      <td className="py-2.5 px-4">
                        <div className="flex items-center gap-1.5">
                          {inXI && <span className="w-1.5 h-1.5 rounded-full bg-primary-500" title="Starting XI" />}
                          <Badge variant={positionBadgeVariant(player.position)} size="sm">
                            {player.position.substring(0, 3).toUpperCase()}
                          </Badge>
                        </div>
                      </td>
                      <td className="py-2.5 px-4">
                        <div className="font-semibold text-sm text-gray-900 dark:text-gray-100 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors">{player.full_name}</div>
                        <div className="text-xs text-gray-400 dark:text-gray-500">{player.nationality}</div>
                      </td>
                      <td className="py-2.5 px-4 text-sm text-gray-600 dark:text-gray-400 tabular-nums">{age}</td>
                      <td className="py-2.5 px-4 w-28">
                        <ProgressBar value={player.condition} variant="auto" size="sm" showLabel />
                      </td>
                      <td className="py-2.5 px-4 text-sm text-gray-500 dark:text-gray-400 tabular-nums">{player.morale}</td>
                      <td className="py-2.5 px-4">
                        {player.traits && player.traits.length > 0 ? (
                          <TraitList traits={player.traits} size="xs" max={2} />
                        ) : (
                          <span className="text-xs text-gray-500">—</span>
                        )}
                      </td>
                      <td className="py-2.5 px-4 text-xs text-gray-600 dark:text-gray-400 font-medium">{formatVal(player.market_value)}</td>
                      <td className="py-2.5 px-4">
                        <span className={`font-heading font-bold text-base tabular-nums ${
                          ovr >= 75 ? 'text-success-500 dark:text-success-400' :
                          ovr >= 55 ? 'text-accent-600 dark:text-accent-400' :
                          'text-gray-500 dark:text-gray-400'
                        }`}>{ovr}</span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            {roster.length === 0 && (
              <div className="p-8 text-center text-gray-500 dark:text-gray-400 font-heading uppercase tracking-wider text-sm">{t('squad.noPlayers')}</div>
            )}
          </div>
        </Card>
      )}
    </div>
  );
}
