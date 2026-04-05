import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { invoke } from "@tauri-apps/api/core";
import { useTranslation } from "react-i18next";
import { useGameStore } from "../store/gameStore";
import { Card, CardBody } from "../components/ui";
import { ShieldX, ArrowRight } from "lucide-react";

export default function Sacked() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { gameState, clearGame } = useGameStore();
  const [exiting, setExiting] = useState(false);

  const manager = gameState?.manager;
  const stats = manager?.career_stats;

  // Get team name from the last career history entry (team_id is already null)
  const lastEntry = manager?.career_history?.length
    ? manager.career_history[manager.career_history.length - 1]
    : null;
  const teamName = lastEntry?.team_name || "";

  const handleReturn = async () => {
    setExiting(true);
    try {
      await invoke("exit_to_menu");
    } catch {
      // Ignore — game state may already be cleared
    }
    clearGame();
    navigate("/");
  };

  const winRate = stats && stats.matches_managed > 0
    ? ((stats.wins / stats.matches_managed) * 100).toFixed(1)
    : "0.0";

  const posLabel = (pos: number) => {
    if (pos === 1) return "1st";
    if (pos === 2) return "2nd";
    if (pos === 3) return "3rd";
    return `${pos}th`;
  };

  return (
    <div className="min-h-screen bg-gray-100 dark:bg-navy-900 flex items-center justify-center p-4">
      <div className="max-w-2xl w-full">
        {/* Header */}
        <div className="text-center mb-8">
          <div className="w-20 h-20 mx-auto rounded-2xl bg-gradient-to-br from-red-600 to-red-800 flex items-center justify-center mb-4 shadow-lg shadow-red-600/30">
            <ShieldX className="w-10 h-10 text-white" />
          </div>
          <h1 className="text-3xl font-heading font-bold text-gray-900 dark:text-gray-100 uppercase tracking-wide">
            {t("sacked.title")}
          </h1>
          <p className="text-lg text-gray-500 dark:text-gray-400 mt-2">
            {t("sacked.subtitle")}
          </p>
          {teamName && (
            <p className="text-sm text-gray-400 dark:text-gray-500 mt-1">
              {t("sacked.teamLabel")}: <span className="font-semibold text-gray-600 dark:text-gray-300">{teamName}</span>
            </p>
          )}
        </div>

        {/* Career Stats */}
        {stats && (
          <Card className="mb-6">
            <CardBody>
              <h3 className="font-heading font-bold text-sm uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-4">
                {t("sacked.careerOverview")}
              </h3>
              <div className="grid grid-cols-3 gap-4 text-center">
                <div>
                  <p className="text-2xl font-heading font-bold text-gray-900 dark:text-gray-100">{stats.matches_managed}</p>
                  <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">{t("sacked.matchesManaged")}</p>
                </div>
                <div>
                  <p className="text-2xl font-heading font-bold text-green-500">{stats.wins}</p>
                  <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">{t("sacked.wins")}</p>
                </div>
                <div>
                  <p className="text-2xl font-heading font-bold text-gray-500">{stats.draws}</p>
                  <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">{t("sacked.draws")}</p>
                </div>
                <div>
                  <p className="text-2xl font-heading font-bold text-red-500">{stats.losses}</p>
                  <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">{t("sacked.losses")}</p>
                </div>
                <div>
                  <p className="text-2xl font-heading font-bold text-primary-500">{winRate}%</p>
                  <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">{t("sacked.winRate")}</p>
                </div>
                <div>
                  <p className="text-2xl font-heading font-bold text-accent-500">
                    {stats.best_finish ? posLabel(stats.best_finish) : "-"}
                  </p>
                  <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase">{t("sacked.bestFinish")}</p>
                </div>
              </div>
            </CardBody>
          </Card>
        )}

        {/* Career History */}
        {manager?.career_history && manager.career_history.length > 0 && (
          <Card className="mb-8">
            <CardBody>
              <h3 className="font-heading font-bold text-sm uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-3">
                {t("sacked.careerHistory")}
              </h3>
              <div className="divide-y divide-gray-100 dark:divide-navy-600">
                {manager.career_history.map((entry, idx) => (
                  <div key={idx} className="flex items-center justify-between py-2.5">
                    <div>
                      <p className="text-sm font-semibold text-gray-800 dark:text-gray-200">{entry.team_name}</p>
                      <p className="text-xs text-gray-400 dark:text-gray-500">
                        {entry.start_date} — {entry.end_date || t("sacked.present")}
                      </p>
                    </div>
                    <div className="text-right text-xs text-gray-500 dark:text-gray-400 tabular-nums">
                      <span className="text-green-500 font-bold">{entry.wins}W</span>{" "}
                      <span>{entry.draws}D</span>{" "}
                      <span className="text-red-500 font-bold">{entry.losses}L</span>
                      {entry.best_league_position && (
                        <span className="ml-2 text-gray-400">Best: {posLabel(entry.best_league_position)}</span>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            </CardBody>
          </Card>
        )}

        {/* Return button */}
        <div className="text-center">
          <button
            onClick={handleReturn}
            disabled={exiting}
            className="px-8 py-4 bg-gray-700 dark:bg-navy-700 text-white rounded-xl font-heading font-bold text-lg uppercase tracking-wider hover:bg-gray-800 dark:hover:bg-navy-600 transition-all shadow-lg disabled:opacity-50 flex items-center gap-3 mx-auto"
          >
            {exiting ? "..." : t("sacked.returnToMenu")}
            <ArrowRight className="w-5 h-5" />
          </button>
        </div>
      </div>
    </div>
  );
}
