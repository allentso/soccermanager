import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { GameStateData, PlayerData } from "../../store/gameStore";
import { MatchSnapshot, FORMATIONS, PLAY_STYLES } from "./types";
import { Badge } from "../ui";
import {
  ChevronRight, Shield, Zap, Target, RefreshCw, Crosshair, Flag,
  Crown, Footprints, CornerDownRight, CircleDot, ArrowUpDown, Check
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

export default function PreMatchSetup({ snapshot, gameState, userSide, onStart, onUpdateSnapshot }: PreMatchSetupProps) {
  const [activeTab, setActiveTab] = useState<"lineup" | "setpieces">("lineup");

  const userTeam = userSide === "Home" ? snapshot.home_team : snapshot.away_team;
  const oppTeam = userSide === "Home" ? snapshot.away_team : snapshot.home_team;
  const userSetPieces = userSide === "Home" ? snapshot.home_set_pieces : snapshot.away_set_pieces;

  const homeTeamColor = gameState.teams.find(t => t.id === snapshot.home_team.id)?.colors?.primary || "#10b981";
  const awayTeamColor = gameState.teams.find(t => t.id === snapshot.away_team.id)?.colors?.primary || "#6366f1";
  const userColor = userSide === "Home" ? homeTeamColor : awayTeamColor;

  // All squad players for this team
  const allSquadPlayers = gameState.players.filter(p => p.team_id === userTeam.id);
  const startingIds = new Set(userTeam.players.map(p => p.id));
  const benchPlayers = allSquadPlayers.filter(p => !startingIds.has(p.id) && !p.injury);

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

  const getPlayerOvr = (p: PlayerData) => {
    const a = p.attributes;
    return Math.round(
      (a.pace + a.stamina + a.strength + a.passing + a.shooting +
        a.tackling + a.dribbling + a.defending + a.positioning + a.vision + a.decisions) / 11
    );
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
            <div className="grid grid-cols-2 gap-4">
              {/* Starting XI */}
              <div className="bg-navy-800 rounded-xl border border-navy-700 p-4">
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500">
                    Starting XI
                  </h3>
                  <Badge variant="primary" size="sm">{userTeam.players.length} players</Badge>
                </div>
                {positions.map(pos => {
                  const players = userTeam.players.filter(p => p.position === pos);
                  if (players.length === 0) return null;
                  return (
                    <div key={pos} className="mb-3">
                      <p className="text-[10px] font-heading uppercase tracking-widest text-gray-600 mb-1">{pos}s</p>
                      {players.map(p => {
                        const squad = allSquadPlayers.find(sp => sp.id === p.id);
                        const ovr = squad ? getPlayerOvr(squad) : 0;
                        return (
                          <div key={p.id} className="flex items-center gap-2 py-1.5 px-2 rounded hover:bg-navy-700/50">
                            <div
                              className="w-6 h-6 rounded-full flex items-center justify-center text-[10px] font-heading font-bold flex-shrink-0"
                              style={{ backgroundColor: userColor + "30", color: userColor }}
                            >
                              {ovr}
                            </div>
                            <span className="text-sm text-gray-200 font-medium flex-1 truncate">{p.name}</span>
                            <Badge variant="neutral" size="sm">{pos.substring(0, 3)}</Badge>
                            <span className="text-xs text-gray-500 tabular-nums">{Math.round(p.condition)}%</span>
                          </div>
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
                  <Badge variant="neutral" size="sm">{benchPlayers.length} available</Badge>
                </div>
                {benchPlayers.length === 0 ? (
                  <p className="text-xs text-gray-600">No bench players available.</p>
                ) : (
                  <div className="flex flex-col gap-1">
                    {benchPlayers.map(p => {
                      const ovr = getPlayerOvr(p);
                      return (
                        <div key={p.id} className="flex items-center gap-2 py-1.5 px-2 rounded hover:bg-navy-700/50">
                          <div className="w-6 h-6 rounded-full bg-navy-600 flex items-center justify-center text-[10px] font-heading font-bold text-gray-400 flex-shrink-0">
                            {ovr}
                          </div>
                          <span className="text-sm text-gray-300 font-medium flex-1 truncate">{p.match_name}</span>
                          <Badge variant="neutral" size="sm">{p.position.substring(0, 3)}</Badge>
                          <span className="text-xs text-gray-500 tabular-nums">{p.condition}%</span>
                        </div>
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
          )}

          {/* Set Pieces Tab */}
          {activeTab === "setpieces" && (
            <div className="bg-navy-800 rounded-xl border border-navy-700 p-4">
              <SetPieceSelector
                label="Captain"
                icon={<Crown className="w-4 h-4 text-accent-400" />}
                currentId={userSetPieces.captain}
                players={userTeam.players}
                allSquad={allSquadPlayers}
                onSelect={(id) => handleSetPieceTaker("captain", id)}
                getOvr={getPlayerOvr}
              />
              <SetPieceSelector
                label="Penalty Taker"
                icon={<CircleDot className="w-4 h-4 text-accent-400" />}
                currentId={userSetPieces.penalty_taker}
                players={userTeam.players}
                allSquad={allSquadPlayers}
                onSelect={(id) => handleSetPieceTaker("penalty", id)}
                getOvr={getPlayerOvr}
              />
              <SetPieceSelector
                label="Free Kick Taker"
                icon={<Footprints className="w-4 h-4 text-accent-400" />}
                currentId={userSetPieces.free_kick_taker}
                players={userTeam.players}
                allSquad={allSquadPlayers}
                onSelect={(id) => handleSetPieceTaker("freekick", id)}
                getOvr={getPlayerOvr}
              />
              <SetPieceSelector
                label="Corner Taker"
                icon={<CornerDownRight className="w-4 h-4 text-accent-400" />}
                currentId={userSetPieces.corner_taker}
                players={userTeam.players}
                allSquad={allSquadPlayers}
                onSelect={(id) => handleSetPieceTaker("corner", id)}
                getOvr={getPlayerOvr}
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

function SetPieceSelector({
  label,
  icon,
  currentId,
  players,
  allSquad,
  onSelect,
  getOvr,
}: {
  label: string;
  icon: React.ReactNode;
  currentId: string | null;
  players: { id: string; name: string; position: string }[];
  allSquad: PlayerData[];
  onSelect: (id: string) => void;
  getOvr: (p: PlayerData) => number;
}) {
  const [expanded, setExpanded] = useState(false);
  const currentPlayer = players.find(p => p.id === currentId);

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
        <ArrowUpDown className="w-4 h-4 text-gray-500" />
      </button>

      {expanded && (
        <div className="mt-1 bg-navy-700 rounded-lg p-2 flex flex-col gap-1 max-h-48 overflow-auto">
          {players
            .filter(p => p.position !== "Goalkeeper")
            .map(p => {
              const squad = allSquad.find(sp => sp.id === p.id);
              const ovr = squad ? getOvr(squad) : 0;
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
                  <span className="text-xs text-gray-500">{ovr}</span>
                </button>
              );
            })}
        </div>
      )}
    </div>
  );
}
