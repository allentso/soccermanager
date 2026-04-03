import type { GameStateData, PlayerData, TeamData } from "../store/gameStore";
import { calcOvr } from "../lib/helpers";

const POSITION_ORDER: Record<string, number> = {
  Goalkeeper: 1,
  Defender: 2,
  Midfielder: 3,
  Forward: 4,
};

export interface TeamProfileViewModel {
  roster: PlayerData[];
  avgOvr: number;
  totalWages: number;
  totalValue: number;
  manager: GameStateData["manager"] | null;
  leaguePos: number;
  standings: GameStateData["league"] extends infer League
    ? League extends { standings: infer Standings }
      ? Standings extends Array<infer Standing>
        ? Standing | null
        : null
      : null
    : null;
}

export function buildTeamProfileViewModel(
  team: TeamData,
  gameState: GameStateData,
): TeamProfileViewModel {
  const roster = gameState.players
    .filter((player) => player.team_id === team.id)
    .sort((leftPlayer, rightPlayer) => {
      return (
        (POSITION_ORDER[leftPlayer.position] || 99) -
        (POSITION_ORDER[rightPlayer.position] || 99)
      );
    });

  const avgOvr =
    roster.length > 0
      ? Math.round(
          roster.reduce((sum, player) => {
            return sum + calcOvr(player, player.natural_position || player.position);
          }, 0) / roster.length,
        )
      : 0;

  const totalWages = roster.reduce((sum, player) => sum + player.wage, 0);
  const totalValue = roster.reduce(
    (sum, player) => sum + player.market_value,
    0,
  );

  const manager = gameState.manager.team_id === team.id ? gameState.manager : null;

  const allStandings = gameState.league?.standings
    ? [...gameState.league.standings].sort(
        (leftEntry, rightEntry) =>
          rightEntry.points - leftEntry.points ||
          rightEntry.goals_for -
            rightEntry.goals_against -
            (leftEntry.goals_for - leftEntry.goals_against) ||
          rightEntry.goals_for - leftEntry.goals_for,
      )
    : [];
  const leaguePos = allStandings.findIndex((entry) => entry.team_id === team.id) + 1;
  const standings =
    gameState.league?.standings.find((entry) => entry.team_id === team.id) ?? null;

  return {
    roster,
    avgOvr,
    totalWages,
    totalValue,
    manager,
    leaguePos,
    standings,
  };
}