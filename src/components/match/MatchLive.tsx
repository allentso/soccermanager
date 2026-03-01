import { useEffect, useState, useRef, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { GameStateData } from "../../store/gameStore";
import { MatchSnapshot, MatchEvent, MinuteResult, SimSpeed, SPEED_MS, EnginePlayerData } from "./types";
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

      {/* Substitution Modal */}
      {showSubPanel && userSide && (
        <SubPanel snapshot={snapshot} side={userSide} onSubstitute={handleSubstitution} onClose={() => setShowSubPanel(false)} />
      )}
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
  const renderTeam = (team: MatchSnapshot["home_team"], bench: EnginePlayerData[], side: "Home" | "Away", yellows: Record<string, number>, sentOff: string[]) => {
    const positions = ["Goalkeeper", "Defender", "Midfielder", "Forward"];
    const subbedOnIds = new Set(snapshot.substitutions.filter(s => s.side === side).map(s => s.player_on_id));
    const subbedOffIds = new Set(snapshot.substitutions.filter(s => s.side === side).map(s => s.player_off_id));
    return (
      <div className="flex-1">
        <h4 className={`font-heading font-bold text-sm uppercase tracking-wider mb-3 ${side === "Home" ? "text-primary-400" : "text-indigo-400"}`}>
          {team.name} <span className="text-gray-600 font-normal text-xs">({team.formation})</span>
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
                const isSubOn = subbedOnIds.has(p.id);
                const condColor = p.condition >= 70 ? "bg-primary-500" : p.condition >= 40 ? "bg-yellow-500" : "bg-red-500";
                return (
                  <div key={p.id} className={`flex items-center gap-2 py-1 px-2 rounded text-xs ${isOff ? "opacity-40" : ""}`}>
                    {isSubOn && <span className="text-green-400 text-[10px]">▲</span>}
                    <span className={`font-medium flex-1 truncate ${isOff ? "line-through text-gray-600" : "text-gray-300"}`}>{p.name}</span>
                    {yc > 0 && <span className="w-3 h-4 rounded-sm bg-yellow-400 text-navy-900 text-[8px] flex items-center justify-center font-bold">{yc > 1 ? yc : ""}</span>}
                    {isOff && <span className="w-3 h-4 rounded-sm bg-red-500" />}
                    <div className="w-14 flex items-center gap-1">
                      <div className="flex-1 h-1.5 bg-navy-600 rounded-full overflow-hidden">
                        <div className={`h-full ${condColor} rounded-full transition-all`} style={{ width: `${p.condition}%` }} />
                      </div>
                      <span className="text-gray-500 tabular-nums text-[10px] w-6 text-right">{Math.round(p.condition)}</span>
                    </div>
                  </div>
                );
              })}
            </div>
          );
        })}

        {/* Bench */}
        {bench.length > 0 && (
          <div className="mt-3 pt-3 border-t border-navy-700">
            <p className="text-[10px] font-heading uppercase tracking-widest text-gray-600 mb-1">Bench</p>
            {bench.map(p => {
              const wasSubbedOff = subbedOffIds.has(p.id);
              return (
                <div key={p.id} className={`flex items-center gap-2 py-1 px-2 rounded text-xs ${wasSubbedOff ? "opacity-50" : ""}`}>
                  {wasSubbedOff && <span className="text-red-400 text-[10px]">▼</span>}
                  <span className="text-gray-400 font-medium flex-1 truncate">{p.name}</span>
                  <Badge variant="neutral" size="sm">{p.position.substring(0, 3)}</Badge>
                  <span className="text-gray-600 tabular-nums text-[10px] w-6 text-right">{Math.round(p.condition)}</span>
                </div>
              );
            })}
          </div>
        )}

        {/* Sub History */}
        {snapshot.substitutions.filter(s => s.side === side).length > 0 && (
          <div className="mt-3 pt-3 border-t border-navy-700">
            <p className="text-[10px] font-heading uppercase tracking-widest text-gray-600 mb-1">Substitutions</p>
            {snapshot.substitutions.filter(s => s.side === side).map((sub, i) => (
              <div key={i} className="flex items-center gap-1.5 py-0.5 text-[11px]">
                <span className="text-gray-600 tabular-nums w-5 text-right font-heading">{sub.minute}'</span>
                <span className="text-green-400">▲</span>
                <span className="text-gray-300 truncate">{getPlayerName(snapshot, sub.player_on_id)}</span>
                <span className="text-red-400">▼</span>
                <span className="text-gray-500 truncate">{getPlayerName(snapshot, sub.player_off_id)}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    );
  };
  return (
    <div className="flex gap-6">
      {renderTeam(snapshot.home_team, snapshot.home_bench, "Home", snapshot.home_yellows, snapshot.sent_off)}
      <div className="w-px bg-navy-700" />
      {renderTeam(snapshot.away_team, snapshot.away_bench, "Away", snapshot.away_yellows, snapshot.sent_off)}
    </div>
  );
}

export function SubPanel({ snapshot, side, onSubstitute, onClose }: {
  snapshot: MatchSnapshot; side: "Home" | "Away";
  onSubstitute: (offId: string, onId: string) => void; onClose: () => void;
}) {
  const [selectedOff, setSelectedOff] = useState<string | null>(null);
  const [hoveredBench, setHoveredBench] = useState<string | null>(null);
  const team = side === "Home" ? snapshot.home_team : snapshot.away_team;
  const bench = side === "Home" ? snapshot.home_bench : snapshot.away_bench;
  const subsMade = side === "Home" ? snapshot.home_subs_made : snapshot.away_subs_made;
  const subbedOnIds = new Set(snapshot.substitutions.filter(s => s.side === side).map(s => s.player_on_id));
  const subbedOffIds = new Set(snapshot.substitutions.filter(s => s.side === side).map(s => s.player_off_id));
  const availableBench = bench.filter(p => !subbedOffIds.has(p.id));
  const selectedPlayer = selectedOff ? team.players.find(p => p.id === selectedOff) : null;
  const comparedPlayer = hoveredBench ? availableBench.find(p => p.id === hoveredBench) : null;

  const positions = ["Goalkeeper", "Defender", "Midfielder", "Forward"];
  const posAbbr: Record<string, string> = { Goalkeeper: "GK", Defender: "DEF", Midfielder: "MID", Forward: "FWD" };

  // Parse formation to get expected counts per position
  const parts = team.formation.split('-').map(Number);
  const expectedCounts: Record<string, number> = { Goalkeeper: 1, Defender: 0, Midfielder: 0, Forward: 0 };
  if (parts.length === 3) { expectedCounts.Defender = parts[0]; expectedCounts.Midfielder = parts[1]; expectedCounts.Forward = parts[2]; }
  else if (parts.length === 4) { expectedCounts.Defender = parts[0]; expectedCounts.Midfielder = parts[1] + parts[2]; expectedCounts.Forward = parts[3]; }

  const getOvr = (p: EnginePlayerData) => {
    const vals = [p.pace, p.stamina, p.strength, p.passing, p.shooting, p.tackling, p.dribbling, p.defending, p.positioning, p.vision, p.decisions];
    return Math.round(vals.reduce((a, b) => a + b, 0) / vals.length);
  };

  const condColor = (c: number) => c >= 70 ? "bg-primary-500" : c >= 40 ? "bg-yellow-500" : "bg-red-500";
  const condText = (c: number) => c >= 70 ? "text-primary-400" : c >= 40 ? "text-yellow-400" : "text-red-400";

  // Comparison bar component
  const CompareBar = ({ label, valA, valB }: { label: string; valA: number; valB: number }) => {
    const diff = valB - valA;
    return (
      <div className="flex items-center gap-2 text-[10px]">
        <span className="w-7 text-right text-gray-500 font-heading">{label}</span>
        <span className="w-5 text-right tabular-nums text-red-400">{valA}</span>
        <div className="flex-1 h-1 bg-navy-600 rounded-full overflow-hidden flex">
          <div className="h-full bg-red-500/60" style={{ width: `${valA}%` }} />
        </div>
        <div className="flex-1 h-1 bg-navy-600 rounded-full overflow-hidden flex justify-end">
          <div className="h-full bg-green-500/60" style={{ width: `${valB}%` }} />
        </div>
        <span className="w-5 tabular-nums text-green-400">{valB}</span>
        <span className={`w-6 text-right tabular-nums font-heading font-bold ${diff > 0 ? "text-green-400" : diff < 0 ? "text-red-400" : "text-gray-600"}`}>
          {diff > 0 ? "+" : ""}{diff}
        </span>
      </div>
    );
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm" onClick={onClose}>
      <div className="bg-navy-800 rounded-2xl border border-navy-600 shadow-2xl w-[900px] max-h-[85vh] flex flex-col overflow-hidden" onClick={e => e.stopPropagation()}>
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-navy-700 bg-gradient-to-r from-navy-700 to-navy-800">
          <div className="flex items-center gap-3">
            <RefreshCw className="w-5 h-5 text-accent-400" />
            <h3 className="font-heading font-bold text-sm uppercase tracking-widest text-white">Substitutions</h3>
            <Badge variant={subsMade >= snapshot.max_subs ? "danger" : "primary"} size="sm">
              {subsMade}/{snapshot.max_subs} used
            </Badge>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-white p-1.5 rounded-lg hover:bg-navy-600 transition-colors">
            <AlertTriangle className="w-4 h-4 hidden" />
            <span className="text-sm font-heading">✕</span>
          </button>
        </div>

        {subsMade >= snapshot.max_subs ? (
          <div className="flex-1 flex items-center justify-center p-12">
            <div className="flex flex-col items-center gap-3">
              <AlertTriangle className="w-8 h-8 text-yellow-500" />
              <p className="text-sm font-heading font-bold uppercase tracking-wider text-yellow-500">All substitutions used</p>
            </div>
          </div>
        ) : (
          <div className="flex-1 flex overflow-hidden">
            {/* Left: Pitch + On-Field Players */}
            <div className="flex-1 flex flex-col border-r border-navy-700">
              <div className="px-4 py-2 border-b border-navy-700 bg-navy-800/50">
                <p className="text-[10px] font-heading uppercase tracking-widest text-red-400">
                  {selectedOff ? `Taking off: ${selectedPlayer?.name}` : "Select a player to substitute off"}
                </p>
              </div>

              {/* Mini pitch visualization */}
              <div className="mx-4 mt-3 bg-gradient-to-b from-primary-900/30 to-primary-800/10 rounded-xl p-3 relative border border-primary-500/10 min-h-[200px]">
                <div className="absolute inset-x-3 top-1/2 border-t border-white/5" />
                <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-12 h-12 border border-white/5 rounded-full" />
                {positions.map((pos, rowIdx) => {
                  const players = team.players.filter(p => p.position === pos && !snapshot.sent_off.includes(p.id));
                  const y = [85, 62, 38, 14][rowIdx];
                  return (
                    <div key={pos} className="absolute left-0 right-0 flex justify-center gap-3" style={{ top: `${y}%`, transform: "translateY(-50%)" }}>
                      {players.map(p => {
                        const isSelected = selectedOff === p.id;
                        const isGK = pos === "Goalkeeper";
                        return (
                          <button
                            key={p.id}
                            onClick={() => !isGK ? setSelectedOff(isSelected ? null : p.id) : null}
                            className={`flex flex-col items-center gap-0.5 transition-all ${isGK ? "opacity-40 cursor-default" : "cursor-pointer hover:scale-110"} ${isSelected ? "scale-110" : ""}`}
                          >
                            <div className={`w-8 h-8 rounded-full flex items-center justify-center text-[9px] font-heading font-bold border-2 transition-all ${
                              isSelected ? "bg-red-500/80 border-red-300 text-white ring-2 ring-red-500/50" :
                              p.condition < 50 ? "bg-yellow-600/70 border-yellow-400 text-white" :
                              "bg-primary-500/60 border-primary-300/50 text-white"
                            }`}>
                              {Math.round(p.condition)}
                            </div>
                            <span className="text-[9px] text-white/70 font-medium truncate max-w-[56px]">{p.name.split(' ').pop()}</span>
                          </button>
                        );
                      })}
                    </div>
                  );
                })}
              </div>

              {/* On-field player table */}
              <div className="flex-1 overflow-auto px-4 py-2">
                <table className="w-full text-left">
                  <thead>
                    <tr className="text-[9px] font-heading uppercase tracking-widest text-gray-600 border-b border-navy-700">
                      <th className="py-1.5 pr-2">Player</th>
                      <th className="py-1.5 w-10 text-center">Pos</th>
                      <th className="py-1.5 w-10 text-center">OVR</th>
                      <th className="py-1.5 w-20">Fitness</th>
                    </tr>
                  </thead>
                  <tbody>
                    {team.players
                      .filter(p => p.position !== "Goalkeeper" && !snapshot.sent_off.includes(p.id))
                      .sort((a, b) => a.condition - b.condition)
                      .map(p => {
                        const isSelected = selectedOff === p.id;
                        const isSubOn = subbedOnIds.has(p.id);
                        const ovr = getOvr(p);
                        return (
                          <tr
                            key={p.id}
                            onClick={() => setSelectedOff(isSelected ? null : p.id)}
                            className={`cursor-pointer transition-colors text-xs ${
                              isSelected ? "bg-red-500/10" : "hover:bg-navy-700/50"
                            }`}
                          >
                            <td className="py-1.5 pr-2">
                              <div className="flex items-center gap-1.5">
                                {isSelected && <UserMinus className="w-3 h-3 text-red-400 flex-shrink-0" />}
                                {isSubOn && <span className="text-green-400 text-[9px]">▲</span>}
                                <span className={`font-medium truncate ${isSelected ? "text-red-300" : "text-gray-300"}`}>{p.name}</span>
                              </div>
                            </td>
                            <td className="py-1.5 w-10 text-center">
                              <span className="text-[10px] font-heading text-gray-500">{posAbbr[p.position] || p.position.substring(0, 3)}</span>
                            </td>
                            <td className="py-1.5 w-10 text-center font-heading font-bold text-gray-400">{ovr}</td>
                            <td className="py-1.5 w-20">
                              <div className="flex items-center gap-1">
                                <div className="flex-1 h-1.5 bg-navy-600 rounded-full overflow-hidden">
                                  <div className={`h-full ${condColor(p.condition)} rounded-full`} style={{ width: `${p.condition}%` }} />
                                </div>
                                <span className={`text-[10px] tabular-nums font-heading w-6 text-right ${condText(p.condition)}`}>{Math.round(p.condition)}</span>
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                  </tbody>
                </table>
              </div>
            </div>

            {/* Right: Bench Players + Comparison */}
            <div className="flex-1 flex flex-col">
              <div className="px-4 py-2 border-b border-navy-700 bg-navy-800/50">
                <p className="text-[10px] font-heading uppercase tracking-widest text-green-400">
                  {selectedOff ? "Select replacement from bench" : "Bench players"}
                </p>
              </div>

              {/* Comparison panel */}
              {selectedPlayer && comparedPlayer && (
                <div className="mx-4 mt-3 p-3 bg-navy-700/50 rounded-xl border border-navy-600">
                  <div className="flex items-center justify-between mb-2">
                    <div className="flex items-center gap-1.5">
                      <UserMinus className="w-3 h-3 text-red-400" />
                      <span className="text-[10px] text-red-300 font-heading font-bold truncate max-w-[100px]">{selectedPlayer.name}</span>
                    </div>
                    <span className="text-[9px] text-gray-600 font-heading uppercase">vs</span>
                    <div className="flex items-center gap-1.5">
                      <span className="text-[10px] text-green-300 font-heading font-bold truncate max-w-[100px]">{comparedPlayer.name}</span>
                      <UserPlus className="w-3 h-3 text-green-400" />
                    </div>
                  </div>
                  <CompareBar label="PAC" valA={selectedPlayer.pace} valB={comparedPlayer.pace} />
                  <CompareBar label="PAS" valA={selectedPlayer.passing} valB={comparedPlayer.passing} />
                  <CompareBar label="SHO" valA={selectedPlayer.shooting} valB={comparedPlayer.shooting} />
                  <CompareBar label="DRI" valA={selectedPlayer.dribbling} valB={comparedPlayer.dribbling} />
                  <CompareBar label="DEF" valA={selectedPlayer.defending} valB={comparedPlayer.defending} />
                  <CompareBar label="TAC" valA={selectedPlayer.tackling} valB={comparedPlayer.tackling} />
                  <CompareBar label="FIT" valA={Math.round(selectedPlayer.condition)} valB={Math.round(comparedPlayer.condition)} />
                </div>
              )}

              {/* Bench table */}
              <div className="flex-1 overflow-auto px-4 py-2">
                {availableBench.length === 0 ? (
                  <div className="flex items-center justify-center h-20 text-xs text-gray-600">No bench players available</div>
                ) : (
                  <table className="w-full text-left">
                    <thead>
                      <tr className="text-[9px] font-heading uppercase tracking-widest text-gray-600 border-b border-navy-700">
                        <th className="py-1.5 pr-2">Player</th>
                        <th className="py-1.5 w-10 text-center">Pos</th>
                        <th className="py-1.5 w-10 text-center">OVR</th>
                        <th className="py-1.5 w-20">Fitness</th>
                      </tr>
                    </thead>
                    <tbody>
                      {availableBench.map(p => {
                        const ovr = getOvr(p);
                        // Off-position indicator: compare with selected player's position
                        const posMatch = selectedPlayer ? p.position === selectedPlayer.position : true;
                        return (
                          <tr
                            key={p.id}
                            onClick={() => selectedOff ? (onSubstitute(selectedOff, p.id), setSelectedOff(null)) : null}
                            onMouseEnter={() => setHoveredBench(p.id)}
                            onMouseLeave={() => setHoveredBench(null)}
                            className={`transition-colors text-xs ${
                              selectedOff
                                ? "cursor-pointer hover:bg-green-500/10"
                                : "opacity-60"
                            }`}
                          >
                            <td className="py-1.5 pr-2">
                              <div className="flex items-center gap-1.5">
                                {selectedOff && <UserPlus className="w-3 h-3 text-green-400/50 flex-shrink-0" />}
                                <span className="font-medium truncate text-gray-300">{p.name}</span>
                              </div>
                            </td>
                            <td className="py-1.5 w-10 text-center">
                              <span className={`text-[10px] font-heading ${!posMatch && selectedOff ? "text-yellow-400" : "text-gray-500"}`}>
                                {posAbbr[p.position] || p.position.substring(0, 3)}
                                {!posMatch && selectedOff && " !"}
                              </span>
                            </td>
                            <td className="py-1.5 w-10 text-center font-heading font-bold text-gray-400">{ovr}</td>
                            <td className="py-1.5 w-20">
                              <div className="flex items-center gap-1">
                                <div className="flex-1 h-1.5 bg-navy-600 rounded-full overflow-hidden">
                                  <div className={`h-full ${condColor(p.condition)} rounded-full`} style={{ width: `${p.condition}%` }} />
                                </div>
                                <span className={`text-[10px] tabular-nums font-heading w-6 text-right ${condText(p.condition)}`}>{Math.round(p.condition)}</span>
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                )}
              </div>

              {/* Sub History */}
              {snapshot.substitutions.filter(s => s.side === side).length > 0 && (
                <div className="px-4 py-3 border-t border-navy-700">
                  <p className="text-[10px] font-heading uppercase tracking-widest text-gray-600 mb-1.5">History</p>
                  {snapshot.substitutions.filter(s => s.side === side).map((sub, i) => (
                    <div key={i} className="flex items-center gap-1.5 py-0.5 text-[11px]">
                      <span className="text-gray-600 tabular-nums w-5 text-right font-heading">{sub.minute}'</span>
                      <span className="text-green-400">▲</span>
                      <span className="text-gray-300 truncate">{getPlayerName(snapshot, sub.player_on_id)}</span>
                      <span className="text-red-400">▼</span>
                      <span className="text-gray-500 truncate">{getPlayerName(snapshot, sub.player_off_id)}</span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
