import { GameStateData } from "../store/gameStore";
import { Card, Badge, ProgressBar } from "./ui";
import { Star } from "lucide-react";
import { formatVal, positionBadgeVariant } from "../lib/helpers";
import { TraitList } from "./TraitBadge";

interface SquadTabProps {
  gameState: GameStateData;
  managerId: string;
  onSelectPlayer: (id: string) => void;
}

export default function SquadTab({ gameState, managerId, onSelectPlayer }: SquadTabProps) {
  const myTeam = gameState.teams.find(t => t.manager_id === managerId);
  if (!myTeam) return <p className="text-gray-500 dark:text-gray-400">You are currently unemployed.</p>;

  // Try to sort players by position
  const posOrder: Record<string, number> = { "Goalkeeper": 1, "Defender": 2, "Midfielder": 3, "Forward": 4 };
  const roster = gameState.players
    .filter(p => p.team_id === myTeam.id)
    .sort((a, b) => (posOrder[a.position] || 99) - (posOrder[b.position] || 99));

  return (
    <div className="max-w-6xl mx-auto">
      <Card>
        <div className="p-5 border-b border-gray-100 dark:border-navy-600 flex justify-between items-center bg-gradient-to-r from-navy-700 to-navy-800 dark:from-navy-700 dark:to-navy-800 rounded-t-xl">
          <div>
            <h3 className="text-lg font-heading font-bold text-white flex items-center gap-2 uppercase tracking-wide">
              <Star className="text-accent-400 w-5 h-5 fill-current" />
              {myTeam.name} Squad
            </h3>
            <p className="text-xs text-gray-400 mt-1 font-heading uppercase tracking-wider">{roster.length} Players</p>
          </div>
        </div>
        
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs transition-colors">
                <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Pos</th>
                <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Name</th>
                <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Age</th>
                <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Condition</th>
                <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Traits</th>
                <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Value</th>
                <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">OVR</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
              {roster.map(player => {
                const attrs = player.attributes;
                const ovr = Math.round((attrs.pace + attrs.stamina + attrs.strength + attrs.passing + attrs.shooting + attrs.tackling + attrs.dribbling + attrs.defending + attrs.positioning + attrs.vision + attrs.decisions) / 11);
                const birth = new Date(player.date_of_birth);
                const age = 2026 - birth.getFullYear();
                
                return (
                  <tr key={player.id} onClick={() => onSelectPlayer(player.id)} className="hover:bg-gray-50 dark:hover:bg-navy-700/50 transition-colors group cursor-pointer">
                    <td className="py-3 px-5">
                      <Badge variant={positionBadgeVariant(player.position)}>
                        {player.position.substring(0, 3).toUpperCase()}
                      </Badge>
                    </td>
                    <td className="py-3 px-5">
                      <div className="font-semibold text-sm text-gray-900 dark:text-gray-100 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors">{player.full_name}</div>
                      <div className="text-xs text-gray-400 dark:text-gray-500">{player.nationality}</div>
                    </td>
                    <td className="py-3 px-5 text-sm text-gray-600 dark:text-gray-400 tabular-nums">{age}</td>
                    <td className="py-3 px-5">
                      <ProgressBar value={player.condition} variant="auto" size="sm" showLabel className="max-w-[120px]" />
                    </td>
                    <td className="py-3 px-5">
                      {player.traits && player.traits.length > 0 ? (
                        <TraitList traits={player.traits} size="xs" max={2} />
                      ) : (
                        <span className="text-xs text-gray-500">—</span>
                      )}
                    </td>
                    <td className="py-3 px-5 text-xs text-gray-600 dark:text-gray-400 font-medium">{formatVal(player.market_value)}</td>
                    <td className="py-3 px-5">
                      <span className={`font-heading font-bold text-lg tabular-nums ${
                        ovr >= 75 ? 'text-success-500 dark:text-success-400' :
                        ovr >= 55 ? 'text-accent-600 dark:text-accent-400' :
                        'text-gray-500 dark:text-gray-400'
                      }`}>{ovr}</span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          {roster.length === 0 && (
            <div className="p-8 text-center text-gray-500 dark:text-gray-400 font-heading uppercase tracking-wider text-sm">No players found in your squad.</div>
          )}
        </div>
      </Card>
    </div>
  );
}
