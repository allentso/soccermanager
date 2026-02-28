import { useState } from "react";
import { GameStateData } from "../../store/gameStore";
import { MatchSnapshot, MatchEvent, TEAM_TALK_OPTIONS, TeamTalkTone } from "./types";
import { getEventDisplay, getPlayerName } from "./helpers";
import { Badge } from "../ui";
import {
  Trophy, TrendingDown, Minus, Star,
  MessageCircle, ChevronRight, BarChart3
} from "lucide-react";

interface PostMatchScreenProps {
  snapshot: MatchSnapshot;
  gameState: GameStateData;
  userSide: "Home" | "Away" | null;
  isSpectator: boolean;
  importantEvents: MatchEvent[];
  onPressConference: () => void;
  onFinish: () => void;
}

export default function PostMatchScreen({
  snapshot, gameState, userSide, isSpectator, importantEvents, onPressConference, onFinish,
}: PostMatchScreenProps) {
  const [selectedTalk, setSelectedTalk] = useState<TeamTalkTone | null>(null);
  const [talkDelivered, setTalkDelivered] = useState(false);

  const homeTeamColor = gameState.teams.find(t => t.id === snapshot.home_team.id)?.colors?.primary || "#10b981";
  const awayTeamColor = gameState.teams.find(t => t.id === snapshot.away_team.id)?.colors?.primary || "#6366f1";

  const userScore = userSide === "Home" ? snapshot.home_score : snapshot.away_score;
  const oppScore = userSide === "Home" ? snapshot.away_score : snapshot.home_score;

  const resultType = userScore > oppScore ? "win" : userScore < oppScore ? "loss" : "draw";

  // Key events (goals, cards, subs)
  const keyEvents = importantEvents.filter(e =>
    ["Goal", "PenaltyGoal", "YellowCard", "RedCard", "SecondYellow", "PenaltyMiss", "Injury"].includes(e.event_type)
  );

  // Count stats from snapshot events
  const homeEvents = snapshot.events.filter(e => e.side === "Home");
  const awayEvents = snapshot.events.filter(e => e.side === "Away");
  const countType = (events: MatchEvent[], type: string) => events.filter(e => e.event_type === type).length;

  const homeShots = countType(homeEvents, "Goal") + countType(homeEvents, "PenaltyGoal") +
    countType(homeEvents, "ShotSaved") + countType(homeEvents, "ShotOffTarget") + countType(homeEvents, "ShotBlocked");
  const awayShots = countType(awayEvents, "Goal") + countType(awayEvents, "PenaltyGoal") +
    countType(awayEvents, "ShotSaved") + countType(awayEvents, "ShotOffTarget") + countType(awayEvents, "ShotBlocked");

  // Suggested team talk based on result
  const suggestedTalks: TeamTalkTone[] = resultType === "win"
    ? ["praise", "calm", "motivational"]
    : resultType === "loss"
      ? ["motivational", "assertive", "disappointed"]
      : ["calm", "motivational", "assertive"];

  const handleDeliverTalk = () => {
    if (!selectedTalk) return;
    setTalkDelivered(true);
  };

  return (
    <div className="min-h-screen bg-navy-900 text-white flex flex-col">
      {/* Result Header */}
      <header className={`border-b border-navy-700 px-4 py-8 ${
        resultType === "win" ? "bg-gradient-to-r from-primary-900/50 via-navy-900 to-primary-900/50" :
        resultType === "loss" ? "bg-gradient-to-r from-red-900/30 via-navy-900 to-red-900/30" :
        "bg-gradient-to-r from-navy-800 via-navy-900 to-navy-800"
      }`}>
        <div className="max-w-5xl mx-auto text-center">
          {/* Result badge */}
          {!isSpectator && userSide && (
            <div className="mb-4">
              {resultType === "win" && (
                <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-primary-500/20 rounded-full">
                  <Trophy className="w-4 h-4 text-accent-400" />
                  <span className="font-heading font-bold text-sm uppercase tracking-widest text-primary-400">Victory</span>
                </div>
              )}
              {resultType === "loss" && (
                <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-red-500/20 rounded-full">
                  <TrendingDown className="w-4 h-4 text-red-400" />
                  <span className="font-heading font-bold text-sm uppercase tracking-widest text-red-400">Defeat</span>
                </div>
              )}
              {resultType === "draw" && (
                <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-gray-500/20 rounded-full">
                  <Minus className="w-4 h-4 text-gray-400" />
                  <span className="font-heading font-bold text-sm uppercase tracking-widest text-gray-400">Draw</span>
                </div>
              )}
            </div>
          )}

          {/* Scoreboard */}
          <div className="flex items-center justify-center gap-10">
            <div className="flex items-center gap-4">
              <div
                className="w-16 h-16 rounded-xl flex items-center justify-center font-heading font-bold text-lg"
                style={{ backgroundColor: homeTeamColor + "30", borderColor: homeTeamColor, borderWidth: 2 }}
              >
                {snapshot.home_team.name.substring(0, 3).toUpperCase()}
              </div>
              <p className="font-heading font-bold text-lg text-gray-200">{snapshot.home_team.name}</p>
            </div>

            <div className="flex items-center gap-5">
              <span className="text-6xl font-heading font-bold text-white tabular-nums">{snapshot.home_score}</span>
              <div className="text-center">
                <p className="text-xs font-heading uppercase tracking-widest text-accent-400">Full Time</p>
                <p className="text-lg font-heading font-bold text-gray-600">FT</p>
              </div>
              <span className="text-6xl font-heading font-bold text-white tabular-nums">{snapshot.away_score}</span>
            </div>

            <div className="flex items-center gap-4">
              <p className="font-heading font-bold text-lg text-gray-200">{snapshot.away_team.name}</p>
              <div
                className="w-16 h-16 rounded-xl flex items-center justify-center font-heading font-bold text-lg"
                style={{ backgroundColor: awayTeamColor + "30", borderColor: awayTeamColor, borderWidth: 2 }}
              >
                {snapshot.away_team.name.substring(0, 3).toUpperCase()}
              </div>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <div className="flex-1 overflow-auto">
        <div className="max-w-5xl mx-auto px-6 py-6 grid grid-cols-3 gap-6">

          {/* Left: Match Events */}
          <div className="flex flex-col gap-4">
            <div className="bg-navy-800 rounded-xl border border-navy-700 p-4">
              <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 mb-3">
                Match Events
              </h3>
              {keyEvents.length === 0 ? (
                <p className="text-xs text-gray-600">A quiet match.</p>
              ) : (
                <div className="flex flex-col gap-2">
                  {keyEvents.map((evt, i) => {
                    const display = getEventDisplay(evt);
                    return (
                      <div key={i} className="flex items-center gap-2 text-xs">
                        <span className="text-gray-600 tabular-nums w-6 text-right font-heading">{evt.minute}'</span>
                        <span>{display.icon}</span>
                        <span className={`${display.color} font-medium truncate flex-1`}>
                          {getPlayerName(snapshot, evt.player_id)}
                        </span>
                        <Badge variant={evt.side === "Home" ? "primary" : "accent"} size="sm">
                          {evt.side === "Home" ? snapshot.home_team.name.substring(0, 3) : snapshot.away_team.name.substring(0, 3)}
                        </Badge>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>

            {/* Quick Stats */}
            <div className="bg-navy-800 rounded-xl border border-navy-700 p-4">
              <div className="flex items-center gap-2 mb-3">
                <BarChart3 className="w-4 h-4 text-gray-500" />
                <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500">
                  Quick Stats
                </h3>
              </div>
              <QuickStat label="Possession" home={`${snapshot.home_possession_pct.toFixed(0)}%`} away={`${snapshot.away_possession_pct.toFixed(0)}%`} homePct={snapshot.home_possession_pct} />
              <QuickStat label="Shots" home={homeShots} away={awayShots} />
              <QuickStat label="Fouls" home={countType(homeEvents, "Foul")} away={countType(awayEvents, "Foul")} />
              <QuickStat label="Corners" home={countType(homeEvents, "Corner")} away={countType(awayEvents, "Corner")} />
            </div>
          </div>

          {/* Center: Post-Match Team Talk */}
          <div className="flex flex-col gap-4">
            {!isSpectator && userSide ? (
              <div className="bg-navy-800 rounded-xl border border-navy-700 p-4">
                <div className="flex items-center gap-2 mb-4">
                  <MessageCircle className="w-4 h-4 text-accent-400" />
                  <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500">
                    Post-Match Team Talk
                  </h3>
                </div>

                {!talkDelivered ? (
                  <>
                    <p className="text-xs text-gray-400 mb-3">
                      Address your players after the match.
                    </p>
                    <div className="flex flex-col gap-2">
                      {TEAM_TALK_OPTIONS.map(opt => {
                        const isSuggested = suggestedTalks.includes(opt.id);
                        return (
                          <button
                            key={opt.id}
                            onClick={() => setSelectedTalk(opt.id)}
                            className={`flex items-center gap-3 p-3 rounded-lg text-left transition-all ${
                              selectedTalk === opt.id
                                ? "bg-primary-500/20 ring-2 ring-primary-500/50"
                                : "bg-navy-700/50 hover:bg-navy-700"
                            }`}
                          >
                            <span className="text-xl">{opt.icon}</span>
                            <div className="flex-1">
                              <div className="flex items-center gap-2">
                                <p className={`text-sm font-heading font-bold ${
                                  selectedTalk === opt.id ? "text-primary-400" : "text-gray-200"
                                }`}>{opt.label}</p>
                                {isSuggested && <Star className="w-3 h-3 text-accent-400" />}
                              </div>
                              <p className="text-[11px] text-gray-500">{opt.description}</p>
                            </div>
                          </button>
                        );
                      })}
                    </div>
                    {selectedTalk && (
                      <button
                        onClick={handleDeliverTalk}
                        className="w-full mt-3 py-2.5 bg-primary-500/20 hover:bg-primary-500/30 text-primary-400 rounded-lg font-heading font-bold text-sm uppercase tracking-wider transition-colors"
                      >
                        Deliver Team Talk
                      </button>
                    )}
                  </>
                ) : (
                  <div className="flex flex-col items-center gap-2 py-6">
                    <span className="text-4xl">{TEAM_TALK_OPTIONS.find(o => o.id === selectedTalk)?.icon}</span>
                    <p className="text-sm font-heading font-bold text-primary-400">
                      {TEAM_TALK_OPTIONS.find(o => o.id === selectedTalk)?.label}
                    </p>
                    <p className="text-xs text-gray-500 text-center">Your players listen and head to the dressing room.</p>
                    <Badge variant="success" size="sm">Talk Delivered</Badge>
                  </div>
                )}
              </div>
            ) : (
              <div className="bg-navy-800 rounded-xl border border-navy-700 p-4 flex flex-col items-center justify-center py-12">
                <p className="text-lg font-heading font-bold text-gray-400 mb-2">Match Over</p>
                <p className="text-sm text-gray-500 text-center">
                  {snapshot.home_score} - {snapshot.away_score}
                </p>
              </div>
            )}
          </div>

          {/* Right: Player Ratings (placeholder) */}
          <div className="flex flex-col gap-4">
            <div className="bg-navy-800 rounded-xl border border-navy-700 p-4">
              <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 mb-3">
                Scorers
              </h3>
              {renderScorers(snapshot, importantEvents, "Home")}
              {renderScorers(snapshot, importantEvents, "Away")}
              {keyEvents.filter(e => e.event_type === "Goal" || e.event_type === "PenaltyGoal").length === 0 && (
                <p className="text-xs text-gray-600">No goals scored.</p>
              )}
            </div>

            {/* Substitutions made */}
            {snapshot.substitutions.length > 0 && (
              <div className="bg-navy-800 rounded-xl border border-navy-700 p-4">
                <h3 className="text-xs font-heading font-bold uppercase tracking-widest text-gray-500 mb-3">
                  Substitutions
                </h3>
                <div className="flex flex-col gap-2">
                  {snapshot.substitutions.map((sub, i) => (
                    <div key={i} className="flex items-center gap-2 text-xs">
                      <span className="text-gray-600 tabular-nums w-6 text-right font-heading">{sub.minute}'</span>
                      <span className="text-green-400">↑</span>
                      <span className="text-gray-300 truncate flex-1">{getPlayerName(snapshot, sub.player_on_id)}</span>
                      <span className="text-red-400">↓</span>
                      <span className="text-gray-500 truncate">{getPlayerName(snapshot, sub.player_off_id)}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Footer */}
      <footer className="bg-navy-800 border-t border-navy-700 px-6 py-4">
        <div className="max-w-5xl mx-auto flex justify-between items-center">
          <p className="text-xs text-gray-600 font-heading uppercase tracking-wider">
            {isSpectator ? "Match complete." : "Address the press or head back."}
          </p>
          <div className="flex items-center gap-3">
            {!isSpectator && (
              <button
                onClick={onPressConference}
                className="flex items-center gap-2 px-6 py-3 bg-navy-700 hover:bg-navy-600 rounded-xl font-heading font-bold uppercase tracking-wider text-sm text-gray-300 transition-colors"
              >
                Press Conference
                <ChevronRight className="w-4 h-4" />
              </button>
            )}
            <button
              onClick={onFinish}
              className="flex items-center gap-2 px-8 py-3 bg-gradient-to-r from-primary-500 to-primary-600 hover:from-primary-600 hover:to-primary-700 rounded-xl font-heading font-bold uppercase tracking-wider text-sm text-white shadow-lg shadow-primary-500/20 transition-all"
            >
              Continue
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      </footer>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function renderScorers(snapshot: MatchSnapshot, events: MatchEvent[], side: "Home" | "Away") {
  const goals = events.filter(e =>
    e.side === side && (e.event_type === "Goal" || e.event_type === "PenaltyGoal")
  );
  if (goals.length === 0) return null;

  const team = side === "Home" ? snapshot.home_team : snapshot.away_team;
  return (
    <div className="mb-3 last:mb-0">
      <p className={`text-[10px] font-heading uppercase tracking-widest mb-1 ${
        side === "Home" ? "text-primary-400" : "text-indigo-400"
      }`}>{team.name}</p>
      {goals.map((g, i) => (
        <div key={i} className="flex items-center gap-2 text-xs py-0.5">
          <span className="text-gray-600 tabular-nums w-6 text-right font-heading">{g.minute}'</span>
          <span>⚽</span>
          <span className="text-gray-200 font-medium">{getPlayerName(snapshot, g.player_id)}</span>
          {g.event_type === "PenaltyGoal" && <Badge variant="accent" size="sm">PEN</Badge>}
        </div>
      ))}
    </div>
  );
}

function QuickStat({
  label, home, away, homePct,
}: {
  label: string;
  home: number | string;
  away: number | string;
  homePct?: number;
}) {
  const hv = typeof home === "number" ? home : 0;
  const av = typeof away === "number" ? away : 0;
  const total = hv + av || 1;
  const pct = homePct ?? (hv / total * 100);

  return (
    <div className="mb-2 last:mb-0">
      <div className="flex justify-between text-xs mb-0.5">
        <span className="font-heading font-bold text-primary-400 tabular-nums">{home}</span>
        <span className="text-gray-600 font-heading uppercase tracking-wider text-[10px]">{label}</span>
        <span className="font-heading font-bold text-indigo-400 tabular-nums">{away}</span>
      </div>
      <div className="flex h-1 bg-navy-700 rounded-full overflow-hidden">
        <div className="h-full bg-primary-500" style={{ width: `${pct}%` }} />
        <div className="h-full bg-indigo-500" style={{ width: `${100 - pct}%` }} />
      </div>
    </div>
  );
}
