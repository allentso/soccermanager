import { GameStateData } from "../store/gameStore";
import { Card, CardHeader, CardBody, ProgressBar } from "./ui";

interface ManagerTabProps {
  gameState: GameStateData;
}

export default function ManagerTab({ gameState }: ManagerTabProps) {
  const mgr = gameState.manager;
  const myTeam = gameState.teams.find(t => t.id === mgr.team_id);
  const stats = mgr.career_stats;

  return (
    <div className="max-w-4xl mx-auto grid grid-cols-1 md:grid-cols-3 gap-5">
      {/* Profile card */}
      <Card accent="primary" className="md:col-span-3">
        <div className="bg-gradient-to-r from-navy-700 to-navy-800 p-6 rounded-t-xl flex items-center gap-6">
          <div className="w-20 h-20 rounded-xl bg-primary-500/20 flex items-center justify-center font-heading font-bold text-3xl text-primary-400 border-2 border-primary-500/30">
            {mgr.first_name.charAt(0)}{mgr.last_name.charAt(0)}
          </div>
          <div>
            <h2 className="text-2xl font-heading font-bold text-white uppercase tracking-wide">{mgr.first_name} {mgr.last_name}</h2>
            <p className="text-gray-400 text-sm mt-1">{mgr.nationality} • Born {new Date(mgr.date_of_birth).toLocaleDateString()}</p>
            {myTeam && <p className="text-primary-400 text-sm font-semibold mt-0.5">Manager of {myTeam.name}</p>}
          </div>
          <div className="ml-auto text-right">
            <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">Reputation</p>
            <p className="font-heading font-bold text-2xl text-accent-400">{mgr.reputation}</p>
          </div>
        </div>
      </Card>

      {/* Career stats */}
      <Card accent="accent" className="md:col-span-2">
        <CardHeader>Career Statistics</CardHeader>
        <CardBody>
          <div className="grid grid-cols-3 md:grid-cols-6 gap-3">
            <StatBlock label="Matches" value={stats.matches_managed} />
            <StatBlock label="Wins" value={stats.wins} />
            <StatBlock label="Draws" value={stats.draws} />
            <StatBlock label="Losses" value={stats.losses} />
            <StatBlock label="Trophies" value={stats.trophies} />
            <StatBlock label="Win %" value={stats.matches_managed > 0 ? `${(stats.wins / stats.matches_managed * 100).toFixed(0)}%` : "—"} />
          </div>
        </CardBody>
      </Card>

      {/* Board satisfaction */}
      <Card>
        <CardHeader>Board Status</CardHeader>
        <CardBody>
          <div className="text-center mb-3">
            <p className="font-heading font-bold text-4xl text-gray-800 dark:text-gray-100">{mgr.satisfaction}%</p>
            <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase tracking-wider mt-1">Satisfaction</p>
          </div>
          <ProgressBar value={mgr.satisfaction} variant="auto" size="lg" />
          <p className="text-xs text-gray-400 dark:text-gray-500 text-center mt-3">
            {mgr.satisfaction >= 80 ? "The board is very pleased with your work." :
             mgr.satisfaction >= 50 ? "The board is satisfied with your performance." :
             mgr.satisfaction >= 30 ? "The board has concerns about results." :
             "Your position is under serious threat."}
          </p>
        </CardBody>
      </Card>

      {/* Career history */}
      {mgr.career_history.length > 0 && (
        <Card className="md:col-span-3">
          <CardHeader>Career History</CardHeader>
          <CardBody className="p-0">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Club</th>
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Period</th>
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">P</th>
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">W</th>
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">D</th>
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">L</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                {mgr.career_history.map((entry, i) => (
                  <tr key={i}>
                    <td className="py-3 px-5 font-semibold text-sm text-gray-800 dark:text-gray-200">{entry.team_name}</td>
                    <td className="py-3 px-5 text-sm text-gray-500 dark:text-gray-400">{entry.start_date.substring(0, 4)} — {entry.end_date?.substring(0, 4) || "Present"}</td>
                    <td className="py-3 px-5 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.matches}</td>
                    <td className="py-3 px-5 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.wins}</td>
                    <td className="py-3 px-5 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.draws}</td>
                    <td className="py-3 px-5 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{entry.losses}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </CardBody>
        </Card>
      )}
    </div>
  );
}

function StatBlock({ label, value }: { label: string; value: number | string }) {
  return (
    <div className="text-center p-3 bg-gray-50 dark:bg-navy-700 rounded-lg">
      <p className="font-heading font-bold text-xl text-gray-800 dark:text-gray-100 tabular-nums">{value}</p>
      <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase tracking-wider mt-0.5">{label}</p>
    </div>
  );
}
