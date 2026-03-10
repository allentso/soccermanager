import type { GameStateData, MessageData } from "../store/gameStore";

const DEFAULT_FORMATION = "4-4-2";
const DEFAULT_TRAINING_FOCUS = "Physical";
const DEFAULT_TRAINING_INTENSITY = "Medium";
const DEFAULT_TRAINING_SCHEDULE = "Balanced";
const ONBOARDING_VISIBLE_DAYS = 7;

export interface OnboardingCompletionState {
  completedSteps: number;
  hasConfiguredTraining: boolean;
  hasHiredCoreStaff: boolean;
  hasReadInbox: boolean;
  hasReviewedSquad: boolean;
  hasSetTactics: boolean;
  showOnboarding: boolean;
}

function isOnboardingMessage(message: MessageData): boolean {
  return message.category === "Welcome" || message.category === "LeagueInfo";
}

export function getOnboardingCompletionState(
  gameState: GameStateData,
): OnboardingCompletionState {
  const currentDate = new Date(gameState.clock.current_date);
  const startDate = new Date(gameState.clock.start_date);
  const daysSinceStart = Math.floor(
    (currentDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24),
  );
  const showOnboarding = daysSinceStart <= ONBOARDING_VISIBLE_DAYS;
  const myTeam = gameState.teams.find(
    (team) => team.id === gameState.manager.team_id,
  );
  const myStaff = myTeam
    ? gameState.staff.filter((staffMember) => staffMember.team_id === myTeam.id)
    : [];
  const onboardingMessages = gameState.messages.filter(isOnboardingMessage);
  const welcomeMessages = onboardingMessages.filter(
    (message) => message.category === "Welcome",
  );
  const hasCoach = myStaff.some((staffMember) => staffMember.role === "Coach");
  const hasPhysio = myStaff.some((staffMember) => staffMember.role === "Physio");
  const hasReviewedSquad =
    welcomeMessages.some((message) => message.read) ||
    (myTeam?.starting_xi_ids.length ?? 0) > 0;
  const hasSetTactics = myTeam ? myTeam.formation !== DEFAULT_FORMATION : false;
  const hasConfiguredTraining = myTeam
    ? myTeam.training_focus !== DEFAULT_TRAINING_FOCUS ||
      myTeam.training_intensity !== DEFAULT_TRAINING_INTENSITY ||
      myTeam.training_schedule !== DEFAULT_TRAINING_SCHEDULE
    : false;
  const hasReadInbox =
    onboardingMessages.length > 0 &&
    onboardingMessages.every((message) => message.read);
  const completedSteps = [
    hasReviewedSquad,
    hasCoach && hasPhysio,
    hasSetTactics,
    hasConfiguredTraining,
    hasReadInbox,
  ].filter(Boolean).length;

  return {
    completedSteps,
    hasConfiguredTraining,
    hasHiredCoreStaff: hasCoach && hasPhysio,
    hasReadInbox,
    hasReviewedSquad,
    hasSetTactics,
    showOnboarding,
  };
}
