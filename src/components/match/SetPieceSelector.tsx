import { useState } from "react";
import { useTranslation } from "react-i18next";
import { PlayerData } from "../../store/gameStore";
import { Badge } from "../ui";
import { ArrowUpDown, Check } from "lucide-react";

export function getSetPieceStats(
  role: string,
  p: PlayerData,
): { score: number; stats: { label: string; value: number }[] } {
  const a = p.attributes;
  switch (role) {
    case "penalty":
      return {
        score: Math.round((a.shooting + a.composure) / 2),
        stats: [
          { label: "SHO", value: a.shooting },
          { label: "COM", value: a.composure },
        ],
      };
    case "freekick":
      return {
        score: Math.round((a.passing + a.vision + a.shooting / 2) / 2.5),
        stats: [
          { label: "PAS", value: a.passing },
          { label: "VIS", value: a.vision },
          { label: "SHO", value: a.shooting },
        ],
      };
    case "corner":
      return {
        score: Math.round((a.passing + a.vision) / 2),
        stats: [
          { label: "PAS", value: a.passing },
          { label: "VIS", value: a.vision },
        ],
      };
    case "captain":
    case "vicecaptain":
      return {
        score: Math.round((a.leadership + a.teamwork) / 2),
        stats: [
          { label: "LDR", value: a.leadership },
          { label: "TMW", value: a.teamwork },
        ],
      };
    default:
      return { score: 0, stats: [] };
  }
}

function roleAllowsGoalkeeper(role: string): boolean {
  return role === "captain" || role === "vicecaptain";
}

export default function SetPieceSelector({
  label,
  icon,
  role,
  currentId,
  players,
  allSquad,
  onSelect,
}: {
  label: string;
  icon: React.ReactNode;
  role: string;
  currentId: string | null;
  players: { id: string; name: string; position: string }[];
  allSquad: PlayerData[];
  onSelect: (id: string) => void;
}) {
  const { t } = useTranslation();
  const [expanded, setExpanded] = useState(false);
  const currentPlayer = players.find((p) => p.id === currentId);
  const currentSquad = allSquad.find((sp) => sp.id === currentId);
  const currentStats = currentSquad
    ? getSetPieceStats(role, currentSquad)
    : null;

  const sortedPlayers = [...players]
    .filter((p) => roleAllowsGoalkeeper(role) || p.position !== "Goalkeeper")
    .map((p) => {
      const squad = allSquad.find((sp) => sp.id === p.id);
      const spStats = squad
        ? getSetPieceStats(role, squad)
        : { score: 0, stats: [] };
      return { ...p, squad, spStats };
    })
    .sort(
      (a, b) =>
        b.spStats.score - a.spStats.score || a.name.localeCompare(b.name),
    );

  return (
    <div className="mb-4 last:mb-0">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center gap-3 p-3 rounded-lg bg-navy-700/50 hover:bg-navy-700 transition-colors"
      >
        {icon}
        <div className="flex-1 text-left">
          <p className="text-xs font-heading font-bold uppercase tracking-widest text-gray-400">
            {label}
          </p>
          <p className="text-sm text-gray-200 font-medium">
            {currentPlayer ? currentPlayer.name : t("match.notAssigned")}
          </p>
        </div>
        {currentStats && (
          <div className="flex items-center gap-1">
            {currentStats.stats.map((s) => (
              <span
                key={s.label}
                className="text-[10px] font-heading text-gray-500"
              >
                <span className="text-gray-600">{s.label}</span>{" "}
                <span
                  className={
                    s.value >= 70
                      ? "text-primary-400"
                      : s.value >= 50
                        ? "text-gray-300"
                        : "text-gray-500"
                  }
                >
                  {s.value}
                </span>
              </span>
            ))}
          </div>
        )}
        <ArrowUpDown className="w-4 h-4 text-gray-500" />
      </button>

      {expanded && (
        <div className="mt-1 bg-navy-700 rounded-lg p-2 flex flex-col gap-1 max-h-56 overflow-auto">
          {sortedPlayers.map((p) => {
            const isCurrent = p.id === currentId;
            return (
              <button
                key={p.id}
                onClick={() => {
                  onSelect(p.id);
                  setExpanded(false);
                }}
                className={`flex items-center gap-2 px-3 py-1.5 rounded text-left transition-colors ${
                  isCurrent
                    ? "bg-primary-500/20 text-primary-400"
                    : "hover:bg-navy-600 text-gray-300"
                }`}
              >
                {isCurrent && <Check className="w-3 h-3 text-primary-400" />}
                <span className="text-sm font-medium flex-1 truncate">
                  {p.name}
                </span>
                <Badge variant="neutral" size="sm">
                  {t(`common.posAbbr.${p.position}`, {
                    defaultValue: p.position.substring(0, 3),
                  })}
                </Badge>
                {p.spStats.stats.map((s) => (
                  <span
                    key={s.label}
                    className="text-[10px] font-heading w-7 text-center"
                  >
                    <span
                      className={
                        s.value >= 70
                          ? "text-primary-400 font-bold"
                          : s.value >= 50
                            ? "text-gray-300"
                            : "text-gray-500"
                      }
                    >
                      {s.value}
                    </span>
                  </span>
                ))}
                <span
                  className={`text-xs font-heading font-bold w-6 text-right ${
                    p.spStats.score >= 70
                      ? "text-primary-400"
                      : p.spStats.score >= 50
                        ? "text-gray-300"
                        : "text-gray-500"
                  }`}
                >
                  {p.spStats.score}
                </span>
              </button>
            );
          })}
          {/* Column headers */}
          {sortedPlayers.length > 0 && (
            <div className="flex items-center gap-2 px-3 py-1 text-[9px] font-heading uppercase tracking-widest text-gray-600 border-t border-navy-600 mt-1 pt-1">
              <span className="flex-1" />
              <span className="w-8" />
              {sortedPlayers[0].spStats.stats.map((s) => (
                <span key={s.label} className="w-7 text-center">
                  {s.label}
                </span>
              ))}
              <span className="w-6 text-right">{t("match.fit")}</span>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
