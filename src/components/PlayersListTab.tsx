import { useState } from "react";
import { GameStateData } from "../store/gameStore";
import { Card, CardBody, Badge } from "./ui";
import { Search, Filter, ArrowUpDown } from "lucide-react";
import { getTeamName, calcOvr, calcAge, formatVal, positionBadgeVariant } from "../lib/helpers";

interface PlayersListTabProps {
  gameState: GameStateData;
  onSelectPlayer: (id: string) => void;
  onSelectTeam: (id: string) => void;
}

type SortKey = "name" | "position" | "age" | "ovr" | "value" | "team";

export default function PlayersListTab({ gameState, onSelectPlayer, onSelectTeam }: PlayersListTabProps) {
  const [search, setSearch] = useState("");
  const [posFilter, setPosFilter] = useState<string | null>(null);
  const [teamFilter, setTeamFilter] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<SortKey>("ovr");
  const [sortAsc, setSortAsc] = useState(false);
  const [statusFilter, setStatusFilter] = useState<"all" | "transfer" | "loan">("all");

  const handleSort = (key: SortKey) => {
    if (sortKey === key) setSortAsc(!sortAsc);
    else { setSortKey(key); setSortAsc(key === "name"); }
  };

  let filtered = gameState.players.filter(p => {
    if (search.length >= 2) {
      const q = search.toLowerCase();
      if (!p.full_name.toLowerCase().includes(q) && !p.match_name.toLowerCase().includes(q) && !p.nationality.toLowerCase().includes(q)) return false;
    }
    if (posFilter && p.position !== posFilter) return false;
    if (teamFilter && p.team_id !== teamFilter) return false;
    if (statusFilter === "transfer" && !p.transfer_listed) return false;
    if (statusFilter === "loan" && !p.loan_listed) return false;
    return true;
  });

  const posOrder: Record<string, number> = { Goalkeeper: 1, Defender: 2, Midfielder: 3, Forward: 4 };

  filtered.sort((a, b) => {
    let cmp = 0;
    switch (sortKey) {
      case "name": cmp = a.full_name.localeCompare(b.full_name); break;
      case "position": cmp = (posOrder[a.position] || 99) - (posOrder[b.position] || 99); break;
      case "age": cmp = calcAge(a.date_of_birth) - calcAge(b.date_of_birth); break;
      case "ovr": cmp = calcOvr(a) - calcOvr(b); break;
      case "value": cmp = (a.market_value || 0) - (b.market_value || 0); break;
      case "team": cmp = getTeamName(gameState.teams, a.team_id).localeCompare(getTeamName(gameState.teams, b.team_id)); break;
    }
    return sortAsc ? cmp : -cmp;
  });

  const positions = ["Goalkeeper", "Defender", "Midfielder", "Forward"];

  return (
    <div className="max-w-6xl mx-auto">
      {/* Filters */}
      <div className="flex flex-wrap gap-3 mb-4 items-center">
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 dark:text-gray-500" />
          <input
            type="text"
            placeholder="Search by name or nationality..."
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2 rounded-lg bg-white dark:bg-navy-800 border border-gray-200 dark:border-navy-600 text-sm text-gray-800 dark:text-gray-200 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-500/50"
          />
        </div>

        <div className="flex gap-1.5">
          <button
            onClick={() => setPosFilter(null)}
            className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
              !posFilter ? "bg-primary-500 text-white shadow-sm" : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600"
            }`}
          >
            All Pos
          </button>
          {positions.map(pos => (
            <button
              key={pos}
              onClick={() => setPosFilter(posFilter === pos ? null : pos)}
              className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
                posFilter === pos ? "bg-primary-500 text-white shadow-sm" : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600"
              }`}
            >
              {pos.substring(0, 3)}
            </button>
          ))}
        </div>

        <div className="flex gap-1.5">
          <button onClick={() => setStatusFilter("all")} className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${statusFilter === "all" ? "bg-primary-500 text-white shadow-sm" : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600"}`}>All</button>
          <button onClick={() => setStatusFilter("transfer")} className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${statusFilter === "transfer" ? "bg-accent-500 text-white shadow-sm" : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600"}`}>Transfer</button>
          <button onClick={() => setStatusFilter("loan")} className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${statusFilter === "loan" ? "bg-blue-500 text-white shadow-sm" : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600"}`}>Loan</button>
        </div>

        <select
          value={teamFilter || ""}
          onChange={e => setTeamFilter(e.target.value || null)}
          className="px-3 py-2 rounded-lg bg-white dark:bg-navy-800 border border-gray-200 dark:border-navy-600 text-xs font-heading font-bold uppercase tracking-wider text-gray-600 dark:text-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500/50"
        >
          <option value="">All Teams</option>
          {gameState.teams.map(t => (
            <option key={t.id} value={t.id}>{t.name}</option>
          ))}
        </select>
      </div>

      <p className="text-xs text-gray-400 dark:text-gray-500 mb-3 font-heading uppercase tracking-wider">
        <Filter className="w-3.5 h-3.5 inline mr-1 -mt-0.5" />
        {filtered.length} player{filtered.length !== 1 ? "s" : ""} found
      </p>

      {/* Players table */}
      <Card>
        <CardBody className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
                  <SortHeader label="Pos" sortKey="position" current={sortKey} asc={sortAsc} onClick={handleSort} />
                  <SortHeader label="Name" sortKey="name" current={sortKey} asc={sortAsc} onClick={handleSort} />
                  <SortHeader label="Age" sortKey="age" current={sortKey} asc={sortAsc} onClick={handleSort} />
                  <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Nationality</th>
                  <SortHeader label="Team" sortKey="team" current={sortKey} asc={sortAsc} onClick={handleSort} />
                  <SortHeader label="Value" sortKey="value" current={sortKey} asc={sortAsc} onClick={handleSort} />
                  <SortHeader label="OVR" sortKey="ovr" current={sortKey} asc={sortAsc} onClick={handleSort} />
                  <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                {filtered.slice(0, 100).map(player => {
                  const ovr = calcOvr(player);
                  const age = calcAge(player.date_of_birth);
                  return (
                    <tr key={player.id} onClick={() => onSelectPlayer(player.id)} className="hover:bg-gray-50 dark:hover:bg-navy-700/50 transition-colors cursor-pointer group">
                      <td className="py-2.5 px-4">
                        <Badge variant={positionBadgeVariant(player.position)} size="sm">{player.position.substring(0, 3).toUpperCase()}</Badge>
                      </td>
                      <td className="py-2.5 px-4">
                        <span className="font-semibold text-sm text-gray-800 dark:text-gray-200 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors">{player.full_name}</span>
                      </td>
                      <td className="py-2.5 px-4 text-sm text-gray-600 dark:text-gray-400 tabular-nums">{age}</td>
                      <td className="py-2.5 px-4 text-sm text-gray-500 dark:text-gray-400">{player.nationality}</td>
                      <td className="py-2.5 px-4">
                        <button onClick={e => { e.stopPropagation(); onSelectTeam(player.team_id!); }} className="text-sm text-gray-600 dark:text-gray-400 hover:text-primary-500 hover:underline transition-colors">
                          {getTeamName(gameState.teams, player.team_id)}
                        </button>
                      </td>
                      <td className="py-2.5 px-4 text-sm text-gray-600 dark:text-gray-400 font-medium">{formatVal(player.market_value)}</td>
                      <td className="py-2.5 px-4">
                        <span className={`font-heading font-bold text-base tabular-nums ${
                          ovr >= 75 ? "text-primary-500" : ovr >= 55 ? "text-accent-500" : "text-gray-400"
                        }`}>{ovr}</span>
                      </td>
                      <td className="py-2.5 px-4">
                        {player.transfer_listed && <Badge variant="accent" size="sm">Transfer</Badge>}
                        {player.loan_listed && <Badge variant="primary" size="sm">Loan</Badge>}
                        {player.injury && <Badge variant="danger" size="sm">Injured</Badge>}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            {filtered.length === 0 && (
              <div className="p-8 text-center text-gray-500 dark:text-gray-400 text-sm">No players match your filters.</div>
            )}
            {filtered.length > 100 && (
              <div className="p-3 text-center text-xs text-gray-400 dark:text-gray-500 border-t border-gray-100 dark:border-navy-600">
                Showing first 100 of {filtered.length} players. Refine your search to see more.
              </div>
            )}
          </div>
        </CardBody>
      </Card>
    </div>
  );
}

function SortHeader({ label, sortKey, current, onClick }: { label: string; sortKey: SortKey; current: SortKey; asc: boolean; onClick: (k: SortKey) => void }) {
  const isActive = current === sortKey;
  return (
    <th
      onClick={() => onClick(sortKey)}
      className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 cursor-pointer hover:text-gray-700 dark:hover:text-gray-200 transition-colors select-none"
    >
      <span className="flex items-center gap-1">
        {label}
        <ArrowUpDown className={`w-3 h-3 ${isActive ? "text-primary-500" : "text-gray-300 dark:text-navy-600"}`} />
      </span>
    </th>
  );
}
