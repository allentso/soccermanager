import { useTranslation } from "react-i18next";
import { PlayerData } from "../store/gameStore";
import { Card, Badge } from "./ui";
import { GitCompareArrows } from "lucide-react";
import { positionBadgeVariant, calcOvr, calcAge } from "../lib/helpers";

const ATTR_GROUPS: { label: string; attrs: { key: keyof PlayerData["attributes"]; label: string }[] }[] = [
  {
    label: "Physical",
    attrs: [
      { key: "pace", label: "Pace" },
      { key: "stamina", label: "Stamina" },
      { key: "strength", label: "Strength" },
      { key: "agility", label: "Agility" },
    ],
  },
  {
    label: "Technical",
    attrs: [
      { key: "passing", label: "Passing" },
      { key: "shooting", label: "Shooting" },
      { key: "dribbling", label: "Dribbling" },
      { key: "tackling", label: "Tackling" },
    ],
  },
  {
    label: "Mental",
    attrs: [
      { key: "positioning", label: "Positioning" },
      { key: "vision", label: "Vision" },
      { key: "decisions", label: "Decisions" },
      { key: "composure", label: "Composure" },
      { key: "teamwork", label: "Teamwork" },
      { key: "leadership", label: "Leadership" },
      { key: "aggression", label: "Aggression" },
    ],
  },
  {
    label: "Goalkeeping",
    attrs: [
      { key: "handling", label: "Handling" },
      { key: "reflexes", label: "Reflexes" },
      { key: "aerial", label: "Aerial" },
    ],
  },
];

export default function CompareView({
  roster, compareA, compareB, setCompareA, setCompareB,
}: {
  roster: PlayerData[];
  compareA: string | null;
  compareB: string | null;
  setCompareA: (id: string | null) => void;
  setCompareB: (id: string | null) => void;
}) {
  const { t } = useTranslation();
  const playerA = roster.find(p => p.id === compareA) || null;
  const playerB = roster.find(p => p.id === compareB) || null;

  const renderSelector = (value: string | null, onChange: (id: string | null) => void, otherId: string | null) => (
    <select
      value={value || ""}
      onChange={e => onChange(e.target.value || null)}
      className="w-full text-sm font-heading font-bold bg-gray-100 dark:bg-navy-700 text-gray-700 dark:text-gray-200 border-0 rounded-lg px-3 py-2.5 focus:ring-2 focus:ring-primary-500"
    >
      <option value="">{t('squadCompare.selectPlayerA')}...</option>
      {roster.filter(p => p.id !== otherId).map(p => (
        <option key={p.id} value={p.id}>
          {p.full_name} ({p.position.substring(0, 3)}, OVR {calcOvr(p)})
        </option>
      ))}
    </select>
  );

  const attrColor = (val: number) =>
    val >= 80 ? "text-success-500" : val >= 65 ? "text-primary-500" : val >= 50 ? "text-accent-500" : "text-gray-400";

  const barColor = (val: number) =>
    val >= 80 ? "bg-success-500" : val >= 65 ? "bg-primary-500" : val >= 50 ? "bg-accent-500" : "bg-gray-300 dark:bg-navy-600";

  const betterClass = "ring-2 ring-primary-500/30 bg-primary-500/5";

  return (
    <Card>
      <div className="p-4 border-b border-gray-100 dark:border-navy-600 bg-gradient-to-r from-navy-700 to-navy-800 rounded-t-xl">
        <h3 className="text-sm font-heading font-bold text-white uppercase tracking-wide flex items-center gap-2">
          <GitCompareArrows className="w-4 h-4 text-accent-400" />
          {t('squadCompare.compare')}
        </h3>
      </div>
      <div className="p-4">
        {/* Player selectors */}
        <div className="grid grid-cols-2 gap-4 mb-6">
          <div>
            <label className="text-[10px] font-heading font-bold uppercase tracking-widest text-gray-400 mb-1.5 block">{t('squadCompare.selectPlayerA')}</label>
            {renderSelector(compareA, setCompareA, compareB)}
          </div>
          <div>
            <label className="text-[10px] font-heading font-bold uppercase tracking-widest text-gray-400 mb-1.5 block">{t('squadCompare.selectPlayerB')}</label>
            {renderSelector(compareB, setCompareB, compareA)}
          </div>
        </div>

        {playerA && playerB ? (
          <>
            {/* Summary header */}
            <div className="grid grid-cols-[1fr_auto_1fr] gap-4 mb-6 items-center">
              <div className="text-center">
                <p className="font-heading font-bold text-gray-900 dark:text-white">{playerA.full_name}</p>
                <div className="flex items-center justify-center gap-2 mt-1">
                  <Badge variant={positionBadgeVariant(playerA.position)} size="sm">{playerA.position.substring(0, 3).toUpperCase()}</Badge>
                  <span className="text-xs text-gray-500">{calcAge(playerA.date_of_birth)} yrs</span>
                  <span className="font-heading font-bold text-lg text-primary-500">{calcOvr(playerA)}</span>
                </div>
              </div>
              <div className="text-gray-300 dark:text-navy-600 text-2xl font-heading font-bold">VS</div>
              <div className="text-center">
                <p className="font-heading font-bold text-gray-900 dark:text-white">{playerB.full_name}</p>
                <div className="flex items-center justify-center gap-2 mt-1">
                  <Badge variant={positionBadgeVariant(playerB.position)} size="sm">{playerB.position.substring(0, 3).toUpperCase()}</Badge>
                  <span className="text-xs text-gray-500">{calcAge(playerB.date_of_birth)} yrs</span>
                  <span className="font-heading font-bold text-lg text-primary-500">{calcOvr(playerB)}</span>
                </div>
              </div>
            </div>

            {/* Attribute groups */}
            <div className="flex flex-col gap-5">
              {ATTR_GROUPS.map(group => {
                const isGK = group.label === "Goalkeeping";
                const aIsGK = playerA.position === "Goalkeeper";
                const bIsGK = playerB.position === "Goalkeeper";
                if (isGK && !aIsGK && !bIsGK) return null;

                return (
                  <div key={group.label}>
                    <h4 className="text-[10px] font-heading font-bold uppercase tracking-widest text-gray-400 dark:text-gray-500 mb-2">{group.label}</h4>
                    <div className="flex flex-col gap-1.5">
                      {group.attrs.map(attr => {
                        const valA = playerA.attributes[attr.key];
                        const valB = playerB.attributes[attr.key];
                        const aWins = valA > valB;
                        const bWins = valB > valA;
                        return (
                          <div key={attr.key} className="grid grid-cols-[1fr_100px_1fr] gap-2 items-center">
                            {/* Player A bar (right-aligned) */}
                            <div className={`flex items-center justify-end gap-2 px-2 py-1 rounded-lg ${aWins ? betterClass : ""}`}>
                              <span className={`text-xs font-heading font-bold tabular-nums ${attrColor(valA)}`}>{valA}</span>
                              <div className="w-24 h-2 rounded-full bg-gray-100 dark:bg-navy-700 overflow-hidden flex justify-end">
                                <div className={`h-full rounded-full ${barColor(valA)}`} style={{ width: `${valA}%` }} />
                              </div>
                            </div>
                            {/* Label center */}
                            <div className="text-center text-[10px] font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                              {attr.label}
                            </div>
                            {/* Player B bar (left-aligned) */}
                            <div className={`flex items-center gap-2 px-2 py-1 rounded-lg ${bWins ? betterClass : ""}`}>
                              <div className="w-24 h-2 rounded-full bg-gray-100 dark:bg-navy-700 overflow-hidden">
                                <div className={`h-full rounded-full ${barColor(valB)}`} style={{ width: `${valB}%` }} />
                              </div>
                              <span className={`text-xs font-heading font-bold tabular-nums ${attrColor(valB)}`}>{valB}</span>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Stats comparison */}
            <div className="mt-6 pt-4 border-t border-gray-100 dark:border-navy-700">
              <h4 className="text-[10px] font-heading font-bold uppercase tracking-widest text-gray-400 dark:text-gray-500 mb-3">{t('squadCompare.seasonStats')}</h4>
              <div className="grid grid-cols-[1fr_100px_1fr] gap-2 text-xs">
                {([
                  ["appearances", "Apps"],
                  ["goals", "Goals"],
                  ["assists", "Assists"],
                  ["yellow_cards", "Yellows"],
                  ["red_cards", "Reds"],
                ] as [keyof PlayerData["stats"], string][]).map(([key, label]) => {
                  const vA = playerA.stats[key] as number;
                  const vB = playerB.stats[key] as number;
                  return (
                    <div key={key} className="contents">
                      <div className="text-right font-heading font-bold text-gray-700 dark:text-gray-300">{vA}</div>
                      <div className="text-center text-[10px] font-heading font-bold uppercase tracking-wider text-gray-400">{label}</div>
                      <div className="text-left font-heading font-bold text-gray-700 dark:text-gray-300">{vB}</div>
                    </div>
                  );
                })}
              </div>
            </div>
          </>
        ) : (
          <div className="text-center py-12">
            <GitCompareArrows className="w-10 h-10 text-gray-300 dark:text-navy-600 mx-auto mb-3" />
            <p className="text-sm text-gray-500 dark:text-gray-400">{t('squadCompare.noPlayersSelected')}</p>
          </div>
        )}
      </div>
    </Card>
  );
}
