import type { GameStateData } from "../../store/gameStore";
import { Card, CardHeader, CardBody, Badge, ProgressBar } from "../ui";
import { getTeamName, formatDateShort } from "../../lib/helpers";
import { resolveSeasonContext } from "../../lib/seasonContext";
import NextMatchDisplay from "../NextMatchDisplay";
import {
  resolveBoardObjective,
  resolveMessage,
  resolveNewsArticle,
} from "../../utils/backendI18n";
import {
  getHomeRosterOverview,
  getLeagueDigestArticles,
  getNextOpponentWidgetData,
  getOnboardingCompletionState,
  getRecentResultsForTeam,
} from "./HomeTab.helpers";
import { translatePositionAbbreviation } from "../squad/SquadTab.helpers";
import HomeLeagueDigestCard from "./HomeLeagueDigestCard";
import HomeNextOpponentCard from "./HomeNextOpponentCard";
import {
  Trophy,
  Dumbbell,
  Mail,
  Newspaper,
  AlertTriangle,
  Flame,
  Scale,
  Feather,
  CheckCircle2,
  Circle,
  Users,
  Crosshair,
  UserCog,
  TrendingUp,
  TrendingDown,
  CalendarClock,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import HomeOnboardingChecklistCard from "./HomeOnboardingChecklistCard";

interface HomeTabProps {
  gameState: GameStateData;
  onNavigate?: (tab: string, context?: { messageId?: string }) => void;
  visitedOnboardingTabs: ReadonlySet<string>;
}

const SCHEDULE_ICONS: Record<string, { icon: React.ReactNode; color: string }> =
  {
    Intense: { icon: <Flame className="w-3.5 h-3.5" />, color: "text-red-500" },
    Balanced: {
      icon: <Scale className="w-3.5 h-3.5" />,
      color: "text-primary-500",
    },
    Light: {
      icon: <Feather className="w-3.5 h-3.5" />,
      color: "text-blue-500",
    },
  };

export default function HomeTab({
  gameState,
  onNavigate,
  visitedOnboardingTabs,
}: HomeTabProps) {
  const { t, i18n } = useTranslation();
  const myTeam = gameState.teams.find(
    (tm) => tm.id === gameState.manager.team_id,
  );
  const league = gameState.league;
  const roster = myTeam
    ? gameState.players.filter((p) => p.team_id === myTeam.id)
    : [];
  const {
    avgCondition,
    avgOvr,
    coldPlayers,
    exhaustedCount,
    hotPlayers,
    unavailablePlayers,
  } = getHomeRosterOverview(roster);
  const resolveInjuryName = (injuryName: string): string => {
    if (injuryName.includes(".")) {
      return t(injuryName, { defaultValue: injuryName });
    }

    return t(`common.injuries.${injuryName}`, { defaultValue: injuryName });
  };

  // Current date / season context
  const lang = i18n.language;
  const seasonContext = resolveSeasonContext(gameState);
  const isPreseason = seasonContext.phase === "Preseason";
  const seasonStartLabel = seasonContext.season_start
    ? formatDateShort(seasonContext.season_start, lang)
    : null;
  const transferWindow = seasonContext.transfer_window;
  const transferWindowVariant =
    transferWindow.status === "DeadlineDay"
      ? "danger"
      : transferWindow.status === "Open"
        ? "success"
        : "neutral";
  const transferWindowSummary =
    transferWindow.status === "DeadlineDay"
      ? t("season.windowClosesToday")
      : transferWindow.status === "Open" &&
          transferWindow.days_remaining !== null
        ? t("season.windowClosesInDays", {
            count: transferWindow.days_remaining,
          })
        : transferWindow.status === "Closed" &&
            transferWindow.days_until_opens !== null
          ? t("season.windowOpensInDays", {
              count: transferWindow.days_until_opens,
            })
          : t("season.windowClosed");

  // League position
  const myStanding =
    !isPreseason && league && myTeam
      ? league.standings
          .sort(
            (a, b) =>
              b.points - a.points ||
              b.goals_for - b.goals_against - (a.goals_for - a.goals_against),
          )
          .findIndex((s) => s.team_id === myTeam.id) + 1
      : null;
  const myStandingData =
    !isPreseason && league && myTeam
      ? league.standings.find((s) => s.team_id === myTeam.id)
      : null;

  const recentResults = getRecentResultsForTeam(gameState, myTeam?.id ?? null);

  // Training schedule
  const schedule = myTeam?.training_schedule || "Balanced";
  const schedIcons = SCHEDULE_ICONS[schedule] || SCHEDULE_ICONS.Balanced;
  const schedLabel = t(`common.trainingSchedules.${schedule}`, schedule);
  const focus = myTeam?.training_focus || "Physical";

  // Latest news
  const latestNews = (gameState.news || [])
    .sort((a, b) => b.date.localeCompare(a.date))
    .slice(0, 2);
  const nextOpponent = getNextOpponentWidgetData(gameState);
  const leagueDigestArticles =
    getLeagueDigestArticles(gameState).map(resolveNewsArticle);
  const boardObjectives = (gameState.board_objectives || []).map(
    resolveBoardObjective,
  );
  const onboardingState = getOnboardingCompletionState(
    gameState,
    visitedOnboardingTabs,
  );

  const onboardingSteps = [
    {
      id: "squad",
      done: onboardingState.hasVisitedSquadPage,
      label: t("onboarding.reviewSquad"),
      description: t("onboarding.reviewSquadDesc"),
      tab: "Squad",
      icon: <Users className="w-4 h-4" />,
    },
    {
      id: "staff",
      done: onboardingState.hasVisitedStaffPage,
      label: t("onboarding.hireStaff"),
      description: t("onboarding.hireStaffDesc"),
      tab: "Staff",
      icon: <UserCog className="w-4 h-4" />,
    },
    {
      id: "tactics",
      done: onboardingState.hasVisitedTacticsPage,
      label: t("onboarding.setTactics"),
      description: t("onboarding.setTacticsDesc"),
      tab: "Tactics",
      icon: <Crosshair className="w-4 h-4" />,
    },
    {
      id: "training",
      done: onboardingState.hasVisitedTrainingPage,
      label: t("onboarding.configTraining"),
      description: t("onboarding.configTrainingDesc"),
      tab: "Training",
      icon: <Dumbbell className="w-4 h-4" />,
    },
    {
      id: "inbox",
      done: onboardingState.hasReadInbox,
      label: t("onboarding.readMessages"),
      description: t("onboarding.readMessagesDesc"),
      tab: "Inbox",
      icon: <Mail className="w-4 h-4" />,
    },
  ];
  const completedSteps = onboardingState.completedSteps;

  return (
    <div className="max-w-6xl mx-auto flex flex-col gap-5">
      {isPreseason && (
        <Card accent="primary">
          <CardHeader>
            <div className="flex items-center gap-2">
              <CalendarClock className="w-4 h-4 text-primary-500" />
              {t("season.preseasonStatus")}
            </div>
          </CardHeader>
          <CardBody>
            <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div className="flex flex-col gap-2">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge variant="accent" size="sm">
                    {t(`season.phases.${seasonContext.phase}`)}
                  </Badge>
                  <Badge variant={transferWindowVariant} size="sm">
                    {t(`season.transferWindowStatus.${transferWindow.status}`)}
                  </Badge>
                </div>
                <p className="text-sm text-gray-700 dark:text-gray-300">
                  {t("season.preseasonFocus")}
                </p>
              </div>
              <div className="grid grid-cols-1 gap-3 md:grid-cols-2 md:min-w-[22rem]">
                <div className="rounded-xl bg-gray-50 px-4 py-3 dark:bg-navy-700/50">
                  <p className="text-[10px] font-heading font-bold uppercase tracking-wider text-gray-400 dark:text-gray-500">
                    {t("season.opener")}
                  </p>
                  <p className="mt-1 text-sm font-heading font-bold text-gray-800 dark:text-gray-100">
                    {seasonStartLabel
                      ? t("season.startsOn", { date: seasonStartLabel })
                      : t("season.noOpener")}
                  </p>
                  {seasonContext.days_until_season_start !== null && (
                    <p className="mt-1 text-xs text-primary-500 dark:text-primary-400">
                      {t("season.startsInDays", {
                        count: seasonContext.days_until_season_start,
                      })}
                    </p>
                  )}
                </div>
                <div className="rounded-xl bg-gray-50 px-4 py-3 dark:bg-navy-700/50">
                  <p className="text-[10px] font-heading font-bold uppercase tracking-wider text-gray-400 dark:text-gray-500">
                    {t("transfers.centre")}
                  </p>
                  <p className="mt-1 text-sm font-heading font-bold text-gray-800 dark:text-gray-100">
                    {transferWindowSummary}
                  </p>
                  {(transferWindow.opens_on || transferWindow.closes_on) && (
                    <p className="mt-1 text-xs text-gray-500 dark:text-gray-400">
                      {transferWindow.status === "Closed" &&
                      transferWindow.opens_on
                        ? t("season.windowOpensOn", {
                            date: formatDateShort(
                              transferWindow.opens_on,
                              lang,
                            ),
                          })
                        : transferWindow.closes_on
                          ? t("season.windowClosesOn", {
                              date: formatDateShort(
                                transferWindow.closes_on,
                                lang,
                              ),
                            })
                          : transferWindowSummary}
                    </p>
                  )}
                </div>
              </div>
            </div>
          </CardBody>
        </Card>
      )}

      {/* Onboarding — Getting Started Checklist */}
      {onboardingState.showOnboarding &&
        completedSteps < onboardingSteps.length && (
          <HomeOnboardingChecklistCard
            completedSteps={completedSteps}
            totalSteps={onboardingSteps.length}
            steps={onboardingSteps}
            onNavigate={onNavigate}
          />
        )}

      <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
        {/* Next Match Card */}
        <Card accent="primary" className="md:col-span-2">
          <CardHeader>{t("home.nextMatch")}</CardHeader>
          <CardBody>
            <NextMatchDisplay gameState={gameState} />
          </CardBody>
        </Card>

        {/* League Position */}
        <Card accent="accent">
          <CardHeader
            action={
              <button
                onClick={() => onNavigate?.("Schedule")}
                className="text-primary-500 dark:text-primary-400 text-xs font-heading font-bold uppercase tracking-wider hover:text-primary-600 dark:hover:text-primary-300 transition-colors"
              >
                {t("home.standings")}
              </button>
            }
          >
            {t("home.leaguePosition")}
          </CardHeader>
          <CardBody>
            {isPreseason ? (
              <div className="flex flex-col items-center gap-2 py-4 text-center">
                <Badge variant="accent" size="sm">
                  {t(`season.phases.${seasonContext.phase}`)}
                </Badge>
                <p className="text-sm font-heading font-bold text-gray-800 dark:text-gray-100">
                  {seasonStartLabel
                    ? t("season.startsOn", { date: seasonStartLabel })
                    : t("season.noOpener")}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400 max-w-xs">
                  {t("season.standingsLocked")}
                </p>
              </div>
            ) : myStanding && myStandingData ? (
              <div className="flex flex-col items-center gap-3">
                <div className="flex items-center gap-3">
                  <div className="w-16 h-16 rounded-xl bg-accent-500/10 flex items-center justify-center">
                    <span className="text-3xl font-heading font-bold text-accent-500">
                      {myStanding}
                    </span>
                  </div>
                  <div>
                    <p className="text-xs text-gray-500 dark:text-gray-400 font-heading uppercase tracking-wider">
                      {myStanding === 1
                        ? t("common.place.1")
                        : myStanding === 2
                          ? t("common.place.2")
                          : myStanding === 3
                            ? t("common.place.3")
                            : t("common.place.other", { n: myStanding })}
                    </p>
                    <p className="text-lg font-heading font-bold text-gray-800 dark:text-gray-100">
                      {myStandingData.points} pts
                    </p>
                  </div>
                </div>
                <div className="w-full grid grid-cols-4 text-center gap-1">
                  <div>
                    <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">
                      P
                    </p>
                    <p className="text-sm font-heading font-bold text-gray-700 dark:text-gray-300">
                      {myStandingData.played}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">
                      W
                    </p>
                    <p className="text-sm font-heading font-bold text-green-500">
                      {myStandingData.won}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">
                      D
                    </p>
                    <p className="text-sm font-heading font-bold text-gray-500">
                      {myStandingData.drawn}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">
                      L
                    </p>
                    <p className="text-sm font-heading font-bold text-red-500">
                      {myStandingData.lost}
                    </p>
                  </div>
                </div>
                {/* Form (recent 5) */}
                {myTeam &&
                  myTeam.form &&
                  myTeam.form.length > 0 &&
                  (() => {
                    const form = myTeam.form;
                    const last3 = form.slice(-3);
                    const winStreak =
                      last3.length >= 3 && last3.every((r) => r === "W");
                    const loseStreak =
                      last3.length >= 3 && last3.every((r) => r === "L");
                    const unbeaten =
                      form.length >= 4 && form.every((r) => r !== "L");
                    return (
                      <div className="flex flex-col items-center gap-1.5 mt-1">
                        <div className="flex gap-1.5">
                          {form.map((res, i) => (
                            <span
                              key={i}
                              className={`w-6 h-6 rounded flex items-center justify-center text-[10px] font-heading font-bold text-white ${
                                res === "W"
                                  ? "bg-green-500"
                                  : res === "L"
                                    ? "bg-red-500"
                                    : "bg-gray-400"
                              }`}
                            >
                              {res}
                            </span>
                          ))}
                        </div>
                        {winStreak && (
                          <span className="text-[10px] font-heading font-bold text-green-500 uppercase tracking-wider">
                            {t("home.winningStreak")}
                          </span>
                        )}
                        {loseStreak && (
                          <span className="text-[10px] font-heading font-bold text-red-500 uppercase tracking-wider">
                            {t("home.losingStreak")}
                          </span>
                        )}
                        {!winStreak && !loseStreak && unbeaten && (
                          <span className="text-[10px] font-heading font-bold text-primary-500 uppercase tracking-wider">
                            {t("home.unbeatenRun")}
                          </span>
                        )}
                      </div>
                    );
                  })()}
              </div>
            ) : (
              <div className="flex flex-col items-center gap-2 py-4">
                <Trophy className="w-8 h-8 text-gray-300 dark:text-navy-600" />
                <p className="text-xs text-gray-500 dark:text-gray-400">
                  {t("home.noLeague")}
                </p>
              </div>
            )}
          </CardBody>
        </Card>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
        <HomeNextOpponentCard
          nextOpponent={nextOpponent}
          lang={lang}
          onNavigate={onNavigate}
        />

        <HomeLeagueDigestCard
          articles={leagueDigestArticles}
          lang={lang}
          onNavigate={onNavigate}
        />
      </div>

      {/* Board Objectives */}
      {boardObjectives.length > 0 && (
        <Card>
          <CardHeader>
            {t("manager.boardStatus", "Board Objectives")}
          </CardHeader>
          <CardBody>
            <div className="flex flex-col gap-2.5">
              {boardObjectives.map((obj) => (
                <div key={obj.id} className="flex items-center gap-3">
                  {obj.met ? (
                    <CheckCircle2 className="w-4 h-4 text-green-500 flex-shrink-0" />
                  ) : (
                    <Circle className="w-4 h-4 text-gray-300 dark:text-navy-600 flex-shrink-0" />
                  )}
                  <span
                    className={`text-sm ${obj.met ? "text-green-600 dark:text-green-400 line-through" : "text-gray-700 dark:text-gray-300"}`}
                  >
                    {obj.description}
                  </span>
                  <Badge
                    variant={obj.met ? "success" : "neutral"}
                    size="sm"
                    className="ml-auto"
                  >
                    {obj.met ? t("home.met") : t("home.inProgress")}
                  </Badge>
                </div>
              ))}
            </div>
            <div className="mt-3 pt-2 border-t border-gray-100 dark:border-navy-700">
              <p className="text-[10px] text-gray-400 dark:text-gray-500">
                {t("home.objectivesMet", {
                  done: boardObjectives.filter((o) => o.met).length,
                  total: boardObjectives.length,
                  pct: gameState.manager.satisfaction,
                })}
              </p>
            </div>
          </CardBody>
        </Card>
      )}

      {unavailablePlayers.length > 0 && (
        <Card>
          <CardHeader
            action={
              <button
                onClick={() => onNavigate?.("Squad")}
                className="text-primary-500 dark:text-primary-400 text-xs font-heading font-bold uppercase tracking-wider hover:text-primary-600 dark:hover:text-primary-300 transition-colors"
              >
                {t("dashboard.squad")}
              </button>
            }
          >
            <div className="flex items-center gap-2">
              <AlertTriangle className="w-4 h-4 text-red-500" />
              {t("home.unavailablePlayers")}
            </div>
          </CardHeader>
          <CardBody>
            <div className="flex flex-col gap-2.5">
              {unavailablePlayers.map((player) => (
                <div
                  key={player.id}
                  className="flex flex-col gap-2 rounded-lg border border-gray-100 px-3 py-2.5 dark:border-navy-700 sm:flex-row sm:items-center sm:justify-between"
                >
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="truncate text-sm font-heading font-bold text-gray-800 dark:text-gray-200">
                        {player.full_name}
                      </span>
                      <Badge variant="danger" size="sm">
                        {t("common.injured")}
                      </Badge>
                    </div>
                    <p className="mt-1 text-xs text-gray-500 dark:text-gray-400">
                      {player.injury
                        ? resolveInjuryName(player.injury.name)
                        : ""}{" "}
                      ·{" "}
                      {t("home.daysUnavailable", {
                        count: player.injury?.days_remaining ?? 0,
                      })}
                    </p>
                  </div>
                  <div className="text-xs font-heading font-bold uppercase tracking-wider text-gray-400 dark:text-gray-500">
                    {t(`common.positions.${player.position}`, {
                      defaultValue: player.position,
                    })}
                  </div>
                </div>
              ))}
            </div>
          </CardBody>
        </Card>
      )}

      <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
        {/* Squad Fitness */}
        <Card>
          <CardHeader
            action={
              <button
                onClick={() => onNavigate?.("Training")}
                className="text-primary-500 dark:text-primary-400 text-xs font-heading font-bold uppercase tracking-wider hover:text-primary-600 dark:hover:text-primary-300 transition-colors"
              >
                {t("dashboard.training")}
              </button>
            }
          >
            {t("home.squadOverview")}
          </CardHeader>
          <CardBody>
            <div className="flex flex-col gap-3">
              <div className="flex items-center justify-between">
                <span className="text-xs text-gray-500 dark:text-gray-400">
                  {t("home.avgCondition")}
                </span>
                <span className="font-heading font-bold text-sm text-gray-800 dark:text-gray-100">
                  {avgCondition}%
                </span>
              </div>
              <ProgressBar value={avgCondition} variant="auto" size="md" />

              <div className="flex items-center justify-between mt-1">
                <span className="text-xs text-gray-500 dark:text-gray-400">
                  {t("home.avgOvr")}
                </span>
                <span className="font-heading font-bold text-sm text-gray-800 dark:text-gray-100">
                  {avgOvr}
                </span>
              </div>

              {exhaustedCount > 0 && (
                <div className="flex items-center gap-1.5 mt-1 text-amber-500 dark:text-amber-400">
                  <AlertTriangle className="w-3.5 h-3.5" />
                  <span className="text-xs font-heading">
                    {t("home.exhaustedPlayers", { count: exhaustedCount })}
                  </span>
                </div>
              )}

              <div className="mt-2 pt-2 border-t border-gray-100 dark:border-navy-700 flex items-center gap-2">
                <Dumbbell className="w-3.5 h-3.5 text-gray-400 dark:text-gray-500" />
                <span className="text-xs text-gray-500 dark:text-gray-400">
                  {t("home.scheduleLabel")}
                </span>
                <span
                  className={`text-xs font-heading font-bold flex items-center gap-1 ${schedIcons.color}`}
                >
                  {schedIcons.icon} {schedLabel}
                </span>
                <span className="text-xs text-gray-400 dark:text-gray-500 ml-auto">
                  {t(`common.trainingFocuses.${focus}`, focus)}
                </span>
              </div>
            </div>
          </CardBody>
        </Card>

        {/* Recent Results */}
        <Card>
          <CardHeader
            action={
              <button
                onClick={() => onNavigate?.("Schedule")}
                className="text-primary-500 dark:text-primary-400 text-xs font-heading font-bold uppercase tracking-wider hover:text-primary-600 dark:hover:text-primary-300 transition-colors"
              >
                {t("dashboard.schedule")}
              </button>
            }
          >
            {t("home.recentResults")}
          </CardHeader>
          <CardBody className="p-0">
            {recentResults.length === 0 ? (
              <p className="text-gray-500 dark:text-gray-400 text-xs p-5">
                {t("home.noMatches")}
              </p>
            ) : (
              <div className="divide-y divide-gray-100 dark:divide-navy-600">
                {recentResults
                  .slice(-5)
                  .reverse()
                  .map((result) => {
                    return (
                      <div
                        key={result.fixture.id}
                        className="flex items-center px-4 py-2.5 gap-3"
                      >
                        <span
                          className={`w-5 h-5 rounded flex items-center justify-center text-[9px] font-heading font-bold text-white flex-shrink-0 ${
                            result.resultCode === "W"
                              ? "bg-green-500"
                              : result.resultCode === "L"
                                ? "bg-red-500"
                                : "bg-gray-400"
                          }`}
                        >
                          {result.resultCode}
                        </span>
                        <span className="text-xs text-gray-500 dark:text-gray-400 flex-shrink-0 w-6">
                          {result.isHome
                            ? t("home.home").charAt(0)
                            : t("home.away").charAt(0)}
                        </span>
                        <span className="text-sm font-medium text-gray-800 dark:text-gray-200 flex-1 truncate">
                          {getTeamName(gameState.teams, result.opponentId)}
                        </span>
                        <span className="text-sm font-heading font-bold text-gray-700 dark:text-gray-300 tabular-nums">
                          {result.myGoals} – {result.opponentGoals}
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
              <button
                onClick={() => onNavigate?.("News")}
                className="text-primary-500 dark:text-primary-400 text-xs font-heading font-bold uppercase tracking-wider hover:text-primary-600 dark:hover:text-primary-300 transition-colors"
              >
                {t("home.allNews")}
              </button>
            }
          >
            {t("home.latestNews")}
          </CardHeader>
          <CardBody className="p-0">
            {latestNews.length === 0 ? (
              <div className="flex flex-col items-center gap-2 py-6">
                <Newspaper className="w-8 h-8 text-gray-300 dark:text-navy-600" />
                <p className="text-xs text-gray-500 dark:text-gray-400">
                  {t("home.noNews")}
                </p>
              </div>
            ) : (
              <div className="divide-y divide-gray-100 dark:divide-navy-600">
                {latestNews.map((article) => (
                  <button
                    key={article.id}
                    onClick={() => onNavigate?.("News")}
                    className="w-full text-left px-4 py-3 hover:bg-gray-50 dark:hover:bg-navy-700/50 transition-colors"
                  >
                    <p className="text-xs text-gray-400 dark:text-gray-500 mb-0.5">
                      {formatDateShort(article.date, lang)} · {article.source}
                    </p>
                    <p className="text-sm font-heading font-bold text-gray-800 dark:text-gray-200 leading-snug line-clamp-2">
                      {article.headline}
                    </p>
                    {article.match_score && (
                      <div className="flex items-center gap-1.5 mt-1">
                        <span className="text-[10px] text-gray-500 dark:text-gray-400">
                          {getTeamName(
                            gameState.teams,
                            article.match_score.home_team_id,
                          )}
                        </span>
                        <span className="text-[10px] font-heading font-bold text-primary-500">
                          {article.match_score.home_goals}–
                          {article.match_score.away_goals}
                        </span>
                        <span className="text-[10px] text-gray-500 dark:text-gray-400">
                          {getTeamName(
                            gameState.teams,
                            article.match_score.away_team_id,
                          )}
                        </span>
                      </div>
                    )}
                  </button>
                ))}
              </div>
            )}
          </CardBody>
        </Card>
      </div>

      {/* Player Momentum */}
      {roster.length > 0 && (hotPlayers.length > 0 || coldPlayers.length > 0) && (
        <Card>
          <CardHeader
            action={
              <button
                onClick={() => onNavigate?.("Squad")}
                className="text-primary-500 dark:text-primary-400 text-xs font-heading font-bold uppercase tracking-wider hover:text-primary-600 dark:hover:text-primary-300 transition-colors"
              >
                {t("dashboard.squad")}
              </button>
            }
          >
            {t("home.playerMomentum", "Player Momentum")}
          </CardHeader>
          <CardBody>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {hotPlayers.length > 0 && (
                <div>
                  <div className="flex items-center gap-1.5 mb-2">
                    <TrendingUp className="w-3.5 h-3.5 text-green-500" />
                    <span className="text-[10px] font-heading font-bold uppercase tracking-widest text-green-500">
                      {t("home.inForm")}
                    </span>
                  </div>
                  <div className="flex flex-col gap-1.5">
                    {hotPlayers.map((player) => (
                      <div
                        key={player.id}
                        className="flex items-center gap-2 px-2 py-1.5 rounded-lg bg-green-500/5 dark:bg-green-500/10"
                      >
                        <span className="text-xs font-medium text-gray-800 dark:text-gray-200 flex-1 truncate">
                          {player.full_name}
                        </span>
                        <Badge variant="success" size="sm">
                          {translatePositionAbbreviation(t, player.position)}
                        </Badge>
                        <span className="text-xs font-heading font-bold text-green-500 tabular-nums w-8 text-right">
                          {player.morale}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              )}
              {coldPlayers.length > 0 && (
                <div>
                  <div className="flex items-center gap-1.5 mb-2">
                    <TrendingDown className="w-3.5 h-3.5 text-red-500" />
                    <span className="text-[10px] font-heading font-bold uppercase tracking-widest text-red-500">
                      {t("home.lowMorale")}
                    </span>
                  </div>
                  <div className="flex flex-col gap-1.5">
                    {coldPlayers.map((player) => (
                      <div
                        key={player.id}
                        className="flex items-center gap-2 px-2 py-1.5 rounded-lg bg-red-500/5 dark:bg-red-500/10"
                      >
                        <span className="text-xs font-medium text-gray-800 dark:text-gray-200 flex-1 truncate">
                          {player.full_name}
                        </span>
                        <Badge variant="danger" size="sm">
                          {translatePositionAbbreviation(t, player.position)}
                        </Badge>
                        <span className="text-xs font-heading font-bold text-red-500 tabular-nums w-8 text-right">
                          {player.morale}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </CardBody>
        </Card>
      )}

      {/* Recent Messages */}
      <Card>
        <CardHeader
          action={
            <button
              onClick={() => onNavigate?.("Inbox")}
              className="text-primary-500 dark:text-primary-400 text-xs font-heading font-bold uppercase tracking-wider hover:text-primary-600 dark:hover:text-primary-300 transition-colors"
            >
              {t("home.viewAll")}
            </button>
          }
        >
          {t("home.recentMessages")}
        </CardHeader>
        <CardBody className="p-0">
          <div className="divide-y divide-gray-100 dark:divide-navy-600">
            {(gameState.messages || []).length === 0 ? (
              <p className="text-gray-500 dark:text-gray-400 p-6 text-sm">
                {t("home.noMessages")}
              </p>
            ) : (
              (gameState.messages || [])
                .slice(0, 4)
                .map(resolveMessage)
                .map((message) => (
                  <div
                    key={message.id}
                    onClick={() => onNavigate?.("Inbox", { messageId: message.id })}
                    className={`flex gap-4 px-6 py-3.5 hover:bg-gray-50 dark:hover:bg-navy-600/50 cursor-pointer transition-colors ${!message.read ? "border-l-4 border-l-primary-500" : "border-l-4 border-l-transparent"}`}
                  >
                    <div
                      className={`w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 font-heading font-bold text-sm ${
                        message.read
                          ? "bg-gray-100 dark:bg-navy-600 text-gray-400 dark:text-gray-500"
                          : "bg-primary-500/10 dark:bg-primary-500/20 text-primary-600 dark:text-primary-400"
                      }`}
                    >
                      {message.sender.charAt(0)}
                    </div>
                    <div className="min-w-0 flex-1">
                      <h4
                        className={`font-semibold text-sm ${message.read ? "text-gray-500 dark:text-gray-400" : "text-gray-900 dark:text-gray-100"}`}
                      >
                        {message.subject}
                      </h4>
                      <p
                        className={`text-xs truncate mt-0.5 ${message.read ? "text-gray-400 dark:text-gray-500" : "text-gray-600 dark:text-gray-300"}`}
                      >
                        {message.body}
                      </p>
                    </div>
                    <span className="text-[10px] text-gray-400 dark:text-gray-500 flex-shrink-0 mt-1">
                      {formatDateShort(message.date, lang)}
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
