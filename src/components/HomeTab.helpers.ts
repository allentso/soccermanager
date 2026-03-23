import { findNextFixture } from "../lib/helpers";
import type {
  FixtureData,
  GameStateData,
  NewsArticle,
  TeamData,
} from "../store/gameStore";

const ONBOARDING_VISIBLE_DAYS = 7;
const ONBOARDING_PAGE_TABS = new Set(["Squad", "Staff", "Tactics", "Training"]);
const ONBOARDING_STORAGE_KEY_PREFIX = "ofm-onboarding-visited-tabs";

interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

export interface OnboardingCompletionState {
  completedSteps: number;
  hasReadInbox: boolean;
  hasVisitedSquadPage: boolean;
  hasVisitedStaffPage: boolean;
  hasVisitedTacticsPage: boolean;
  hasVisitedTrainingPage: boolean;
  showOnboarding: boolean;
}

export interface NextOpponentWidgetData {
  fixture: FixtureData;
  isHome: boolean;
  opponent: TeamData;
  recentForm: string[];
  standingPoints: number | null;
  standingPosition: number | null;
}

function getStandingPosition(
  gameState: GameStateData,
  teamId: string,
): number | null {
  const league = gameState.league;

  if (!league) {
    return null;
  }

  const sortedStandings = [...league.standings].sort((leftEntry, rightEntry) => {
    return (
      rightEntry.points - leftEntry.points ||
      rightEntry.goals_for -
        rightEntry.goals_against -
        (leftEntry.goals_for - leftEntry.goals_against)
    );
  });
  const standingIndex = sortedStandings.findIndex(
    (entry) => entry.team_id === teamId,
  );

  if (standingIndex === -1) {
    return null;
  }

  return standingIndex + 1;
}

export function getNextOpponentWidgetData(
  gameState: GameStateData,
): NextOpponentWidgetData | null {
  const league = gameState.league;
  const userTeamId = gameState.manager.team_id;

  if (!league || !userTeamId) {
    return null;
  }

  const nextFixture = findNextFixture(league.fixtures, userTeamId);

  if (!nextFixture) {
    return null;
  }

  const isHome = nextFixture.home_team_id === userTeamId;
  const opponentId = isHome ? nextFixture.away_team_id : nextFixture.home_team_id;
  const opponent = gameState.teams.find((team) => team.id === opponentId);

  if (!opponent) {
    return null;
  }

  const standingEntry = league.standings.find((entry) => entry.team_id === opponentId);

  return {
    fixture: nextFixture,
    isHome,
    opponent,
    recentForm: opponent.form.slice(-5),
    standingPoints: standingEntry?.points ?? null,
    standingPosition: getStandingPosition(gameState, opponentId),
  };
}

export function getLeagueDigestArticles(
  gameState: GameStateData,
): NewsArticle[] {
  return [...(gameState.news || [])]
    .filter((article) => {
      return (
        article.category === "LeagueRoundup" ||
        article.category === "StandingsUpdate"
      );
    })
    .sort((leftArticle, rightArticle) => {
      return rightArticle.date.localeCompare(leftArticle.date);
    })
    .slice(0, 2);
}

export function isOnboardingPageTab(tab: string): boolean {
  return ONBOARDING_PAGE_TABS.has(tab);
}

function getOnboardingStorageKey(gameState: GameStateData): string {
  return `${ONBOARDING_STORAGE_KEY_PREFIX}:${gameState.manager.id}:${gameState.clock.start_date}`;
}

function getDefaultStorage(): StorageLike | null {
  if (typeof window === "undefined") {
    return null;
  }

  return window.localStorage;
}

export function loadVisitedOnboardingTabs(
  gameState: GameStateData,
  storage: StorageLike | null = getDefaultStorage(),
): Set<string> {
  if (!storage) {
    return new Set<string>();
  }

  const storedValue = storage.getItem(getOnboardingStorageKey(gameState));

  if (!storedValue) {
    return new Set<string>();
  }

  try {
    const parsedValue: unknown = JSON.parse(storedValue);

    if (!Array.isArray(parsedValue)) {
      return new Set<string>();
    }

    return new Set<string>(
      parsedValue.filter(
        (tab): tab is string => typeof tab === "string" && isOnboardingPageTab(tab),
      ),
    );
  } catch {
    return new Set<string>();
  }
}

export function saveVisitedOnboardingTabs(
  gameState: GameStateData,
  visitedTabs: ReadonlySet<string>,
  storage: StorageLike | null = getDefaultStorage(),
): void {
  if (!storage) {
    return;
  }

  const persistedTabs = Array.from(visitedTabs).filter((tab) =>
    isOnboardingPageTab(tab),
  );

  storage.setItem(
    getOnboardingStorageKey(gameState),
    JSON.stringify(persistedTabs),
  );
}

export function getOnboardingCompletionState(
  gameState: GameStateData,
  visitedTabs: ReadonlySet<string> = new Set<string>(),
): OnboardingCompletionState {
  const currentDate = new Date(gameState.clock.current_date);
  const startDate = new Date(gameState.clock.start_date);
  const daysSinceStart = Math.floor(
    (currentDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24),
  );
  const showOnboarding = daysSinceStart <= ONBOARDING_VISIBLE_DAYS;
  const hasVisitedSquadPage = visitedTabs.has("Squad");
  const hasVisitedStaffPage = visitedTabs.has("Staff");
  const hasVisitedTacticsPage = visitedTabs.has("Tactics");
  const hasVisitedTrainingPage = visitedTabs.has("Training");
  const hasReadInbox = gameState.messages.some((message) => message.read);
  const completedSteps = [
    hasVisitedSquadPage,
    hasVisitedStaffPage,
    hasVisitedTacticsPage,
    hasVisitedTrainingPage,
    hasReadInbox,
  ].filter(Boolean).length;

  return {
    completedSteps,
    hasReadInbox,
    hasVisitedSquadPage,
    hasVisitedStaffPage,
    hasVisitedTacticsPage,
    hasVisitedTrainingPage,
    showOnboarding,
  };
}
