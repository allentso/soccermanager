import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { GameStateData, PlayerData } from "../../store/gameStore";
import { MatchSnapshot, EnginePlayerData, FORMATIONS, PLAY_STYLES } from "./types";
import { Badge } from "../ui";
import {
  ChevronRight, Shield, Zap, Target, RefreshCw, Crosshair, Flag,
  Crown, Footprints, CornerDownRight, CircleDot, ArrowUpDown, Check,
  Wand2, AlertTriangle
} from "lucide-react";

interface PreMatchSetupProps {
  snapshot: MatchSnapshot;
  gameState: GameStateData;
  userSide: "Home" | "Away";
  onStart: () => void;
  onUpdateSnapshot: (snap: MatchSnapshot) => void;
}

const PLAY_STYLE_ICONS: Record<string, React.ReactNode> = {
  Balanced: <Target className="w-4 h-4" />,
  Attacking: <Zap className="w-4 h-4" />,
  Defensive: <Shield className="w-4 h-4" />,
  Possession: <RefreshCw className="w-4 h-4" />,
  Counter: <Crosshair className="w-4 h-4" />,
  HighPress: <Flag className="w-4 h-4" />,
};

const POSITION_KEY_STATS: Record<string, { label: string; key: string }[]> = {
  Goalkeeper: [{ label: "HAN", key: "handling" }, { label: "REF", key: "reflexes" }, { label: "AER", key: "aerial" }],
  Defender: [{ label: "DEF", key: "defending" }, { label: "TAC", key: "tackling" }, { label: "STR", key: "strength" }],
  Midfielder: [{ label: "PAS", key: "passing" }, { label: "VIS", key: "vision" }, { label: "STA", key: "stamina" }],
  Forward: [{ label: "SHO", key: "shooting" }, { label: "PAC", key: "pace" }, { label: "DRI", key: "dribbling" }],
};

function parseFormationNeeds(formation: string): Record<string, number> {
  const parts = formation.split("-").map(Number).filter(n => !isNaN(n));
  if (parts.length === 3) return { Goalkeeper: 1, Defender: parts[0], Midfielder: parts[1], Forward: parts[2] };
  if (parts.length === 4) return { Goalkeeper: parts[0], Defender: parts[1], Midfielder: parts[2], Forward: parts[3] };
  return { Goalkeeper: 1, Defender: 4, Midfielder: 4, Forward: 2 };
}

function getPositionOvr(p: EnginePlayerData): number {
  switch (p.position) {
    case "Goalkeeper": return Math.round((p.handling * 2 + p.reflexes * 2 + p.aerial + p.positioning + p.composure) / 7);
    case "Defender": return Math.round((p.defending * 2 + p.tackling * 2 + p.strength + p.positioning + p.aerial) / 7);
    case "Midfielder": return Math.round((p.passing * 2 + p.vision + p.decisions + p.stamina + p.dribbling + p.teamwork) / 7);
    case "Forward": return Math.round((p.shooting * 2 + p.pace + p.dribbling + p.composure + p.strength + p.positioning) / 7);
    default: return 50;
  }
}

function condColor(c: number): string {
  if (c >= 75) return "text-primary-400";
  if (c >= 50) return "text-amber-400";
  return "text-red-400";
}

function statColor(v: number): string {
  if (v >= 75) return "text-primary-400 font-bold";
  if (v >= 60) return "text-gray-200";
  return "text-gray-500";
}

function getStatVal(p: EnginePlayerData, key: string): number {
  return (p as unknown as Record<string, number>)[key] ?? 0;
}

export default function PreMatchSetup({ snapshot, gameState, userSide, onStart, onUpdateSnapshot }: PreMatchSetupProps) {
  const [activeTab, setActiveTab] = useState<"lineup" | "setpieces">("lineup");
  const [selectedStarterId, setSelectedStarterId] = useState<string | null>(null);
  const [isAutoSelecting, setIsAutoSelecting] = useState(false);

  const userTeam = userSide === "Home" ? snapshot.home_team : snapshot.away_team;
  const oppTeam = userSide === "Home" ? snapshot.away_team : snapshot.home_team;
  const userSetPieces = userSide === "Home" ? snapshot.home_set_pieces : snapshot.away_set_pieces;

  const homeTeamColor = gameState.teams.find(t => t.id === snapshot.home_team.id)?.colors?.primary || "#10b981";
  const awayTeamColor = gameState.teams.find(t => t.id === snapshot.away_team.id)?.colors?.primary || "#6366f1";
  const userColor = userSide === "Home" ? homeTeamColor : awayTeamColor;

  // All squad players for this team
  const allSquadPlayers = gameState.players.filter(p => p.team_id === userTeam.id);
  // Use snapshot bench data (updated after swaps)
  const userBench = userSide === "Home" ? (snapshot.home_bench || []) : (snapshot.away_bench || []);

  const handleFormationChange = async (formation: string) => {
    try {
      const snap = await invoke<MatchSnapshot>("apply_match_command", {
        command: { ChangeFormation: { side: userSide, formation } }
      });
      onUpdateSnapshot(snap);
    } catch (err) {
      console.error("Formation change failed:", err);
    }
  };

  const handlePlayStyleChange = async (playStyle: string) => {
    try {
      const snap = await invoke<MatchSnapshot>("apply_match_command", {
        command: { ChangePlayStyle: { side: userSide, play_style: playStyle } }
      });
      onUpdateSnapshot(snap);
    } catch (err) {
      console.error("Play style change failed:", err);
    }
  };

  const handleSwap = async (benchPlayerId: string) => {
    if (!selectedStarterId) return;
    try {
      const snap = await invoke<MatchSnapshot>("apply_match_command", {
        command: { PreMatchSwap: { side: userSide, player_off_id: selectedStarterId, player_on_id: benchPlayerId } }
      });
      onUpdateSnapshot(snap);
    } catch (err) {
      console.error("Pre-match swap failed:", err);
    }
    setSelectedStarterId(null);
  };

  const handleSetPieceTaker = async (role: string, playerId: string) => {
    const commandMap: Record<string, string> = {
      penalty: "SetPenaltyTaker",
      freekick: "SetFreeKickTaker",
      corner: "SetCornerTaker",
      captain: "SetCaptain",
    };
    const cmdKey = commandMap[role];
    if (!cmdKey) return;
    try {
      const snap = await invoke<MatchSnapshot>("apply_match_command", {
        command: { [cmdKey]: { side: userSide, player_id: playerId } }
      });
      onUpdateSnapshot(snap);
    } catch (err) {
      console.error("Set piece taker change failed:", err);
    }
  };

  const formationNeeds = parseFormationNeeds(userTeam.formation);

  const handleAutoSelect = async () => {
    setIsAutoSelecting(true);
    try {
      const pool = [...userTeam.players, ...userBench];
      const idealIds = new Set<string>();

      for (const pos of ["Goalkeeper", "Defender", "Midfielder", "Forward"]) {
        const candidates = pool
          .filter(p => p.position === pos)
          .sort((a, b) => getPositionOvr(b) * (b.condition / 100) - getPositionOvr(a) * (a.condition / 100));
        const needed = formationNeeds[pos] || 0;
        for (let i = 0; i < Math.min(needed, candidates.length); i++) {
          idealIds.add(candidates[i].id);
        }
      }

      // Fill remaining slots if fewer than 11 (e.g. not enough of a position)
      if (idealIds.size < 11) {
        const rest = pool
          .filter(p => !idealIds.has(p.id))
          .sort((a, b) => getPositionOvr(b) * (b.condition / 100) - getPositionOvr(a) * (a.condition / 100));
        for (const p of rest) {
          if (idealIds.size >= 11) break;
          idealIds.add(p.id);
        }
      }

      const currentIds = new Set(userTeam.players.map(p => p.id));
      const toAdd = [...idealIds].filter(id => !currentIds.has(id));
      const toRemove = [...currentIds].filter(id => !idealIds.has(id));

      let snap: MatchSnapshot | null = null;
      for (let i = 0; i < Math.min(toAdd.length, toRemove.length); i++) {
        snap = await invoke<MatchSnapshot>("apply_match_command", {
          command: { PreMatchSwap: { side: userSide, player_off_id: toRemove[i], player_on_id: toAdd[i] } }
        });
      }
      if (snap) onUpdateSnapshot(snap);
    } catch (err) {
      console.error("Auto-select failed:", err);
    } finally {
      setIsAutoSelecting(false);
      setSelectedStarterId(null);
    }
  };

  const positions = ["Goalkeeper", "Defender", "Midfielder", "Forward"];

  return (
    <div className="min-h-screen bg-navy-900 text-white flex flex-col">
      {/* Header */}
      <header className="bg-gradient-to-r from-navy-800 via-navy-900 to-navy-800 border-b border-navy-700">
        <div className="max-w-5xl mx-auto px-6 py-6">
          {/* Match banner */}
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-4">
              <div
                className="w-14 h-14 rounded-xl flex items-center justify-center font-heading font-bold text-lg"
                style={{ backgroundColor: homeTeamColor + "30", borderColor: homeTeamColor, borderWidth: 2 }}
              >
                {snapshot.home_team.name.substring(0, 3).toUpperCase()}
              </div>
              <div>
                <p className="font-heading font-bold text-lg text-white">{snapshot.home_team.name}</p>
                <p className="text-xs text-gray-500">Home</p>
              </div>
            </div>

            <div className="text-center">
              <p className="text-xs font-heading uppercase tracking-widest text-accent-400 mb-1">Match Day</p>
              <p className="text-3xl font-heading font-bold text-gray-500">VS</p>
            </div>

            <div className="flex items-center gap-4">
              <div className="text-right">
                <p className="font-heading font-bold text-lg text-white">{snapshot.away_team.name}</p>
                <p className="text-xs text-gray-500">Away</p>
              </div>
              <div
                className="w-14 h-14 rounded-xl flex items-center justify-center font-heading font-bold text-lg"
                style={{ backgroundColor: awayTeamColor + "30", borderColor: awayTeamColor, borderWidth: 2 }}
              >
                {snapshot.away_team.name.substring(0, 3).toUpperCase()}
              </div>
            </div>
          </div>

          <div className="text-center">
            <p className="text-sm font-heading uppercase tracking-widest text-primary-400">
              Pre-Match Preparation
            </p>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <div className="flex-1 overflow-auto">
        <div className="max-w-5xl mx-auto px-6 py-6 flex flex-col gap-6">

          {/* Formation & Play Style */}
          <div className="grid grid-cols-2 gap-4">
            {/* Formation */}
            <div className="bg-navy-800 rounded-xl border border-navy-700 p-4">
              <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 mb-3">
                Formation
              </h3>
              <div className="grid grid-cols-3 gap-2">
                {FORMATIONS.map(f => (
                  <button
                    key={f}
                    onClick={() => handleFormationChange(f)}
                    className={`py-2.5 rounded-lg text-sm font-heading font-bold transition-all ${
                      userTeam.formation === f
                        ? "bg-primary-500/20 text-primary-400 ring-2 ring-primary-500/50"
                        : "bg-navy-700 text-gray-400 hover:text-gray-200 hover:bg-navy-600"
                    }`}
                  >
                    {f}
                  </button>
                ))}
              </div>
            </div>

            {/* Play Style */}
            <div className="bg-navy-800 rounded-xl border border-navy-700 p-4">
              <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 mb-3">
                Play Style
              </h3>
              <div className="grid grid-cols-2 gap-2">
                {PLAY_STYLES.map(s => (
                  <button
                    key={s.id}
                    onClick={() => handlePlayStyleChange(s.id)}
                    className={`flex items-center gap-2 py-2.5 px-3 rounded-lg text-sm font-heading font-bold transition-all ${
                      userTeam.play_style === s.id
                        ? "bg-primary-500/20 text-primary-400 ring-2 ring-primary-500/50"
                        : "bg-navy-700 text-gray-400 hover:text-gray-200 hover:bg-navy-600"
                    }`}
                  >
                    {PLAY_STYLE_ICONS[s.id]}
                    {s.label}
                  </button>
                ))}
              </div>
            </div>
          </div>

          {/* Tabs */}
          <div className="flex gap-1 bg-navy-800 rounded-lg p-1 self-start">
            <button
              onClick={() => setActiveTab("lineup")}
              className={`px-4 py-2 rounded-md text-xs font-heading font-bold uppercase tracking-wider transition-colors ${
                activeTab === "lineup" ? "bg-navy-600 text-white" : "text-gray-500 hover:text-gray-300"
              }`}
            >
              Starting Lineup
            </button>
            <button
              onClick={() => setActiveTab("setpieces")}
              className={`px-4 py-2 rounded-md text-xs font-heading font-bold uppercase tracking-wider transition-colors ${
                activeTab === "setpieces" ? "bg-navy-600 text-white" : "text-gray-500 hover:text-gray-300"
              }`}
            >
              Set Pieces & Captain
            </button>
          </div>

          {/* Lineup Tab */}
          {activeTab === "lineup" && (
            <div className="flex flex-col gap-4">
              {/* Formation Balance Bar + Auto-Select */}
              <div className="bg-navy-800 rounded-xl border border-navy-700 p-3 flex items-center justify-between">
                <div className="flex items-center gap-4">
                  <span className="text-[10px] font-heading uppercase tracking-widest text-gray-600">Formation Fit</span>
                  {(["Goalkeeper", "Defender", "Midfielder", "Forward"] as const).map(pos => {
                    const needed = formationNeeds[pos] || 0;
                    const actual = userTeam.players.filter(p => p.position === pos).length;
                    const ok = actual === needed;
                    return (
                      <div key={pos} className="flex items-center gap-1">
                        <span className="text-[10px] font-heading uppercase tracking-widest text-gray-500">{pos.substring(0, 3)}</span>
                        <span className={`text-sm font-heading font-bold tabular-nums ${ok ? "text-primary-400" : "text-amber-400"}`}>
                          {actual}/{needed}
                        </span>
                        {!ok && <AlertTriangle className="w-3 h-3 text-amber-400" />}
                      </div>
                    );
                  })}
                </div>
                <button
                  onClick={handleAutoSelect}
                  disabled={isAutoSelecting}
                  className={`flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
                    isAutoSelecting
                      ? "bg-navy-700 text-gray-500 cursor-wait"
                      : "bg-accent-500/20 text-accent-400 hover:bg-accent-500/30 hover:text-accent-300"
                  }`}
                >
                  <Wand2 className="w-3.5 h-3.5" />
                  {isAutoSelecting ? "Selecting..." : "Auto-Select Best XI"}
                </button>
              </div>

              <div className="grid grid-cols-2 gap-4">
                {/* Starting XI */}
                <div className="bg-navy-800 rounded-xl border border-navy-700 p-4">
                  <div className="flex items-center justify-between mb-3">
                    <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500">
                      Starting XI
                    </h3>
                    <div className="flex items-center gap-2">
                      {selectedStarterId && (
                        <button onClick={() => setSelectedStarterId(null)} className="text-[10px] text-gray-500 hover:text-gray-300 font-heading uppercase tracking-wider">Cancel</button>
                      )}
                      <Badge variant="primary" size="sm">{userTeam.players.length} players</Badge>
                    </div>
                  </div>
                  {selectedStarterId && (
                    <p className="text-[10px] text-accent-400 font-heading uppercase tracking-wider mb-2">Select a bench player to swap with</p>
                  )}
                  {positions.map(pos => {
                    const players = userTeam.players.filter(p => p.position === pos);
                    if (players.length === 0) return null;
                    const needed = formationNeeds[pos] || 0;
                    const balanced = players.length === needed;
                    const keyStats = POSITION_KEY_STATS[pos] || [];
                    return (
                      <div key={pos} className="mb-3">
                        <div className="flex items-center justify-between mb-1">
                          <div className="flex items-center gap-1.5">
                            <p className="text-[10px] font-heading uppercase tracking-widest text-gray-600">{pos}s</p>
                            {!balanced && (
                              <span className="flex items-center gap-0.5">
                                <AlertTriangle className="w-2.5 h-2.5 text-amber-400" />
                                <span className="text-[9px] font-heading text-amber-400">{players.length}/{needed}</span>
                              </span>
                            )}
                          </div>
                          {/* Stat column headers */}
                          <div className="flex items-center gap-0">
                            {keyStats.map(s => (
                              <span key={s.label} className="text-[8px] font-heading uppercase tracking-widest text-gray-600 w-7 text-center">{s.label}</span>
                            ))}
                            <span className="text-[8px] font-heading uppercase tracking-widest text-gray-600 w-8 text-right">FIT</span>
                          </div>
                        </div>
                        {players.map(p => {
                          const posOvr = getPositionOvr(p);
                          const isSelected = selectedStarterId === p.id;
                          return (
                            <button
                              key={p.id}
                              onClick={() => setSelectedStarterId(isSelected ? null : p.id)}
                              className={`flex items-center gap-2 py-1.5 px-2 rounded w-full text-left transition-all ${
                                isSelected
                                  ? "bg-primary-500/20 ring-1 ring-primary-500/50"
                                  : "hover:bg-navy-700/50"
                              }`}
                            >
                              <div
                                className="w-7 h-7 rounded-full flex items-center justify-center text-[10px] font-heading font-bold flex-shrink-0"
                                style={{ backgroundColor: userColor + "30", color: userColor }}
                              >
                                {posOvr}
                              </div>
                              <span className="text-sm text-gray-200 font-medium flex-1 truncate">{p.name}</span>
                              {isSelected && <ArrowUpDown className="w-3.5 h-3.5 text-primary-400 flex-shrink-0" />}
                              <div className="flex items-center gap-0">
                                {keyStats.map(s => (
                                  <span key={s.label} className={`text-[10px] font-heading tabular-nums w-7 text-center ${statColor(getStatVal(p, s.key))}`}>
                                    {getStatVal(p, s.key)}
                                  </span>
                                ))}
                              </div>
                              <span className={`text-xs tabular-nums w-8 text-right ${condColor(p.condition)}`}>{Math.round(p.condition)}%</span>
                            </button>
                          );
                        })}
                      </div>
                    );
                  })}
                </div>

                {/* Bench */}
                <div className="bg-navy-800 rounded-xl border border-navy-700 p-4">
                  <div className="flex items-center justify-between mb-3">
                    <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500">
                      Substitutes
                    </h3>
                    <Badge variant="neutral" size="sm">{userBench.length} available</Badge>
                  </div>
                  {userBench.length === 0 ? (
                    <p className="text-xs text-gray-600">No bench players available.</p>
                  ) : (
                    <div className="flex flex-col gap-1">
                      {/* Bench column header */}
                      <div className="flex items-center gap-2 px-2 pb-1">
                        <span className="w-7" />
                        <span className="flex-1" />
                        <span className="text-[8px] font-heading uppercase tracking-widest text-gray-600 w-8 text-center">POS</span>
                        <span className="text-[8px] font-heading uppercase tracking-widest text-gray-600 w-[84px] text-center">Key Stats</span>
                        <span className="text-[8px] font-heading uppercase tracking-widest text-gray-600 w-8 text-right">FIT</span>
                      </div>
                      {userBench.map(bp => {
                        const posOvr = getPositionOvr(bp);
                        const keyStats = POSITION_KEY_STATS[bp.position] || [];
                        return (
                          <button
                            key={bp.id}
                            onClick={() => selectedStarterId ? handleSwap(bp.id) : null}
                            className={`flex items-center gap-2 py-1.5 px-2 rounded w-full text-left transition-all ${
                              selectedStarterId
                                ? "hover:bg-primary-500/20 hover:ring-1 hover:ring-primary-500/50 cursor-pointer"
                                : "hover:bg-navy-700/50"
                            }`}
                          >
                            <div className="w-7 h-7 rounded-full bg-navy-600 flex items-center justify-center text-[10px] font-heading font-bold text-gray-400 flex-shrink-0">
                              {posOvr}
                            </div>
                            <span className="text-sm text-gray-300 font-medium flex-1 truncate">{bp.name}</span>
                            <Badge variant="neutral" size="sm">{bp.position.substring(0, 3)}</Badge>
                            <div className="flex items-center gap-0">
                              {keyStats.map(s => (
                                <span key={s.label} className={`text-[10px] font-heading tabular-nums w-7 text-center ${statColor(getStatVal(bp, s.key))}`}>
                                  {getStatVal(bp, s.key)}
                                </span>
                              ))}
                            </div>
                            <span className={`text-xs tabular-nums w-8 text-right ${condColor(bp.condition)}`}>{Math.round(bp.condition)}%</span>
                          </button>
                        );
                      })}
                    </div>
                  )}

                  {/* Opponent Info */}
                  <div className="mt-6 pt-4 border-t border-navy-700">
                    <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 mb-3">
                      Opponent
                    </h3>
                    <div className="flex items-center gap-3 mb-2">
                      <div
                        className="w-10 h-10 rounded-lg flex items-center justify-center font-heading font-bold text-sm"
                        style={{ backgroundColor: (userSide === "Home" ? awayTeamColor : homeTeamColor) + "30" }}
                      >
                        {oppTeam.name.substring(0, 3).toUpperCase()}
                      </div>
                      <div>
                        <p className="font-heading font-bold text-sm text-gray-200">{oppTeam.name}</p>
                        <p className="text-xs text-gray-500">{oppTeam.formation} · {oppTeam.play_style}</p>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Set Pieces Tab */}
          {activeTab === "setpieces" && (
            <div className="bg-navy-800 rounded-xl border border-navy-700 p-4">
              <SetPieceSelector
                label="Captain"
                icon={<Crown className="w-4 h-4 text-accent-400" />}
                role="captain"
                currentId={userSetPieces.captain}
                players={userTeam.players}
                allSquad={allSquadPlayers}
                onSelect={(id) => handleSetPieceTaker("captain", id)}
              />
              <SetPieceSelector
                label="Penalty Taker"
                icon={<CircleDot className="w-4 h-4 text-accent-400" />}
                role="penalty"
                currentId={userSetPieces.penalty_taker}
                players={userTeam.players}
                allSquad={allSquadPlayers}
                onSelect={(id) => handleSetPieceTaker("penalty", id)}
              />
              <SetPieceSelector
                label="Free Kick Taker"
                icon={<Footprints className="w-4 h-4 text-accent-400" />}
                role="freekick"
                currentId={userSetPieces.free_kick_taker}
                players={userTeam.players}
                allSquad={allSquadPlayers}
                onSelect={(id) => handleSetPieceTaker("freekick", id)}
              />
              <SetPieceSelector
                label="Corner Taker"
                icon={<CornerDownRight className="w-4 h-4 text-accent-400" />}
                role="corner"
                currentId={userSetPieces.corner_taker}
                players={userTeam.players}
                allSquad={allSquadPlayers}
                onSelect={(id) => handleSetPieceTaker("corner", id)}
              />
            </div>
          )}
        </div>
      </div>

      {/* Footer: Start Match */}
      <footer className="bg-navy-800 border-t border-navy-700 px-6 py-4">
        <div className="max-w-5xl mx-auto flex justify-end">
          <button
            onClick={onStart}
            className="flex items-center gap-3 px-8 py-3 bg-gradient-to-r from-primary-500 to-primary-600 hover:from-primary-600 hover:to-primary-700 rounded-xl font-heading font-bold uppercase tracking-wider text-sm text-white shadow-lg shadow-primary-500/20 transition-all"
          >
            Start Match
            <ChevronRight className="w-5 h-5" />
          </button>
        </div>
      </footer>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Set Piece Selector sub-component
// ---------------------------------------------------------------------------

// Compute a role-specific suitability score and stat labels for set piece roles
function getSetPieceStats(role: string, p: PlayerData): { score: number; stats: { label: string; value: number }[] } {
  const a = p.attributes;
  switch (role) {
    case "penalty":
      return {
        score: Math.round((a.shooting * 2 + a.decisions + a.vision) / 4),
        stats: [
          { label: "SHO", value: a.shooting },
          { label: "DEC", value: a.decisions },
        ],
      };
    case "freekick":
      return {
        score: Math.round((a.shooting + a.passing + a.vision) / 3),
        stats: [
          { label: "SHO", value: a.shooting },
          { label: "PAS", value: a.passing },
          { label: "VIS", value: a.vision },
        ],
      };
    case "corner":
      return {
        score: Math.round((a.passing * 2 + a.vision) / 3),
        stats: [
          { label: "PAS", value: a.passing },
          { label: "VIS", value: a.vision },
        ],
      };
    case "captain":
      return {
        score: Math.round((a.decisions + a.vision + a.positioning) / 3),
        stats: [
          { label: "DEC", value: a.decisions },
          { label: "VIS", value: a.vision },
          { label: "POS", value: a.positioning },
        ],
      };
    default:
      return { score: 0, stats: [] };
  }
}

function SetPieceSelector({
  label,
  icon,
  role,
  currentId,
  players,
  allSquad,
  onSelect,
}: {
  label: string;
  icon: React.ReactNode;
  role: string;
  currentId: string | null;
  players: { id: string; name: string; position: string }[];
  allSquad: PlayerData[];
  onSelect: (id: string) => void;
}) {
  const [expanded, setExpanded] = useState(false);
  const currentPlayer = players.find(p => p.id === currentId);
  const currentSquad = allSquad.find(sp => sp.id === currentId);
  const currentStats = currentSquad ? getSetPieceStats(role, currentSquad) : null;

  // Sort players by set piece suitability for this role
  const sortedPlayers = [...players]
    .filter(p => p.position !== "Goalkeeper")
    .map(p => {
      const squad = allSquad.find(sp => sp.id === p.id);
      const spStats = squad ? getSetPieceStats(role, squad) : { score: 0, stats: [] };
      return { ...p, squad, spStats };
    })
    .sort((a, b) => b.spStats.score - a.spStats.score);

  return (
    <div className="mb-4 last:mb-0">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center gap-3 p-3 rounded-lg bg-navy-700/50 hover:bg-navy-700 transition-colors"
      >
        {icon}
        <div className="flex-1 text-left">
          <p className="text-xs font-heading font-bold uppercase tracking-widest text-gray-400">{label}</p>
          <p className="text-sm text-gray-200 font-medium">
            {currentPlayer ? currentPlayer.name : "Not assigned"}
          </p>
        </div>
        {currentStats && (
          <div className="flex items-center gap-1">
            {currentStats.stats.map(s => (
              <span key={s.label} className="text-[10px] font-heading text-gray-500">
                <span className="text-gray-600">{s.label}</span>{" "}
                <span className={s.value >= 70 ? "text-primary-400" : s.value >= 50 ? "text-gray-300" : "text-gray-500"}>{s.value}</span>
              </span>
            ))}
          </div>
        )}
        <ArrowUpDown className="w-4 h-4 text-gray-500" />
      </button>

      {expanded && (
        <div className="mt-1 bg-navy-700 rounded-lg p-2 flex flex-col gap-1 max-h-56 overflow-auto">
          {sortedPlayers.map(p => {
              const isCurrent = p.id === currentId;
              return (
                <button
                  key={p.id}
                  onClick={() => { onSelect(p.id); setExpanded(false); }}
                  className={`flex items-center gap-2 px-3 py-1.5 rounded text-left transition-colors ${
                    isCurrent ? "bg-primary-500/20 text-primary-400" : "hover:bg-navy-600 text-gray-300"
                  }`}
                >
                  {isCurrent && <Check className="w-3 h-3 text-primary-400" />}
                  <span className="text-sm font-medium flex-1 truncate">{p.name}</span>
                  <Badge variant="neutral" size="sm">{p.position.substring(0, 3)}</Badge>
                  {p.spStats.stats.map(s => (
                    <span key={s.label} className="text-[10px] font-heading w-7 text-center">
                      <span className={s.value >= 70 ? "text-primary-400 font-bold" : s.value >= 50 ? "text-gray-300" : "text-gray-500"}>{s.value}</span>
                    </span>
                  ))}
                  <span className={`text-xs font-heading font-bold w-6 text-right ${
                    p.spStats.score >= 70 ? "text-primary-400" : p.spStats.score >= 50 ? "text-gray-300" : "text-gray-500"
                  }`}>{p.spStats.score}</span>
                </button>
              );
            })}
          {/* Column headers */}
          {sortedPlayers.length > 0 && (
            <div className="flex items-center gap-2 px-3 py-1 text-[9px] font-heading uppercase tracking-widest text-gray-600 border-t border-navy-600 mt-1 pt-1">
              <span className="flex-1" />
              <span className="w-8" />
              {sortedPlayers[0].spStats.stats.map(s => (
                <span key={s.label} className="w-7 text-center">{s.label}</span>
              ))}
              <span className="w-6 text-right">FIT</span>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
