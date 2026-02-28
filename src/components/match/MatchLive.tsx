import { useEffect, useState, useRef, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { GameStateData } from "../../store/gameStore";
import { MatchSnapshot, MatchEvent, MinuteResult, SimSpeed, SPEED_MS } from "./types";
import { getEventDisplay, getPlayerName, phaseLabel } from "./helpers";
import { Badge } from "../ui";
import {
  Play, Pause, FastForward, SkipForward,
  Clock, Users, BarChart3, MessageSquare, RefreshCw,
  ChevronRight, AlertTriangle, Zap, Shield, Crosshair,
  Target, UserMinus, UserPlus, Flag
} from "lucide-react";

type ActivePanel = "events" | "stats" | "lineups";

interface MatchLiveProps {
  snapshot: MatchSnapshot;
  gameState: GameStateData;
  userSide: "Home" | "Away" | null;
  isSpectator: boolean;
  importantEvents: MatchEvent[];
  onSnapshotUpdate: (snap: MatchSnapshot) => void;
  onImportantEvent: (evt: MatchEvent) => void;
  onHalfTime: () => void;
  onFullTime: () => void;
}

export default function MatchLive({
  snapshot, gameState, userSide, isSpectator,
  importantEvents, onSnapshotUpdate, onImportantEvent,
  onHalfTime, onFullTime,
}: MatchLiveProps) {
  const [speed, setSpeed] = useState<SimSpeed>("normal");
  const [activePanel, setActivePanel] = useState<ActivePanel>("events");
  const [isRunning, setIsRunning] = useState(true);
  const [showSubPanel, setShowSubPanel] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const eventFeedRef = useRef<HTMLDivElement>(null);
  // Track phases we've already signaled to avoid double-firing
  const signaledRef = useRef<Set<string>>(new Set());

  const homeTeamColor = gameState.teams.find(t => t.id === snapshot.home_team.id)?.colors?.primary || "#10b981";
  const awayTeamColor = gameState.teams.find(t => t.id === snapshot.away_team.id)?.colors?.primary || "#6366f1";

  const isFinished = snapshot.phase === "Finished";

  // Step the match forward one minute
  const stepMatch = useCallback(async () => {
    try {
      const results = await invoke<MinuteResult[]>("step_live_match", { minutes: 1 });
      if (results.length > 0) {
        const lastResult = results[results.length - 1];

        // Collect important events
        for (const r of results) {
          for (const evt of r.events) {
            const display = getEventDisplay(evt);
            if (display.important) {
              onImportantEvent(evt);
            }
          }
        }

        // Fetch full snapshot
        const snap = await invoke<MatchSnapshot>("get_match_snapshot");
        onSnapshotUpdate(snap);

        // Check for phase transitions that should pause
        const phase = lastResult.phase;
        if (phase === "HalfTime" && !signaledRef.current.has("HalfTime")) {
          signaledRef.current.add("HalfTime");
          setIsRunning(false);
          setSpeed("paused");
          // Small delay so the last event renders before transitioning
          setTimeout(() => onHalfTime(), 600);
          return;
        }

        if (phase === "ExtraTimeHalfTime" && !signaledRef.current.has("ExtraTimeHalfTime")) {
          signaledRef.current.add("ExtraTimeHalfTime");
          setIsRunning(false);
          setSpeed("paused");
          setTimeout(() => onHalfTime(), 600);
          return;
        }

        if (lastResult.is_finished && !signaledRef.current.has("Finished")) {
          signaledRef.current.add("Finished");
          setIsRunning(false);
          setSpeed("paused");
          setTimeout(() => onFullTime(), 600);
          return;
        }
      }
    } catch (err) {
      console.error("Failed to step match:", err);
      setIsRunning(false);
    }
  }, [onSnapshotUpdate, onImportantEvent, onHalfTime, onFullTime]);

  // Auto-step timer
  useEffect(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }

    if (isRunning && speed !== "paused" && !isFinished) {
      timerRef.current = setTimeout(async () => {
        await stepMatch();
      }, SPEED_MS[speed]);
    }

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [isRunning, speed, snapshot.current_minute, snapshot.phase, stepMatch, isFinished]);

  // Auto-scroll event feed
  useEffect(() => {
    if (eventFeedRef.current) {
      eventFeedRef.current.scrollTop = eventFeedRef.current.scrollHeight;
    }
  }, [importantEvents.length]);

  // Apply substitution
  const handleSubstitution = async (playerOffId: string, playerOnId: string) => {
    if (!userSide || isSpectator) return;
    try {
      const snap = await invoke<MatchSnapshot>("apply_match_command", {
        command: { Substitute: { side: userSide, player_off_id: playerOffId, player_on_id: playerOnId } }
      });
      onSnapshotUpdate(snap);
      setShowSubPanel(false);
    } catch (err) {
      console.error("Substitution failed:", err);
    }
  };

  const handleFormationChange = async (formation: string) => {
    if (!userSide || isSpectator) return;
    try {
      const snap = await invoke<MatchSnapshot>("apply_match_command", {
        command: { ChangeFormation: { side: userSide, formation } }
      });
      onSnapshotUpdate(snap);
    } catch (err) {
      console.error("Formation change failed:", err);
    }
  };

  const handlePlayStyleChange = async (playStyle: string) => {
    if (!userSide || isSpectator) return;
    try {
      const snap = await invoke<MatchSnapshot>("apply_match_command", {
        command: { ChangePlayStyle: { side: userSide, play_style: playStyle } }
      });
      onSnapshotUpdate(snap);
    } catch (err) {
      console.error("Play style change failed:", err);
    }
  };

  return (
    <div className="min-h-screen bg-navy-900 text-white flex flex-col">
      {/* Top Scoreboard Bar */}
      <header className="bg-gradient-to-r from-navy-800 via-navy-900 to-navy-800 border-b border-navy-700 px-4 py-3">
        <div className="max-w-7xl mx-auto flex items-center justify-between">
          {/* Live indicator */}
          <div className="flex items-center gap-2">
            {isRunning && (
              <span className="relative flex h-2.5 w-2.5">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75" />
                <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-red-500" />
              </span>
            )}
            <span className="text-xs font-heading uppercase tracking-widest text-gray-500">
              {isRunning ? "Live" : "Paused"}
            </span>
          </div>

          {/* Scoreboard */}
          <div className="flex items-center gap-6">
            <div className="flex items-center gap-3">
              <div className="text-right">
                <p className="font-heading font-bold text-sm uppercase tracking-wider text-gray-200">
                  {snapshot.home_team.name}
                </p>
                <p className="text-xs text-gray-500">{snapshot.home_team.formation}</p>
              </div>
              <div
                className="w-10 h-10 rounded-lg flex items-center justify-center font-heading font-bold text-sm"
                style={{ backgroundColor: homeTeamColor + "30", borderColor: homeTeamColor, borderWidth: 2 }}
              >
                {snapshot.home_team.name.substring(0, 3).toUpperCase()}
              </div>
            </div>

            <div className="flex items-center gap-3">
              <span className="text-4xl font-heading font-bold text-white tabular-nums">{snapshot.home_score}</span>
              <div className="flex flex-col items-center">
                <span className="text-xs font-heading uppercase tracking-widest text-accent-400">
                  {phaseLabel(snapshot.phase)}
                </span>
                <span className="text-2xl font-heading font-bold text-gray-500">{snapshot.current_minute}'</span>
              </div>
              <span className="text-4xl font-heading font-bold text-white tabular-nums">{snapshot.away_score}</span>
            </div>

            <div className="flex items-center gap-3">
              <div
                className="w-10 h-10 rounded-lg flex items-center justify-center font-heading font-bold text-sm"
                style={{ backgroundColor: awayTeamColor + "30", borderColor: awayTeamColor, borderWidth: 2 }}
              >
                {snapshot.away_team.name.substring(0, 3).toUpperCase()}
              </div>
              <div className="text-left">
                <p className="font-heading font-bold text-sm uppercase tracking-wider text-gray-200">
                  {snapshot.away_team.name}
                </p>
                <p className="text-xs text-gray-500">{snapshot.away_team.formation}</p>
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <Clock className="w-4 h-4 text-gray-500" />
            <span className="text-sm font-heading text-gray-400 tabular-nums w-8">{snapshot.current_minute}'</span>
          </div>
        </div>

        {/* Possession bar */}
        <div className="max-w-7xl mx-auto mt-2">
          <div className="flex items-center gap-2 text-xs">
            <span className="font-heading font-bold text-primary-400 w-12 text-right">
              {snapshot.home_possession_pct.toFixed(0)}%
            </span>
            <div className="flex-1 h-1.5 bg-navy-700 rounded-full overflow-hidden flex">
              <div className="h-full bg-primary-500 transition-all duration-500" style={{ width: `${snapshot.home_possession_pct}%` }} />
              <div className="h-full bg-indigo-500 transition-all duration-500" style={{ width: `${snapshot.away_possession_pct}%` }} />
            </div>
            <span className="font-heading font-bold text-indigo-400 w-12">
              {snapshot.away_possession_pct.toFixed(0)}%
            </span>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <div className="flex-1 flex overflow-hidden">
        {/* Left Panel: Event Feed + Stats */}
        <div className="flex-1 flex flex-col">
          <div className="flex bg-navy-800 border-b border-navy-700">
            {([
              { id: "events" as ActivePanel, label: "Events", icon: <MessageSquare className="w-4 h-4" /> },
              { id: "stats" as ActivePanel, label: "Stats", icon: <BarChart3 className="w-4 h-4" /> },
              { id: "lineups" as ActivePanel, label: "Lineups", icon: <Users className="w-4 h-4" /> },
            ]).map(tab => (
              <button
                key={tab.id}
                onClick={() => setActivePanel(tab.id)}
                className={`flex items-center gap-2 px-5 py-3 font-heading font-bold text-xs uppercase tracking-wider transition-colors border-b-2 ${
                  activePanel === tab.id
                    ? "text-primary-400 border-primary-500 bg-navy-700/50"
                    : "text-gray-500 border-transparent hover:text-gray-300"
                }`}
              >
                {tab.icon}
                {tab.label}
              </button>
            ))}
          </div>

          <div className="flex-1 overflow-auto p-4">
            {activePanel === "events" && <EventFeed events={importantEvents} snapshot={snapshot} feedRef={eventFeedRef} />}
            {activePanel === "stats" && <MatchStats snapshot={snapshot} />}
            {activePanel === "lineups" && <Lineups snapshot={snapshot} />}
          </div>
        </div>

        {/* Right Panel: Controls */}
        <aside className="w-72 bg-navy-800 border-l border-navy-700 flex flex-col">
          {/* Speed Controls */}
          <div className="p-4 border-b border-navy-700">
            <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 mb-3">Simulation Speed</h3>
            <div className="flex gap-1">
              {([
                { id: "paused" as SimSpeed, icon: <Pause className="w-4 h-4" />, label: "Pause" },
                { id: "slow" as SimSpeed, icon: <Play className="w-4 h-4" />, label: "Slow" },
                { id: "normal" as SimSpeed, icon: <Play className="w-4 h-4" />, label: "Normal" },
                { id: "fast" as SimSpeed, icon: <FastForward className="w-4 h-4" />, label: "Fast" },
                { id: "instant" as SimSpeed, icon: <SkipForward className="w-4 h-4" />, label: "Max" },
              ]).map(s => (
                <button
                  key={s.id}
                  onClick={() => { setSpeed(s.id); setIsRunning(s.id !== "paused"); }}
                  className={`flex-1 flex flex-col items-center gap-1 py-2 rounded-lg text-xs font-heading uppercase tracking-wider transition-all ${
                    speed === s.id ? "bg-primary-500/20 text-primary-400 ring-1 ring-primary-500/50" : "text-gray-500 hover:text-gray-300 hover:bg-navy-700"
                  }`}
                >
                  {s.icon}
                  <span className="text-[10px]">{s.label}</span>
                </button>
              ))}
            </div>
            {speed === "paused" && (
              <button
                onClick={stepMatch}
                className="w-full mt-2 flex items-center justify-center gap-2 py-2 bg-navy-700 hover:bg-navy-600 rounded-lg text-sm font-heading uppercase tracking-wider text-gray-300 transition-colors"
              >
                <ChevronRight className="w-4 h-4" />
                Step 1 Minute
              </button>
            )}
          </div>

          {/* User Controls */}
          {!isSpectator && userSide && (
            <div className="p-4 border-b border-navy-700 flex flex-col gap-2">
              <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 mb-1">Team Controls</h3>
              <button
                onClick={() => setShowSubPanel(!showSubPanel)}
                className="flex items-center gap-2 px-3 py-2 bg-navy-700 hover:bg-navy-600 rounded-lg text-sm font-heading uppercase tracking-wider text-gray-300 transition-colors"
              >
                <RefreshCw className="w-4 h-4" />
                Subs ({userSide === "Home" ? snapshot.home_subs_made : snapshot.away_subs_made}/{snapshot.max_subs})
              </button>
              <div>
                <p className="text-[10px] font-heading uppercase tracking-widest text-gray-600 mb-1">Formation</p>
                <div className="flex flex-wrap gap-1">
                  {["4-4-2", "4-3-3", "3-5-2", "4-5-1", "4-2-3-1", "3-4-3"].map(f => {
                    const cur = userSide === "Home" ? snapshot.home_team.formation : snapshot.away_team.formation;
                    return (
                      <button key={f} onClick={() => handleFormationChange(f)}
                        className={`px-2 py-1 rounded text-xs font-heading transition-colors ${cur === f ? "bg-primary-500/20 text-primary-400 ring-1 ring-primary-500/50" : "bg-navy-700 text-gray-500 hover:text-gray-300"}`}
                      >{f}</button>
                    );
                  })}
                </div>
              </div>
              <div>
                <p className="text-[10px] font-heading uppercase tracking-widest text-gray-600 mb-1">Play Style</p>
                <div className="flex flex-wrap gap-1">
                  {[
                    { id: "Balanced", icon: <Target className="w-3 h-3" /> },
                    { id: "Attacking", icon: <Zap className="w-3 h-3" /> },
                    { id: "Defensive", icon: <Shield className="w-3 h-3" /> },
                    { id: "Possession", icon: <RefreshCw className="w-3 h-3" /> },
                    { id: "Counter", icon: <Crosshair className="w-3 h-3" /> },
                    { id: "HighPress", icon: <Flag className="w-3 h-3" /> },
                  ].map(s => {
                    const cur = userSide === "Home" ? snapshot.home_team.play_style : snapshot.away_team.play_style;
                    return (
                      <button key={s.id} onClick={() => handlePlayStyleChange(s.id)}
                        className={`flex items-center gap-1 px-2 py-1 rounded text-xs font-heading transition-colors ${cur === s.id ? "bg-primary-500/20 text-primary-400 ring-1 ring-primary-500/50" : "bg-navy-700 text-gray-500 hover:text-gray-300"}`}
                      >{s.icon}{s.id}</button>
                    );
                  })}
                </div>
              </div>
            </div>
          )}

          {/* Sub Panel */}
          {showSubPanel && userSide && (
            <SubPanel snapshot={snapshot} side={userSide} gameState={gameState} onSubstitute={handleSubstitution} onClose={() => setShowSubPanel(false)} />
          )}

          {/* Key Events sidebar */}
          <div className="p-4 flex-1 overflow-auto">
            <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 mb-3">Key Events</h3>
            <div className="flex flex-col gap-1.5">
              {importantEvents
                .filter(e => ["Goal", "PenaltyGoal", "YellowCard", "RedCard", "SecondYellow", "Substitution", "PenaltyMiss", "Injury"].includes(e.event_type))
                .slice(-12).reverse()
                .map((evt, i) => {
                  const display = getEventDisplay(evt);
                  return (
                    <div key={i} className="flex items-center gap-2 text-xs">
                      <span className="text-gray-600 tabular-nums w-6 text-right font-heading">{evt.minute}'</span>
                      <span>{display.icon}</span>
                      <span className={`${display.color} font-medium truncate`}>{getPlayerName(snapshot, evt.player_id)}</span>
                      <Badge variant={evt.side === "Home" ? "primary" : "accent"} size="sm">
                        {evt.side === "Home" ? snapshot.home_team.name.substring(0, 3) : snapshot.away_team.name.substring(0, 3)}
                      </Badge>
                    </div>
                  );
                })}
              {importantEvents.length === 0 && <p className="text-gray-600 text-xs">Match hasn't started yet.</p>}
            </div>
          </div>
        </aside>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Sub-components (same as before, inlined)
// ---------------------------------------------------------------------------

function EventFeed({ events, snapshot, feedRef }: { events: MatchEvent[]; snapshot: MatchSnapshot; feedRef: React.RefObject<HTMLDivElement | null> }) {
  return (
    <div ref={feedRef} className="flex flex-col gap-1">
      {events.length === 0 ? (
        <div className="flex items-center justify-center h-40 text-gray-600">
          <p className="font-heading text-sm uppercase tracking-wider">Waiting for kick-off...</p>
        </div>
      ) : events.map((evt, i) => {
        const display = getEventDisplay(evt);
        const isHome = evt.side === "Home";
        return (
          <div key={i} className={`flex items-start gap-3 px-3 py-2 rounded-lg transition-colors ${display.important ? "bg-navy-800/80" : "opacity-60"}`}>
            <span className="text-gray-600 tabular-nums font-heading text-sm w-8 text-right flex-shrink-0 pt-0.5">{evt.minute}'</span>
            <span className="text-lg flex-shrink-0">{display.icon}</span>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className={`font-heading font-bold text-xs uppercase tracking-wider ${isHome ? "text-primary-400" : "text-indigo-400"}`}>
                  {isHome ? snapshot.home_team.name : snapshot.away_team.name}
                </span>
                <span className="text-xs text-gray-500">{evt.event_type.replace(/([A-Z])/g, ' $1').trim()}</span>
              </div>
              {evt.player_id && (
                <p className="text-sm text-gray-300 font-medium">
                  {getPlayerName(snapshot, evt.player_id)}
                  {evt.secondary_player_id && (
                    <span className="text-gray-500 font-normal">
                      {evt.event_type === "Goal" ? ` (assist: ${getPlayerName(snapshot, evt.secondary_player_id)})` :
                       evt.event_type === "Substitution" ? ` for ${getPlayerName(snapshot, evt.secondary_player_id)}` : ""}
                    </span>
                  )}
                </p>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function MatchStats({ snapshot }: { snapshot: MatchSnapshot }) {
  const homeEvents = snapshot.events.filter(e => e.side === "Home");
  const awayEvents = snapshot.events.filter(e => e.side === "Away");
  const ct = (events: MatchEvent[], type: string) => events.filter(e => e.event_type === type).length;

  const stats = [
    { label: "Possession", home: `${snapshot.home_possession_pct.toFixed(0)}%`, away: `${snapshot.away_possession_pct.toFixed(0)}%`, homePct: snapshot.home_possession_pct },
    { label: "Shots", home: ct(homeEvents, "Goal") + ct(homeEvents, "PenaltyGoal") + ct(homeEvents, "ShotSaved") + ct(homeEvents, "ShotOffTarget") + ct(homeEvents, "ShotBlocked"), away: ct(awayEvents, "Goal") + ct(awayEvents, "PenaltyGoal") + ct(awayEvents, "ShotSaved") + ct(awayEvents, "ShotOffTarget") + ct(awayEvents, "ShotBlocked") },
    { label: "Shots on Target", home: ct(homeEvents, "Goal") + ct(homeEvents, "PenaltyGoal") + ct(homeEvents, "ShotSaved"), away: ct(awayEvents, "Goal") + ct(awayEvents, "PenaltyGoal") + ct(awayEvents, "ShotSaved") },
    { label: "Fouls", home: ct(homeEvents, "Foul"), away: ct(awayEvents, "Foul") },
    { label: "Corners", home: ct(homeEvents, "Corner"), away: ct(awayEvents, "Corner") },
    { label: "Yellow Cards", home: Object.keys(snapshot.home_yellows).length, away: Object.keys(snapshot.away_yellows).length },
  ];

  return (
    <div className="max-w-lg mx-auto flex flex-col gap-3">
      {stats.map((stat, i) => {
        const hv = typeof stat.home === "number" ? stat.home : 0;
        const av = typeof stat.away === "number" ? stat.away : 0;
        const total = hv + av || 1;
        const pct = stat.homePct ?? (hv / total * 100);
        return (
          <div key={i}>
            <div className="flex justify-between text-xs mb-1">
              <span className="font-heading font-bold text-primary-400 tabular-nums">{stat.home}</span>
              <span className="text-gray-500 font-heading uppercase tracking-wider text-[10px]">{stat.label}</span>
              <span className="font-heading font-bold text-indigo-400 tabular-nums">{stat.away}</span>
            </div>
            <div className="flex h-1.5 bg-navy-700 rounded-full overflow-hidden">
              <div className="h-full bg-primary-500 transition-all duration-500" style={{ width: `${pct}%` }} />
              <div className="h-full bg-indigo-500 transition-all duration-500" style={{ width: `${100 - pct}%` }} />
            </div>
          </div>
        );
      })}
    </div>
  );
}

function Lineups({ snapshot }: { snapshot: MatchSnapshot }) {
  const renderTeam = (team: MatchSnapshot["home_team"], side: "Home" | "Away", yellows: Record<string, number>, sentOff: string[]) => {
    const positions = ["Goalkeeper", "Defender", "Midfielder", "Forward"];
    return (
      <div className="flex-1">
        <h4 className={`font-heading font-bold text-sm uppercase tracking-wider mb-3 ${side === "Home" ? "text-primary-400" : "text-indigo-400"}`}>
          {team.name}
        </h4>
        {positions.map(pos => {
          const players = team.players.filter(p => p.position === pos);
          if (players.length === 0) return null;
          return (
            <div key={pos} className="mb-3">
              <p className="text-[10px] font-heading uppercase tracking-widest text-gray-600 mb-1">{pos}s</p>
              {players.map(p => {
                const isOff = sentOff.includes(p.id);
                const yc = yellows[p.id] || 0;
                return (
                  <div key={p.id} className={`flex items-center gap-2 py-1 px-2 rounded text-xs ${isOff ? "opacity-40 line-through" : ""}`}>
                    <span className="text-gray-300 font-medium flex-1 truncate">{p.name}</span>
                    {yc > 0 && <span className="text-yellow-400">🟨{yc > 1 ? `×${yc}` : ""}</span>}
                    {isOff && <span className="text-red-400">🟥</span>}
                    <span className="text-gray-600 tabular-nums w-8 text-right">{Math.round(p.condition)}</span>
                  </div>
                );
              })}
            </div>
          );
        })}
      </div>
    );
  };
  return (
    <div className="flex gap-6">
      {renderTeam(snapshot.home_team, "Home", snapshot.home_yellows, snapshot.sent_off)}
      <div className="w-px bg-navy-700" />
      {renderTeam(snapshot.away_team, "Away", snapshot.away_yellows, snapshot.sent_off)}
    </div>
  );
}

function SubPanel({ snapshot, side, gameState, onSubstitute, onClose }: {
  snapshot: MatchSnapshot; side: "Home" | "Away"; gameState: GameStateData;
  onSubstitute: (offId: string, onId: string) => void; onClose: () => void;
}) {
  const [selectedOff, setSelectedOff] = useState<string | null>(null);
  const team = side === "Home" ? snapshot.home_team : snapshot.away_team;
  const subsMade = side === "Home" ? snapshot.home_subs_made : snapshot.away_subs_made;
  const onPitchIds = new Set(team.players.map(p => p.id));
  const benchPlayers = gameState.players.filter(p => p.team_id === team.id && !onPitchIds.has(p.id) && !p.injury);

  if (subsMade >= snapshot.max_subs) {
    return (
      <div className="p-4 border-b border-navy-700">
        <div className="flex items-center gap-2 text-yellow-500 text-xs">
          <AlertTriangle className="w-4 h-4" />
          <span className="font-heading uppercase tracking-wider">All substitutions used</span>
        </div>
      </div>
    );
  }

  return (
    <div className="p-4 border-b border-navy-700 max-h-80 overflow-auto">
      <div className="flex items-center justify-between mb-3">
        <h4 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500">
          {selectedOff ? "Select Replacement" : "Select Player to Sub Off"}
        </h4>
        <button onClick={onClose} className="text-xs text-gray-500 hover:text-gray-300">✕</button>
      </div>
      {!selectedOff ? (
        <div className="flex flex-col gap-1">
          {team.players.filter(p => p.position !== "Goalkeeper" && !snapshot.sent_off.includes(p.id)).map(p => (
            <button key={p.id} onClick={() => setSelectedOff(p.id)}
              className="flex items-center gap-2 px-2 py-1.5 rounded bg-navy-700 hover:bg-navy-600 transition-colors text-left">
              <UserMinus className="w-3 h-3 text-red-400" />
              <span className="text-xs text-gray-300 font-medium flex-1 truncate">{p.name}</span>
              <Badge variant="neutral" size="sm">{p.position.substring(0, 3)}</Badge>
              <span className="text-[10px] text-gray-500">{Math.round(p.condition)}%</span>
            </button>
          ))}
        </div>
      ) : (
        <div className="flex flex-col gap-1">
          <button onClick={() => setSelectedOff(null)} className="text-xs text-primary-400 hover:text-primary-300 mb-2">← Back</button>
          {benchPlayers.length === 0 ? <p className="text-xs text-gray-500">No bench players available.</p> : (
            benchPlayers.map(p => (
              <button key={p.id} onClick={() => onSubstitute(selectedOff, p.id)}
                className="flex items-center gap-2 px-2 py-1.5 rounded bg-navy-700 hover:bg-navy-600 transition-colors text-left">
                <UserPlus className="w-3 h-3 text-green-400" />
                <span className="text-xs text-gray-300 font-medium flex-1 truncate">{p.match_name}</span>
                <Badge variant="neutral" size="sm">{p.position.substring(0, 3)}</Badge>
                <span className="text-[10px] text-gray-500">{p.condition}%</span>
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
}
