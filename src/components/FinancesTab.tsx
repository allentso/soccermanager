import { GameStateData } from "../store/gameStore";
import { Card, CardHeader, CardBody, Badge, ProgressBar } from "./ui";
import {
  formatVal,
  formatWeeklyAmount,
  positionBadgeVariant,
} from "../lib/helpers";
import { useTranslation } from "react-i18next";
import { translatePositionAbbreviation } from "./SquadTab.helpers";

interface FinancesTabProps {
  gameState: GameStateData;
}

export default function FinancesTab({ gameState }: FinancesTabProps) {
  const { t } = useTranslation();
  const myTeam = gameState.teams.find(
    (tm) => tm.id === gameState.manager.team_id,
  );
  if (!myTeam)
    return (
      <p className="text-gray-500 dark:text-gray-400">{t("common.noTeam")}</p>
    );
  const weeklySuffix = t("finances.perWeekSuffix", "/wk");

  const roster = gameState.players.filter((p) => p.team_id === myTeam.id);
  const totalWages = roster.reduce((s, p) => s + p.wage, 0);
  const totalValue = roster.reduce((s, p) => s + p.market_value, 0);

  const financeItems = [
    {
      label: t("finances.clubBalance"),
      value: myTeam.finance,
      color: myTeam.finance >= 0 ? "text-primary-500" : "text-red-500",
    },
    {
      label: t("finances.wageBudget"),
      value: myTeam.wage_budget,
      color: "text-gray-800 dark:text-gray-200",
    },
    {
      label: t("finances.transferBudget"),
      value: myTeam.transfer_budget,
      color: "text-gray-800 dark:text-gray-200",
    },
    {
      label: t("finances.seasonIncome"),
      value: myTeam.season_income,
      color: "text-primary-500",
    },
    {
      label: t("finances.seasonExpenses"),
      value: myTeam.season_expenses,
      color: "text-red-500",
    },
  ];

  return (
    <div className="max-w-6xl mx-auto grid grid-cols-1 lg:grid-cols-3 gap-5">
      {/* Financial overview */}
      <Card accent="accent" className="lg:col-span-2">
        <CardHeader>{t("finances.overview")}</CardHeader>
        <CardBody>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
            {financeItems.map((item) => (
              <div
                key={item.label}
                className="bg-gray-50 dark:bg-navy-800 rounded-xl p-4 text-center"
              >
                <p className="text-xs font-heading font-bold uppercase tracking-wider text-gray-400 dark:text-gray-500 mb-1">
                  {item.label}
                </p>
                <p className={`font-heading font-bold text-xl ${item.color}`}>
                  {formatVal(item.value)}
                </p>
              </div>
            ))}
            <div className="bg-gray-50 dark:bg-navy-800 rounded-xl p-4 text-center">
              <p className="text-xs font-heading font-bold uppercase tracking-wider text-gray-400 dark:text-gray-500 mb-1">
                {t("finances.squadValue")}
              </p>
              <p className="font-heading font-bold text-xl text-gray-800 dark:text-gray-200">
                {formatVal(totalValue)}
              </p>
            </div>
          </div>
        </CardBody>
      </Card>

      {/* Wage summary */}
      <Card>
        <CardHeader>{t("finances.wageBill")}</CardHeader>
        <CardBody>
          <div className="text-center mb-4">
            <p className="text-xs font-heading font-bold uppercase tracking-wider text-gray-400 dark:text-gray-500">
              {t("finances.weeklyTotal")}
            </p>
            <p className="font-heading font-bold text-2xl text-gray-800 dark:text-gray-100 mt-1">
              {formatWeeklyAmount(formatVal(totalWages), weeklySuffix)}
            </p>
            <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">
              {t("finances.budget")}:{" "}
              {formatWeeklyAmount(formatVal(myTeam.wage_budget), weeklySuffix)}{" "}
              —{" "}
              {totalWages <= myTeam.wage_budget ? (
                <span className="text-primary-500">
                  {t("finances.underBudget")}
                </span>
              ) : (
                <span className="text-red-500">{t("finances.overBudget")}</span>
              )}
            </p>
          </div>
          <ProgressBar
            value={Math.min(
              100,
              Math.round((totalWages / Math.max(1, myTeam.wage_budget)) * 100),
            )}
            variant={totalWages <= myTeam.wage_budget ? "success" : "danger"}
            size="md"
            showLabel
          />
        </CardBody>
      </Card>

      {/* Payroll */}
      <Card className="lg:col-span-3">
        <CardHeader>{t("finances.payroll")}</CardHeader>
        <CardBody className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                    {t("common.player")}
                  </th>
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                    {t("common.position")}
                  </th>
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                    {t("finances.wagePerWeek")}
                  </th>
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                    {t("finances.marketValue")}
                  </th>
                  <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                    {t("common.contract")}
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                {[...roster]
                  .sort((a, b) => b.wage - a.wage)
                  .slice(0, 10)
                  .map((p) => (
                    <tr
                      key={p.id}
                      className="hover:bg-gray-50 dark:hover:bg-navy-700/50 transition-colors"
                    >
                      <td className="py-3 px-5 font-semibold text-sm text-gray-800 dark:text-gray-200">
                        {p.full_name}
                      </td>
                      <td className="py-3 px-5">
                        <Badge variant={positionBadgeVariant(p.position)}>
                          {translatePositionAbbreviation(t, p.position)}
                        </Badge>
                      </td>
                      <td className="py-3 px-5 text-sm font-medium text-gray-700 dark:text-gray-300">
                        €{p.wage.toLocaleString()}
                      </td>
                      <td className="py-3 px-5 text-sm text-gray-600 dark:text-gray-400">
                        {formatVal(p.market_value)}
                      </td>
                      <td className="py-3 px-5 text-sm text-gray-500 dark:text-gray-400">
                        {p.contract_end
                          ? t("finances.until", {
                              year: p.contract_end.substring(0, 4),
                            })
                          : "—"}
                      </td>
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
