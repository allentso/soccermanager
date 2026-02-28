import { GameStateData } from "../store/gameStore";
import { Card, CardHeader, CardBody, Badge, ProgressBar } from "./ui";
import { formatVal, positionBadgeVariant } from "../lib/helpers";

interface FinancesTabProps {
  gameState: GameStateData;
}

export default function FinancesTab({ gameState }: FinancesTabProps) {
  const myTeam = gameState.teams.find(t => t.id === gameState.manager.team_id);
  if (!myTeam) return <p className="text-gray-500 dark:text-gray-400">No team assigned.</p>;

  const roster = gameState.players.filter(p => p.team_id === myTeam.id);
  const totalWages = roster.reduce((s, p) => s + p.wage, 0);
  const totalValue = roster.reduce((s, p) => s + p.market_value, 0);

  const financeItems = [
    { label: "Club Balance", value: myTeam.finance, color: myTeam.finance >= 0 ? "text-primary-500" : "text-red-500" },
    { label: "Wage Budget", value: myTeam.wage_budget, color: "text-gray-800 dark:text-gray-200" },
    { label: "Transfer Budget", value: myTeam.transfer_budget, color: "text-gray-800 dark:text-gray-200" },
    { label: "Season Income", value: myTeam.season_income, color: "text-primary-500" },
    { label: "Season Expenses", value: myTeam.season_expenses, color: "text-red-500" },
  ];

  return (
    <div className="max-w-6xl mx-auto grid grid-cols-1 lg:grid-cols-3 gap-5">
      {/* Financial overview */}
      <Card accent="accent" className="lg:col-span-2">
        <CardHeader>Financial Overview</CardHeader>
        <CardBody>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
            {financeItems.map(item => (
              <div key={item.label} className="bg-gray-50 dark:bg-navy-800 rounded-xl p-4 text-center">
                <p className="text-xs font-heading font-bold uppercase tracking-wider text-gray-400 dark:text-gray-500 mb-1">{item.label}</p>
                <p className={`font-heading font-bold text-xl ${item.color}`}>{formatVal(item.value)}</p>
              </div>
            ))}
            <div className="bg-gray-50 dark:bg-navy-800 rounded-xl p-4 text-center">
              <p className="text-xs font-heading font-bold uppercase tracking-wider text-gray-400 dark:text-gray-500 mb-1">Squad Value</p>
              <p className="font-heading font-bold text-xl text-gray-800 dark:text-gray-200">{formatVal(totalValue)}</p>
            </div>
          </div>
        </CardBody>
      </Card>

      {/* Wage summary */}
      <Card>
        <CardHeader>Wage Bill</CardHeader>
        <CardBody>
          <div className="text-center mb-4">
            <p className="text-xs font-heading font-bold uppercase tracking-wider text-gray-400 dark:text-gray-500">Weekly Total</p>
            <p className="font-heading font-bold text-2xl text-gray-800 dark:text-gray-100 mt-1">{formatVal(totalWages)}/wk</p>
            <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">
              Budget: {formatVal(myTeam.wage_budget)}/wk — {totalWages <= myTeam.wage_budget
                ? <span className="text-primary-500">Under budget</span>
                : <span className="text-red-500">Over budget!</span>
              }
            </p>
          </div>
          <ProgressBar
            value={Math.min(100, Math.round((totalWages / Math.max(1, myTeam.wage_budget)) * 100))}
            variant={totalWages <= myTeam.wage_budget ? "success" : "danger"}
            size="md"
            showLabel
          />
        </CardBody>
      </Card>

      {/* Payroll */}
      <Card className="lg:col-span-3">
        <CardHeader>Payroll — Top Earners</CardHeader>
        <CardBody className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Player</th>
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Position</th>
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Wage/wk</th>
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Market Value</th>
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Contract</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                {[...roster].sort((a, b) => b.wage - a.wage).slice(0, 10).map(p => (
                  <tr key={p.id} className="hover:bg-gray-50 dark:hover:bg-navy-700/50 transition-colors">
                    <td className="py-3 px-5 font-semibold text-sm text-gray-800 dark:text-gray-200">{p.full_name}</td>
                    <td className="py-3 px-5"><Badge variant={positionBadgeVariant(p.position)}>{p.position.substring(0, 3).toUpperCase()}</Badge></td>
                    <td className="py-3 px-5 text-sm font-medium text-gray-700 dark:text-gray-300">€{p.wage.toLocaleString()}</td>
                    <td className="py-3 px-5 text-sm text-gray-600 dark:text-gray-400">{formatVal(p.market_value)}</td>
                    <td className="py-3 px-5 text-sm text-gray-500 dark:text-gray-400">{p.contract_end ? `Until ${p.contract_end.substring(0, 4)}` : "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </CardBody>
      </Card>
    </div>
  );
}
