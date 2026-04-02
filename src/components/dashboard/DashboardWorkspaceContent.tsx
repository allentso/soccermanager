import type { GameStateData } from "../../store/gameStore";
import PlayerProfile from "../playerProfile/PlayerProfile";
import TeamProfile from "../TeamProfile";
import DashboardAlerts from "./DashboardAlerts";
import type { DashboardAlert } from "./dashboardHelpers";
import type { DashboardProfileNavigationState } from "./dashboardProfileNavigation";
import DashboardTabContent from "./DashboardTabContent";
import type { DashboardTabContentModel } from "./dashboardTabContentModel";

interface DashboardWorkspaceContentProps {
  dashboardAlerts: DashboardAlert[];
  gameState: GameStateData;
  profileNavigation: DashboardProfileNavigationState;
  dashboardTabContentModel: DashboardTabContentModel;
  onBack: () => void;
  onNavigate: (tab: string) => void;
  onSelectPlayer: (id: string) => void;
  onSelectTeam: (id: string) => void;
  onGameUpdate: (state: GameStateData) => void;
}

export default function DashboardWorkspaceContent({
  dashboardAlerts,
  gameState,
  profileNavigation,
  dashboardTabContentModel,
  onBack,
  onNavigate,
  onSelectPlayer,
  onSelectTeam,
  onGameUpdate,
}: DashboardWorkspaceContentProps) {
  const selectedPlayer = profileNavigation.selectedPlayerId
    ? gameState.players.find(
      (player) => player.id === profileNavigation.selectedPlayerId,
    ) ?? null
    : null;
  const selectedTeam = profileNavigation.selectedTeamId
    ? gameState.teams.find((team) => team.id === profileNavigation.selectedTeamId) ??
      null
    : null;

  return (
    <div className="flex-1 overflow-auto p-6 bg-gray-100 dark:bg-navy-900">
      {!selectedPlayer && !selectedTeam ? (
        <DashboardAlerts alerts={dashboardAlerts} onNavigate={onNavigate} />
      ) : null}

      {selectedPlayer && !selectedTeam ? (
        <PlayerProfile
          player={selectedPlayer}
          gameState={gameState}
          isOwnClub={selectedPlayer.team_id === gameState.manager.team_id}
          startWithRenewalModal={
            profileNavigation.selectedPlayerOptions?.openRenewal === true
          }
          onClose={onBack}
          onSelectTeam={onSelectTeam}
          onGameUpdate={onGameUpdate}
        />
      ) : null}

      {selectedTeam ? (
        <TeamProfile
          team={selectedTeam}
          gameState={gameState}
          isOwnTeam={selectedTeam.id === gameState.manager.team_id}
          onClose={onBack}
          onSelectPlayer={onSelectPlayer}
        />
      ) : null}

      {!selectedPlayer && !selectedTeam ? (
        <DashboardTabContent viewModel={dashboardTabContentModel} />
      ) : null}
    </div>
  );
}