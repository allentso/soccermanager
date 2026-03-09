import type {
  FixtureData,
  GameStateData,
  PlayerData,
  TeamData,
} from "../../store/gameStore";

export interface DashboardAlert {
  id: string;
  text: string;
  tab: string;
  severity: "warn" | "info";
}

export interface DashboardSearchResults {
  matchedPlayers: PlayerData[];
  matchedTeams: TeamData[];
}

export function getTodayMatchFixture(gameState: GameStateData): FixtureData | null {
  const fixtures = gameState.league?.fixtures;

  if (!fixtures) {
    return null;
  }

  const today = gameState.clock.current_date.split("T")[0];

  return (
    fixtures.find((fixture) => {
      return (
        fixture.date === today &&
        fixture.status === "Scheduled" &&
        (fixture.home_team_id === gameState.manager.team_id ||
          fixture.away_team_id === gameState.manager.team_id)
      );
    }) ?? null
  );
}

export function getUnreadMessagesCount(gameState: GameStateData): number {
  return gameState.messages.filter((message) => !message.read).length;
}

export function getManagerTeamName(gameState: GameStateData): string | null {
  return (
    gameState.teams.find((team) => team.id === gameState.manager.team_id)?.name ??
    null
  );
}

export function getPlayerBadgeVariant(
  position: string,
): "accent" | "danger" | "primary" | "success" {
  switch (position) {
    case "Goalkeeper":
      return "accent";
    case "Defender":
      return "primary";
    case "Midfielder":
      return "success";
    default:
      return "danger";
  }
}

export function getDashboardSearchResults(
  gameState: GameStateData,
  query: string,
): DashboardSearchResults {
  const normalizedQuery = query.trim().toLowerCase();

  if (normalizedQuery.length < 2) {
    return {
      matchedPlayers: [],
      matchedTeams: [],
    };
  }

  return {
    matchedPlayers: gameState.players
      .filter((player) => {
        return (
          player.full_name.toLowerCase().includes(normalizedQuery) ||
          player.match_name.toLowerCase().includes(normalizedQuery)
        );
      })
      .slice(0, 5),
    matchedTeams: gameState.teams
      .filter((team) => {
        return (
          team.name.toLowerCase().includes(normalizedQuery) ||
          team.short_name.toLowerCase().includes(normalizedQuery)
        );
      })
      .slice(0, 4),
  };
}

export function getDashboardAlerts(
  gameState: GameStateData,
  hasMatchToday: boolean,
): DashboardAlert[] {
  const alerts: DashboardAlert[] = [];
  const myTeam = gameState.teams.find(
    (team) => team.id === gameState.manager.team_id,
  );
  const roster = myTeam
    ? gameState.players.filter((player) => player.team_id === myTeam.id)
    : [];
  const exhaustedCount = roster.filter((player) => player.condition < 25).length;
  const injuredCount = roster.filter((player) => player.injury).length;
  const urgentUnreadCount = gameState.messages.filter((message) => {
    return !message.read && message.priority === "Urgent";
  }).length;
  const startingXi = myTeam?.starting_xi_ids ?? [];
  const xiPlayersOnRoster = startingXi.filter((playerId) => {
    return roster.some((player) => player.id === playerId);
  });
  const injuredInXiCount = xiPlayersOnRoster.filter((playerId) => {
    return roster.find((player) => player.id === playerId)?.injury;
  }).length;
  const healthyXiCount = xiPlayersOnRoster.length - injuredInXiCount;

  if (exhaustedCount >= 3) {
    alerts.push({
      id: "exhausted",
      text: `${exhaustedCount} players in critical condition (<25%)`,
      tab: "Training",
      severity: "warn",
    });
  }

  if (injuredCount >= 2) {
    alerts.push({
      id: "injured",
      text: `${injuredCount} players injured`,
      tab: "Squad",
      severity: "info",
    });
  }

  if (startingXi.length > 0) {
    if (injuredInXiCount > 0) {
      const suffix = injuredInXiCount > 1 ? "s" : "";

      alerts.push({
        id: "injured_xi",
        text: `${injuredInXiCount} injured player${suffix} in Starting XI — replace them`,
        tab: "Squad",
        severity: "warn",
      });
    }

    if (
      healthyXiCount < 11 &&
      injuredInXiCount === 0 &&
      roster.length >= 11
    ) {
      alerts.push({
        id: "xi",
        text: "Starting XI incomplete — set your lineup",
        tab: "Squad",
        severity: "warn",
      });
    }
  }

  if (urgentUnreadCount > 0) {
    const suffix = urgentUnreadCount > 1 ? "s" : "";

    alerts.push({
      id: "urgent",
      text: `${urgentUnreadCount} urgent message${suffix} unread`,
      tab: "Inbox",
      severity: "warn",
    });
  }

  if (hasMatchToday && startingXi.length > 0 && healthyXiCount < 11) {
    alerts.push({
      id: "matchxi",
      text: "Match today! Set your starting XI",
      tab: "Squad",
      severity: "warn",
    });
  }

  return alerts;
}
