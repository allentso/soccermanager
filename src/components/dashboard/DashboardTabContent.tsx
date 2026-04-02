import HomeTab from "../HomeTab";
import SquadTab from "../SquadTab";
import TacticsTab from "../TacticsTab";
import TrainingTab from "../TrainingTab";
import ScheduleTab from "../ScheduleTab";
import FinancesTab from "../FinancesTab";
import TransfersTab from "../TransfersTab";
import PlayersListTab from "../PlayersListTab";
import TeamsListTab from "../TeamsListTab";
import TournamentsTab from "../TournamentsTab";
import ScoutingTab from "../ScoutingTab";
import YouthAcademyTab from "../YouthAcademyTab";
import StaffTab from "../StaffTab";
import InboxTab from "../InboxTab";
import ManagerTab from "../ManagerTab";
import NewsTab from "../NewsTab";
import EndOfSeasonScreen from "../EndOfSeasonScreen";
import type { DashboardTabContentModel } from "./dashboardTabContentModel";

interface DashboardTabContentProps {
  viewModel: DashboardTabContentModel;
}

export default function DashboardTabContent({
  viewModel,
}: DashboardTabContentProps) {
  const {
    activeTab,
    gameState,
    initialMessageId,
    managerId,
    seasonComplete,
    visitedOnboardingTabs,
    handlers: {
      onGameUpdate,
      onNavigate,
      onSelectPlayer,
      onSelectTeam,
    },
  } = viewModel;

  return (
    <>
      {/* End-of-season screen when all fixtures are complete */}
      {seasonComplete && activeTab === "Home" && (
        <EndOfSeasonScreen gameState={gameState} onGameUpdate={onGameUpdate} />
      )}

      {activeTab === "Home" && !seasonComplete && (
        <HomeTab
          gameState={gameState}
          onNavigate={onNavigate}
          visitedOnboardingTabs={visitedOnboardingTabs}
        />
      )}

      {activeTab === "Squad" && (
        <SquadTab
          gameState={gameState}
          managerId={managerId}
          onSelectPlayer={onSelectPlayer}
          onGameUpdate={onGameUpdate}
        />
      )}

      {activeTab === "Tactics" && (
        <TacticsTab
          gameState={gameState}
          onSelectPlayer={onSelectPlayer}
          onGameUpdate={onGameUpdate}
        />
      )}

      {activeTab === "Training" && (
        <TrainingTab gameState={gameState} onGameUpdate={onGameUpdate} />
      )}

      {activeTab === "Schedule" && (
        <ScheduleTab gameState={gameState} onSelectTeam={onSelectTeam} />
      )}

      {activeTab === "Finances" && (
        <FinancesTab
          gameState={gameState}
          onGameUpdate={onGameUpdate}
          onSelectPlayer={onSelectPlayer}
        />
      )}

      {activeTab === "Transfers" && (
        <TransfersTab
          gameState={gameState}
          onSelectPlayer={onSelectPlayer}
          onSelectTeam={onSelectTeam}
          onGameUpdate={onGameUpdate}
        />
      )}

      {activeTab === "Players" && (
        <PlayersListTab
          gameState={gameState}
          onSelectPlayer={onSelectPlayer}
          onSelectTeam={onSelectTeam}
        />
      )}

      {activeTab === "Teams" && (
        <TeamsListTab gameState={gameState} onSelectTeam={onSelectTeam} />
      )}

      {activeTab === "Tournaments" && (
        <TournamentsTab gameState={gameState} onSelectTeam={onSelectTeam} />
      )}

      {activeTab === "Staff" && (
        <StaffTab gameState={gameState} onGameUpdate={onGameUpdate} />
      )}

      {activeTab === "Scouting" && (
        <ScoutingTab
          gameState={gameState}
          onGameUpdate={onGameUpdate}
          onSelectPlayer={onSelectPlayer}
        />
      )}

      {activeTab === "Youth" && (
        <YouthAcademyTab
          gameState={gameState}
          onSelectPlayer={onSelectPlayer}
        />
      )}

      {activeTab === "Inbox" && (
        <InboxTab
          gameState={gameState}
          onGameUpdate={onGameUpdate}
          initialMessageId={initialMessageId}
          onNavigate={onNavigate}
        />
      )}

      {activeTab === "Manager" && <ManagerTab gameState={gameState} />}

      {activeTab === "News" && (
        <NewsTab gameState={gameState} onSelectTeam={onSelectTeam} />
      )}
    </>
  );
}
