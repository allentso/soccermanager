import { GameStateData, FixtureData } from "../store/gameStore";
import { Card, CardHeader, CardBody, Badge, ProgressBar } from "./ui";
import { getTeamName, getTeamShort, findNextFixture, formatMatchDate, calcOvr } from "../lib/helpers";
import { resolveMessage } from "../utils/backendI18n";
import {
  Calendar, Trophy, Dumbbell, Mail, Newspaper,
  AlertTriangle, Flame, Scale, Feather,
  CheckCircle2, Circle, Users, Crosshair, UserCog, Lightbulb,
} from "lucide-react";

interface HomeTabProps {
  gameState: GameStateData;
  onNavigate?: (tab: string, context?: { messageId?: string }) => void;
}

const SCHEDULE_META: Record<string, { label: string; icon: React.ReactNode; color: string }> = {
  Intense:  { label: "Intense",  icon: <Flame className="w-3.5 h-3.5" />,   color: "text-red-500" },
  Balanced: { label: "Balanced", icon: <Scale className="w-3.5 h-3.5" />,   color: "text-primary-500" },
  Light:    { label: "Light",    icon: <Feather className="w-3.5 h-3.5" />, color: "text-blue-500" },
};

export default function HomeTab({ gameState, onNavigate }: HomeTabProps) {
  const myTeam = gameState.teams.find(t => t.id === gameState.manager.team_id);
  const league = gameState.league;
  const roster = myTeam ? gameState.players.filter(p => p.team_id === myTeam.id) : [];
  const avgCondition = roster.length > 0 ? Math.round(roster.reduce((s, p) => s + p.condition, 0) / roster.length) : 0;
  const avgOvr = roster.length > 0 ? Math.round(roster.reduce((s, p) => s + calcOvr(p), 0) / roster.length) : 0;
  const exhaustedCount = roster.filter(p => p.condition < 40).length;
  const unreadCount = (gameState.messages || []).filter(m => !m.read).length;

  // League position
  const myStanding = league && myTeam
    ? league.standings
        .sort((a, b) => b.points - a.points || (b.goals_for - b.goals_against) - (a.goals_for - a.goals_against))
        .findIndex(s => s.team_id === myTeam.id) + 1
    : null;
  const myStandingData = league && myTeam ? league.standings.find(s => s.team_id === myTeam.id) : null;

  // Recent results (last 5 completed fixtures involving user team)
  const recentResults: (FixtureData & { result: NonNullable<FixtureData["result"]> })[] = [];
  if (league && myTeam) {
    for (const f of [...league.fixtures].reverse()) {
      if (f.status === "Completed" && f.result && (f.home_team_id === myTeam.id || f.away_team_id === myTeam.id)) {
        recentResults.push(f as FixtureData & { result: NonNullable<FixtureData["result"]> });
        if (recentResults.length >= 5) break;
      }
    }
    recentResults.reverse();
  }

  // Current date
  const currentDate = new Date(gameState.clock.current_date);
  const dateStr = currentDate.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric", year: "numeric" });

  // Training schedule
  const schedule = myTeam?.training_schedule || "Balanced";
  const schedMeta = SCHEDULE_META[schedule] || SCHEDULE_META.Balanced;
  const focus = myTeam?.training_focus || "Physical";

  // Latest news
  const latestNews = (gameState.news || []).sort((a, b) => b.date.localeCompare(a.date)).slice(0, 2);

  // Onboarding: show Getting Started during first 7 days
  const startDate = new Date(gameState.clock.start_date);
  const daysSinceStart = Math.floor((currentDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24));
  const showOnboarding = daysSinceStart <= 7;

  // Onboarding checklist items with smart completion detection
  const myStaff = myTeam ? gameState.staff.filter(s => s.team_id === myTeam.id) : [];
  const hasCoach = myStaff.some(s => s.role === "Coach");
  const hasPhysio = myStaff.some(s => s.role === "Physio");
  const hasReviewedSquad = (gameState.messages || []).some(m => m.id === "welcome_1" && m.read);
  const hasSetFormation = myTeam ? myTeam.formation !== "4-4-2" : false;
  const hasReadInbox = (gameState.messages || []).filter(m => m.read).length >= 2;

  const onboardingSteps = [
    { id: "squad", done: hasReviewedSquad, label: "Review your squad", description: "Check player stats, condition, and traits", tab: "Squad", icon: <Users className="w-4 h-4" /> },
    { id: "staff", done: hasCoach && hasPhysio, label: "Hire coaching staff", description: "Staff boost training quality and recovery — hire a Coach and Physio", tab: "Staff", icon: <UserCog className="w-4 h-4" /> },
    { id: "tactics", done: hasSetFormation, label: "Set your formation & tactics", description: "Choose a formation and play style that fits your squad", tab: "Tactics", icon: <Crosshair className="w-4 h-4" /> },
    { id: "training", done: false, label: "Configure training", description: "Pick a focus and schedule to develop your players", tab: "Training", icon: <Dumbbell className="w-4 h-4" /> },
    { id: "inbox", done: hasReadInbox, label: "Read your messages", description: "Important info from the board and staff awaits", tab: "Inbox", icon: <Mail className="w-4 h-4" /> },
  ];
  const completedSteps = onboardingSteps.filter(s => s.done).length;

  return (
    <div className="max-w-6xl mx-auto flex flex-col gap-5">
      {/* Date header */}
      <div className="flex items-center gap-2">
        <Calendar className="w-4 h-4 text-gray-400 dark:text-gray-500" />
        <span className="text-sm text-gray-600 dark:text-gray-400">{dateStr}</span>
        {unreadCount > 0 && (
          <button onClick={() => onNavigate?.("Inbox")} className="ml-auto flex items-center gap-1.5 text-xs font-heading font-bold uppercase tracking-wider text-primary-500 hover:text-primary-600 dark:hover:text-primary-400 transition-colors">
            <Mail className="w-3.5 h-3.5" />
            {unreadCount} unread message{unreadCount > 1 ? "s" : ""}
          </button>
        )}
      </div>

      {/* Onboarding — Getting Started Checklist */}
      {showOnboarding && completedSteps < onboardingSteps.length && (
        <Card accent="accent">
          <CardHeader>
            <div className="flex items-center gap-2">
              <Lightbulb className="w-4 h-4 text-accent-500" />
              Getting Started
            </div>
          </CardHeader>
          <CardBody>
            <p className="text-xs text-gray-500 dark:text-gray-400 mb-3">
              Complete these steps to prepare your team for the upcoming season. Staff are especially important — they boost training and recovery.
            </p>
            <div className="flex items-center gap-2 mb-4">
              <ProgressBar value={Math.round((completedSteps / onboardingSteps.length) * 100)} variant="accent" size="sm" />
              <span className="text-xs font-heading font-bold text-gray-500 dark:text-gray-400 flex-shrink-0">{completedSteps}/{onboardingSteps.length}</span>
            </div>
            <div className="flex flex-col gap-2">
              {onboardingSteps.map(step => (
                <button
                  key={step.id}
                  onClick={() => onNavigate?.(step.tab)}
                  className={`flex items-center gap-3 p-3 rounded-lg text-left transition-all ${
                    step.done
                      ? "bg-primary-50 dark:bg-primary-500/5 opacity-70"
                      : "bg-gray-50 dark:bg-navy-700/50 hover:bg-gray-100 dark:hover:bg-navy-700"
                  }`}
                >
                  <div className={`flex-shrink-0 ${step.done ? "text-primary-500" : "text-gray-400 dark:text-gray-500"}`}>
                    {step.done ? <CheckCircle2 className="w-5 h-5" /> : <Circle className="w-5 h-5" />}
                  </div>
                  <div className={`flex-shrink-0 ${step.done ? "text-primary-500" : "text-gray-500 dark:text-gray-400"}`}>
                    {step.icon}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className={`text-sm font-heading font-bold ${step.done ? "text-gray-400 dark:text-gray-500 line-through" : "text-gray-800 dark:text-gray-200"}`}>
                      {step.label}
                    </p>
                    <p className="text-xs text-gray-400 dark:text-gray-500 mt-0.5">{step.description}</p>
                  </div>
                </button>
              ))}
            </div>
          </CardBody>
        </Card>
      )}

      <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
        {/* Next Match Card */}
        <Card accent="primary" className="md:col-span-2">
          <CardHeader>Next Match</CardHeader>
          <CardBody>
            <NextMatchDisplay gameState={gameState} />
          </CardBody>
        </Card>

        {/* League Position */}
        <Card accent="accent">
          <CardHeader
            action={
              <button onClick={() => onNavigate?.("Schedule")} className="text-primary-500 dark:text-primary-400 text-xs font-heading font-bold uppercase tracking-wider hover:text-primary-600 dark:hover:text-primary-300 transition-colors">
                Standings
              </button>
            }
          >
            League Position
          </CardHeader>
          <CardBody>
            {myStanding && myStandingData ? (
              <div className="flex flex-col items-center gap-3">
                <div className="flex items-center gap-3">
                  <div className="w-16 h-16 rounded-xl bg-accent-500/10 flex items-center justify-center">
                    <span className="text-3xl font-heading font-bold text-accent-500">{myStanding}</span>
                  </div>
                  <div>
                    <p className="text-xs text-gray-500 dark:text-gray-400 font-heading uppercase tracking-wider">
                      {myStanding === 1 ? "1st" : myStanding === 2 ? "2nd" : myStanding === 3 ? "3rd" : `${myStanding}th`} Place
                    </p>
                    <p className="text-lg font-heading font-bold text-gray-800 dark:text-gray-100">{myStandingData.points} pts</p>
                  </div>
                </div>
                <div className="w-full grid grid-cols-4 text-center gap-1">
                  <div>
                    <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">P</p>
                    <p className="text-sm font-heading font-bold text-gray-700 dark:text-gray-300">{myStandingData.played}</p>
                  </div>
                  <div>
                    <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">W</p>
                    <p className="text-sm font-heading font-bold text-green-500">{myStandingData.won}</p>
                  </div>
                  <div>
                    <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">D</p>
                    <p className="text-sm font-heading font-bold text-gray-500">{myStandingData.drawn}</p>
                  </div>
                  <div>
                    <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">L</p>
                    <p className="text-sm font-heading font-bold text-red-500">{myStandingData.lost}</p>
                  </div>
                </div>
                {/* Form (recent 5) */}
                {myTeam && myTeam.form && myTeam.form.length > 0 && (() => {
                  const form = myTeam.form;
                  const last3 = form.slice(-3);
                  const winStreak = last3.length >= 3 && last3.every(r => r === "W");
                  const loseStreak = last3.length >= 3 && last3.every(r => r === "L");
                  const unbeaten = form.length >= 4 && form.every(r => r !== "L");
                  return (
                    <div className="flex flex-col items-center gap-1.5 mt-1">
                      <div className="flex gap-1.5">
                        {form.map((res, i) => (
                          <span key={i} className={`w-6 h-6 rounded flex items-center justify-center text-[10px] font-heading font-bold text-white ${
                            res === "W" ? "bg-green-500" : res === "L" ? "bg-red-500" : "bg-gray-400"
                          }`}>
                            {res}
                          </span>
                        ))}
                      </div>
                      {winStreak && <span className="text-[10px] font-heading font-bold text-green-500 uppercase tracking-wider">Winning streak!</span>}
                      {loseStreak && <span className="text-[10px] font-heading font-bold text-red-500 uppercase tracking-wider">Losing streak</span>}
                      {!winStreak && !loseStreak && unbeaten && <span className="text-[10px] font-heading font-bold text-primary-500 uppercase tracking-wider">Unbeaten run</span>}
                    </div>
                  );
                })()}
              </div>
            ) : (
              <div className="flex flex-col items-center gap-2 py-4">
                <Trophy className="w-8 h-8 text-gray-300 dark:text-navy-600" />
                <p className="text-xs text-gray-500 dark:text-gray-400">No league data yet.</p>
              </div>
            )}
          </CardBody>
        </Card>
      </div>

      {/* Board Objectives */}
      {(gameState.board_objectives || []).length > 0 && (
        <Card className="mb-5">
          <CardHeader>Board Objectives</CardHeader>
          <CardBody>
            <div className="flex flex-col gap-2.5">
              {(gameState.board_objectives || []).map(obj => (
                <div key={obj.id} className="flex items-center gap-3">
                  {obj.met ? (
                    <CheckCircle2 className="w-4 h-4 text-green-500 flex-shrink-0" />
                  ) : (
                    <Circle className="w-4 h-4 text-gray-300 dark:text-navy-600 flex-shrink-0" />
                  )}
                  <span className={`text-sm ${obj.met ? "text-green-600 dark:text-green-400 line-through" : "text-gray-700 dark:text-gray-300"}`}>
                    {obj.description}
                  </span>
                  <Badge variant={obj.met ? "success" : "neutral"} size="sm" className="ml-auto">
                    {obj.met ? "Met" : "In Progress"}
                  </Badge>
                </div>
              ))}
            </div>
            <div className="mt-3 pt-2 border-t border-gray-100 dark:border-navy-700">
              <p className="text-[10px] text-gray-400 dark:text-gray-500">
                {(gameState.board_objectives || []).filter(o => o.met).length}/{(gameState.board_objectives || []).length} objectives met — Board satisfaction: {gameState.manager.satisfaction}%
              </p>
            </div>
          </CardBody>
        </Card>
      )}

      <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
        {/* Squad Fitness */}
        <Card>
          <CardHeader
            action={
              <button onClick={() => onNavigate?.("Training")} className="text-primary-500 dark:text-primary-400 text-xs font-heading font-bold uppercase tracking-wider hover:text-primary-600 dark:hover:text-primary-300 transition-colors">
                Training
              </button>
            }
          >
            Squad Overview
          </CardHeader>
          <CardBody>
            <div className="flex flex-col gap-3">
              <div className="flex items-center justify-between">
                <span className="text-xs text-gray-500 dark:text-gray-400">Avg Condition</span>
                <span className="font-heading font-bold text-sm text-gray-800 dark:text-gray-100">{avgCondition}%</span>
              </div>
              <ProgressBar value={avgCondition} variant="auto" size="md" />

              <div className="flex items-center justify-between mt-1">
                <span className="text-xs text-gray-500 dark:text-gray-400">Avg OVR</span>
                <span className="font-heading font-bold text-sm text-gray-800 dark:text-gray-100">{avgOvr}</span>
              </div>

              {exhaustedCount > 0 && (
                <div className="flex items-center gap-1.5 mt-1 text-amber-500 dark:text-amber-400">
                  <AlertTriangle className="w-3.5 h-3.5" />
                  <span className="text-xs font-heading">{exhaustedCount} player{exhaustedCount > 1 ? "s" : ""} exhausted</span>
                </div>
              )}

              <div className="mt-2 pt-2 border-t border-gray-100 dark:border-navy-700 flex items-center gap-2">
                <Dumbbell className="w-3.5 h-3.5 text-gray-400 dark:text-gray-500" />
                <span className="text-xs text-gray-500 dark:text-gray-400">Schedule:</span>
                <span className={`text-xs font-heading font-bold flex items-center gap-1 ${schedMeta.color}`}>
                  {schedMeta.icon} {schedMeta.label}
                </span>
                <span className="text-xs text-gray-400 dark:text-gray-500 ml-auto">{focus}</span>
              </div>
            </div>
          </CardBody>
        </Card>

        {/* Recent Results */}
        <Card>
          <CardHeader
            action={
              <button onClick={() => onNavigate?.("Schedule")} className="text-primary-500 dark:text-primary-400 text-xs font-heading font-bold uppercase tracking-wider hover:text-primary-600 dark:hover:text-primary-300 transition-colors">
                Schedule
              </button>
            }
          >
            Recent Results
          </CardHeader>
          <CardBody className="p-0">
            {recentResults.length === 0 ? (
              <p className="text-gray-500 dark:text-gray-400 text-xs p-5">No matches played yet.</p>
            ) : (
              <div className="divide-y divide-gray-100 dark:divide-navy-600">
                {recentResults.slice(-5).reverse().map(f => {
                  const isHome = f.home_team_id === myTeam!.id;
                  const myGoals = isHome ? f.result.home_goals : f.result.away_goals;
                  const oppGoals = isHome ? f.result.away_goals : f.result.home_goals;
                  const oppId = isHome ? f.away_team_id : f.home_team_id;
                  const res = myGoals > oppGoals ? "W" : myGoals < oppGoals ? "L" : "D";
                  return (
                    <div key={f.id} className="flex items-center px-4 py-2.5 gap-3">
                      <span className={`w-5 h-5 rounded flex items-center justify-center text-[9px] font-heading font-bold text-white flex-shrink-0 ${
                        res === "W" ? "bg-green-500" : res === "L" ? "bg-red-500" : "bg-gray-400"
                      }`}>
                        {res}
                      </span>
                      <span className="text-xs text-gray-500 dark:text-gray-400 flex-shrink-0 w-6">{isHome ? "H" : "A"}</span>
                      <span className="text-sm font-medium text-gray-800 dark:text-gray-200 flex-1 truncate">
                        {getTeamName(gameState.teams, oppId)}
                      </span>
                      <span className="text-sm font-heading font-bold text-gray-700 dark:text-gray-300 tabular-nums">
                        {myGoals} – {oppGoals}
                      </span>
                    </div>
                  );
                })}
              </div>
            )}
          </CardBody>
        </Card>

        {/* Latest News + Messages */}
        <Card>
          <CardHeader
            action={
              <button onClick={() => onNavigate?.("News")} className="text-primary-500 dark:text-primary-400 text-xs font-heading font-bold uppercase tracking-wider hover:text-primary-600 dark:hover:text-primary-300 transition-colors">
                All News
              </button>
            }
          >
            Latest News
          </CardHeader>
          <CardBody className="p-0">
            {latestNews.length === 0 ? (
              <div className="flex flex-col items-center gap-2 py-6">
                <Newspaper className="w-8 h-8 text-gray-300 dark:text-navy-600" />
                <p className="text-xs text-gray-500 dark:text-gray-400">No news yet.</p>
              </div>
            ) : (
              <div className="divide-y divide-gray-100 dark:divide-navy-600">
                {latestNews.map(article => (
                  <button
                    key={article.id}
                    onClick={() => onNavigate?.("News")}
                    className="w-full text-left px-4 py-3 hover:bg-gray-50 dark:hover:bg-navy-700/50 transition-colors"
                  >
                    <p className="text-xs text-gray-400 dark:text-gray-500 mb-0.5">
                      {new Date(article.date).toLocaleDateString(undefined, { month: "short", day: "numeric" })} · {article.source}
                    </p>
                    <p className="text-sm font-heading font-bold text-gray-800 dark:text-gray-200 leading-snug line-clamp-2">
                      {article.headline}
                    </p>
                    {article.match_score && (
                      <div className="flex items-center gap-1.5 mt-1">
                        <span className="text-[10px] text-gray-500 dark:text-gray-400">{getTeamName(gameState.teams, article.match_score.home_team_id)}</span>
                        <span className="text-[10px] font-heading font-bold text-primary-500">{article.match_score.home_goals}–{article.match_score.away_goals}</span>
                        <span className="text-[10px] text-gray-500 dark:text-gray-400">{getTeamName(gameState.teams, article.match_score.away_team_id)}</span>
                      </div>
                    )}
                  </button>
                ))}
              </div>
            )}
          </CardBody>
        </Card>
      </div>

      {/* Recent Messages */}
      <Card>
        <CardHeader
          action={
            <button
              onClick={() => onNavigate?.("Inbox")}
              className="text-primary-500 dark:text-primary-400 text-xs font-heading font-bold uppercase tracking-wider hover:text-primary-600 dark:hover:text-primary-300 transition-colors"
            >
              View All
            </button>
          }
        >
          Recent Messages
        </CardHeader>
        <CardBody className="p-0">
          <div className="divide-y divide-gray-100 dark:divide-navy-600">
            {(gameState.messages || []).length === 0 ? (
              <p className="text-gray-500 dark:text-gray-400 p-6 text-sm">No recent messages.</p>
            ) : (
              (gameState.messages || []).slice(0, 4).map(resolveMessage).map(message => (
                <div
                  key={message.id}
                  onClick={() => onNavigate?.("Inbox", { messageId: message.id })}
                  className={`flex gap-4 px-6 py-3.5 hover:bg-gray-50 dark:hover:bg-navy-600/50 cursor-pointer transition-colors ${!message.read ? 'border-l-4 border-l-primary-500' : 'border-l-4 border-l-transparent'}`}
                >
                  <div className={`w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 font-heading font-bold text-sm ${
                    message.read 
                      ? 'bg-gray-100 dark:bg-navy-600 text-gray-400 dark:text-gray-500' 
                      : 'bg-primary-500/10 dark:bg-primary-500/20 text-primary-600 dark:text-primary-400'
                  }`}>
                    {message.sender.charAt(0)}
                  </div>
                  <div className="min-w-0 flex-1">
                    <h4 className={`font-semibold text-sm ${message.read ? 'text-gray-500 dark:text-gray-400' : 'text-gray-900 dark:text-gray-100'}`}>{message.subject}</h4>
                    <p className={`text-xs truncate mt-0.5 ${message.read ? 'text-gray-400 dark:text-gray-500' : 'text-gray-600 dark:text-gray-300'}`}>
                      {message.body}
                    </p>
                  </div>
                  <span className="text-[10px] text-gray-400 dark:text-gray-500 flex-shrink-0 mt-1">
                    {new Date(message.date).toLocaleDateString(undefined, { month: "short", day: "numeric" })}
                  </span>
                </div>
              ))
            )}
          </div>
        </CardBody>
      </Card>
    </div>
  );
}

function NextMatchDisplay({ gameState }: { gameState: GameStateData }) {
  const userTeamId = gameState.manager.team_id;
  const league = gameState.league;

  if (!userTeamId || !league) {
    return <p className="text-gray-500 dark:text-gray-400 text-sm text-center py-4">No league schedule yet.</p>;
  }

  const nextFixture = findNextFixture(league.fixtures, userTeamId);
  if (!nextFixture) {
    return <p className="text-gray-500 dark:text-gray-400 text-sm text-center py-4">Season complete — no upcoming matches.</p>;
  }

  const isHome = nextFixture.home_team_id === userTeamId;
  const opponentId = isHome ? nextFixture.away_team_id : nextFixture.home_team_id;

  return (
    <div className="flex items-center justify-between py-6 px-4 bg-gray-50 dark:bg-navy-800 rounded-lg border border-gray-100 dark:border-navy-600 transition-colors">
      <div className="text-center flex-1">
        <div className="w-16 h-16 bg-gradient-to-br from-primary-500/20 to-primary-600/20 dark:from-primary-500/10 dark:to-primary-600/10 rounded-full mx-auto mb-2 flex items-center justify-center font-heading font-bold text-primary-600 dark:text-primary-400 text-lg border-2 border-primary-200 dark:border-primary-800 transition-colors">
          {getTeamShort(gameState.teams, nextFixture.home_team_id)}
        </div>
        <p className={`font-heading font-bold uppercase tracking-wide text-sm ${isHome ? "text-primary-600 dark:text-primary-400" : "text-gray-500 dark:text-gray-400"}`}>
          {getTeamName(gameState.teams, nextFixture.home_team_id)}
        </p>
      </div>

      <div className="text-center px-4 flex flex-col items-center gap-1.5">
        <span className="font-heading font-bold text-2xl text-gray-300 dark:text-navy-600">VS</span>
        <Badge variant="neutral">{formatMatchDate(nextFixture.date)}</Badge>
        <span className="text-xs text-gray-400 dark:text-gray-500">Matchday {nextFixture.matchday}</span>
        <Badge variant={isHome ? "success" : "accent"} size="sm">{isHome ? "Home" : "Away"}</Badge>
      </div>

      <div className="text-center flex-1">
        <div className="w-16 h-16 bg-gray-200 dark:bg-navy-600 rounded-full mx-auto mb-2 flex items-center justify-center font-heading font-bold text-gray-500 dark:text-gray-400 text-lg border-2 border-gray-300 dark:border-navy-600 transition-colors">
          {getTeamShort(gameState.teams, opponentId)}
        </div>
        <p className={`font-heading font-bold uppercase tracking-wide text-sm ${!isHome ? "text-primary-600 dark:text-primary-400" : "text-gray-500 dark:text-gray-400"}`}>
          {getTeamName(gameState.teams, opponentId)}
        </p>
      </div>
    </div>
  );
}
