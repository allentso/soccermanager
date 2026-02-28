import { useState } from "react";
import { GameStateData, FixtureData } from "../store/gameStore";
import { Card, CardHeader, CardBody, Badge } from "./ui";
import { Trophy, Calendar, TableProperties } from "lucide-react";
import { getTeamName, formatMatchDate } from "../lib/helpers";

interface TournamentsTabProps {
  gameState: GameStateData;
  onSelectTeam: (id: string) => void;
}

export default function TournamentsTab({ gameState, onSelectTeam }: TournamentsTabProps) {
  const league = gameState.league;
  const userTeamId = gameState.manager.team_id;
  const [view, setView] = useState<"overview" | "fixtures" | "standings">("overview");

  if (!league) {
    return (
      <div className="max-w-4xl mx-auto text-center py-12">
        <Trophy className="w-12 h-12 text-gray-300 dark:text-navy-600 mx-auto mb-3" />
        <p className="text-gray-500 dark:text-gray-400 text-sm">No active tournaments.</p>
      </div>
    );
  }

  const standings = [...league.standings].sort((a, b) =>
    b.points - a.points || (b.goals_for - b.goals_against) - (a.goals_for - a.goals_against) || b.goals_for - a.goals_for
  );

  const matchdays = new Map<number, FixtureData[]>();
  league.fixtures.forEach(f => {
    const list = matchdays.get(f.matchday) || [];
    list.push(f);
    matchdays.set(f.matchday, list);
  });
  const sortedMatchdays = Array.from(matchdays.entries()).sort((a, b) => a[0] - b[0]);

  const completedMatchdays = sortedMatchdays.filter(([, fixtures]) => fixtures.every(f => f.status === "Completed")).length;
  const totalMatchdays = sortedMatchdays.length;
  const totalGoals = league.fixtures
    .filter(f => f.result)
    .reduce((s, f) => s + (f.result!.home_goals + f.result!.away_goals), 0);
  const completedMatches = league.fixtures.filter(f => f.status === "Completed").length;

  const topScorers = (() => {
    const goals: Record<string, number> = {};
    league.fixtures.forEach(f => {
      if (f.result) {
        f.result.home_scorers.forEach(s => { goals[s.player_id] = (goals[s.player_id] || 0) + 1; });
        f.result.away_scorers.forEach(s => { goals[s.player_id] = (goals[s.player_id] || 0) + 1; });
      }
    });
    return Object.entries(goals)
      .map(([pid, g]) => ({ player: gameState.players.find(p => p.id === pid), goals: g }))
      .filter(e => e.player)
      .sort((a, b) => b.goals - a.goals)
      .slice(0, 10);
  })();

  return (
    <div className="max-w-6xl mx-auto">
      {/* League header */}
      <Card accent="primary" className="mb-5">
        <div className="bg-gradient-to-r from-navy-700 to-navy-800 p-6 rounded-t-xl">
          <div className="flex items-center gap-4">
            <div className="w-14 h-14 rounded-xl bg-accent-500/20 flex items-center justify-center">
              <Trophy className="w-7 h-7 text-accent-400" />
            </div>
            <div className="flex-1">
              <h2 className="text-2xl font-heading font-bold text-white uppercase tracking-wide">{league.name}</h2>
              <p className="text-gray-400 text-sm mt-0.5">Season {league.season} — {league.standings.length} teams</p>
            </div>
            <div className="hidden md:flex gap-4">
              <div className="bg-white/5 rounded-xl px-4 py-2 text-center">
                <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">Progress</p>
                <p className="font-heading font-bold text-lg text-white">{completedMatchdays}/{totalMatchdays}</p>
              </div>
              <div className="bg-white/5 rounded-xl px-4 py-2 text-center">
                <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">Matches</p>
                <p className="font-heading font-bold text-lg text-white">{completedMatches}</p>
              </div>
              <div className="bg-white/5 rounded-xl px-4 py-2 text-center">
                <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">Goals</p>
                <p className="font-heading font-bold text-lg text-accent-400">{totalGoals}</p>
              </div>
            </div>
          </div>
        </div>
      </Card>

      {/* Tab switcher */}
      <div className="flex gap-2 mb-5">
        {(["overview", "standings", "fixtures"] as const).map(v => (
          <button
            key={v}
            onClick={() => setView(v)}
            className={`px-4 py-2 rounded-lg font-heading font-bold text-sm uppercase tracking-wider transition-all ${
              view === v
                ? "bg-primary-500 text-white shadow-md shadow-primary-500/20"
                : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 border border-gray-200 dark:border-navy-600"
            }`}
          >
            {v === "overview" ? <><Trophy className="w-4 h-4 inline mr-1.5 -mt-0.5" />Overview</> :
             v === "standings" ? <><TableProperties className="w-4 h-4 inline mr-1.5 -mt-0.5" />Standings</> :
             <><Calendar className="w-4 h-4 inline mr-1.5 -mt-0.5" />Fixtures</>}
          </button>
        ))}
      </div>

      {/* Overview */}
      {view === "overview" && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
          {/* Mini standings */}
          <Card className="lg:col-span-2">
            <CardHeader>League Table</CardHeader>
            <CardBody className="p-0">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
                    <th className="py-2 px-3 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 w-8">#</th>
                    <th className="py-2 px-3 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Team</th>
                    <th className="py-2 px-3 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">P</th>
                    <th className="py-2 px-3 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">W</th>
                    <th className="py-2 px-3 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">D</th>
                    <th className="py-2 px-3 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">L</th>
                    <th className="py-2 px-3 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">GD</th>
                    <th className="py-2 px-3 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">Pts</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                  {standings.map((entry, idx) => {
                    const isUser = entry.team_id === userTeamId;
                    const gd = entry.goals_for - entry.goals_against;
                    return (
                      <tr key={entry.team_id} onClick={() => onSelectTeam(entry.team_id)} className={`cursor-pointer transition-colors ${isUser ? "bg-primary-50 dark:bg-primary-500/10" : "hover:bg-gray-50 dark:hover:bg-navy-700/50"}`}>
                        <td className="py-2 px-3 font-heading font-bold text-sm text-gray-400">{idx + 1}</td>
                        <td className={`py-2 px-3 font-semibold text-sm ${isUser ? "text-primary-600 dark:text-primary-400" : "text-gray-800 dark:text-gray-200"}`}>{getTeamName(gameState.teams, entry.team_id)}</td>
                        <td className="py-2 px-3 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.played}</td>
                        <td className="py-2 px-3 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.won}</td>
                        <td className="py-2 px-3 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.drawn}</td>
                        <td className="py-2 px-3 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.lost}</td>
                        <td className={`py-2 px-3 text-center text-sm font-semibold tabular-nums ${gd > 0 ? "text-primary-500" : gd < 0 ? "text-red-500" : "text-gray-500"}`}>{gd > 0 ? `+${gd}` : gd}</td>
                        <td className="py-2 px-3 text-center font-heading font-bold text-sm text-gray-800 dark:text-gray-100 tabular-nums">{entry.points}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </CardBody>
          </Card>

          {/* Top scorers */}
          <Card>
            <CardHeader>Top Scorers</CardHeader>
            <CardBody className="p-0">
              {topScorers.length === 0 ? (
                <p className="p-4 text-sm text-gray-400 dark:text-gray-500 text-center">No goals scored yet.</p>
              ) : (
                <div className="divide-y divide-gray-100 dark:divide-navy-600">
                  {topScorers.map((entry, i) => (
                    <div key={entry.player!.id} className="flex items-center px-4 py-2.5 gap-3">
                      <span className="font-heading font-bold text-sm text-gray-400 dark:text-gray-500 w-5 text-center">{i + 1}</span>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-semibold text-gray-800 dark:text-gray-200 truncate">{entry.player!.full_name}</p>
                        <p className="text-xs text-gray-400 dark:text-gray-500">{getTeamName(gameState.teams, entry.player!.team_id ?? "")}</p>
                      </div>
                      <span className="font-heading font-bold text-lg text-accent-500 tabular-nums">{entry.goals}</span>
                    </div>
                  ))}
                </div>
              )}
            </CardBody>
          </Card>
        </div>
      )}

      {/* Full standings */}
      {view === "standings" && (
        <Card>
          <div className="p-5 border-b border-gray-100 dark:border-navy-600 bg-gradient-to-r from-navy-700 to-navy-800 rounded-t-xl">
            <h3 className="text-lg font-heading font-bold text-white flex items-center gap-2 uppercase tracking-wide">
              <Trophy className="text-accent-400 w-5 h-5" />
              {league.name} — Season {league.season}
            </h3>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
                  <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 w-8">#</th>
                  <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Team</th>
                  <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">P</th>
                  <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">W</th>
                  <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">D</th>
                  <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">L</th>
                  <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">GF</th>
                  <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">GA</th>
                  <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">GD</th>
                  <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">Pts</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                {standings.map((entry, idx) => {
                  const isUser = entry.team_id === userTeamId;
                  const gd = entry.goals_for - entry.goals_against;
                  return (
                    <tr key={entry.team_id} onClick={() => onSelectTeam(entry.team_id)} className={`cursor-pointer transition-colors ${isUser ? "bg-primary-50 dark:bg-primary-500/10" : "hover:bg-gray-50 dark:hover:bg-navy-700/50"}`}>
                      <td className="py-3 px-4 font-heading font-bold text-sm text-gray-400">{idx + 1}</td>
                      <td className={`py-3 px-4 font-semibold text-sm ${isUser ? "text-primary-600 dark:text-primary-400" : "text-gray-800 dark:text-gray-200"}`}>{getTeamName(gameState.teams, entry.team_id)}</td>
                      <td className="py-3 px-4 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.played}</td>
                      <td className="py-3 px-4 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.won}</td>
                      <td className="py-3 px-4 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.drawn}</td>
                      <td className="py-3 px-4 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.lost}</td>
                      <td className="py-3 px-4 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.goals_for}</td>
                      <td className="py-3 px-4 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.goals_against}</td>
                      <td className={`py-3 px-4 text-center text-sm font-semibold tabular-nums ${gd > 0 ? "text-primary-500" : gd < 0 ? "text-red-500" : "text-gray-500"}`}>{gd > 0 ? `+${gd}` : gd}</td>
                      <td className="py-3 px-4 text-center font-heading font-bold text-sm text-gray-800 dark:text-gray-100 tabular-nums">{entry.points}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {/* Fixtures */}
      {view === "fixtures" && (
        <div className="flex flex-col gap-4">
          {sortedMatchdays.map(([md, fixtures]) => (
            <Card key={md}>
              <div className="px-5 py-3 border-b border-gray-100 dark:border-navy-600 bg-gray-50 dark:bg-navy-800 rounded-t-xl">
                <h4 className="font-heading font-bold text-sm uppercase tracking-wider text-gray-600 dark:text-gray-300">
                  Matchday {md} — {formatMatchDate(fixtures[0].date)}
                </h4>
              </div>
              <CardBody className="p-0">
                <div className="divide-y divide-gray-100 dark:divide-navy-600">
                  {fixtures.map(f => {
                    const isUserMatch = f.home_team_id === userTeamId || f.away_team_id === userTeamId;
                    const completed = f.status === "Completed";
                    return (
                      <div key={f.id} className={`flex items-center px-5 py-3 transition-colors ${isUserMatch ? "bg-primary-50/50 dark:bg-primary-500/5" : ""}`}>
                        <span onClick={() => onSelectTeam(f.home_team_id)} className={`flex-1 text-right font-semibold text-sm cursor-pointer hover:underline ${f.home_team_id === userTeamId ? "text-primary-600 dark:text-primary-400" : "text-gray-800 dark:text-gray-200"}`}>
                          {getTeamName(gameState.teams, f.home_team_id)}
                        </span>
                        <div className="w-24 text-center mx-3">
                          {completed && f.result ? (
                            <span className="font-heading font-bold text-lg text-gray-800 dark:text-gray-100">
                              {f.result.home_goals} - {f.result.away_goals}
                            </span>
                          ) : (
                            <Badge variant="neutral" size="sm">vs</Badge>
                          )}
                        </div>
                        <span onClick={() => onSelectTeam(f.away_team_id)} className={`flex-1 text-left font-semibold text-sm cursor-pointer hover:underline ${f.away_team_id === userTeamId ? "text-primary-600 dark:text-primary-400" : "text-gray-800 dark:text-gray-200"}`}>
                          {getTeamName(gameState.teams, f.away_team_id)}
                        </span>
                      </div>
                    );
                  })}
                </div>
              </CardBody>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
