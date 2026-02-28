import { useState } from "react";
import { GameStateData, PlayerData } from "../store/gameStore";
import { Card, CardBody, Badge } from "./ui";
import { Search, TrendingUp, ShoppingCart, Handshake, ArrowRightLeft, Filter } from "lucide-react";
import { getTeamName, calcOvr, calcAge, formatVal, positionBadgeVariant } from "../lib/helpers";

interface TransfersTabProps {
  gameState: GameStateData;
  onSelectPlayer: (id: string) => void;
  onSelectTeam: (id: string) => void;
}

type TabView = "my_list" | "market" | "loans" | "offers";

export default function TransfersTab({ gameState, onSelectPlayer, onSelectTeam }: TransfersTabProps) {
  const userTeamId = gameState.manager.team_id;
  const [view, setView] = useState<TabView>("my_list");
  const [search, setSearch] = useState("");
  const [posFilter, setPosFilter] = useState<string | null>(null);

  const myTeam = gameState.teams.find(t => t.id === userTeamId);

  // My team's transfer-listed players
  const myTransferList = gameState.players.filter(p => p.team_id === userTeamId && p.transfer_listed);
  const myLoanList = gameState.players.filter(p => p.team_id === userTeamId && p.loan_listed);

  // Market: all transfer-listed players from other teams
  const marketPlayers = gameState.players.filter(p =>
    p.transfer_listed && p.team_id !== userTeamId
  );

  // Loans available: all loan-listed players from other teams
  const loanPlayers = gameState.players.filter(p =>
    p.loan_listed && p.team_id !== userTeamId
  );

  // Players with offers involving user's team (either incoming to user's players or user's bids)
  const playersWithOffers = gameState.players.filter(p =>
    p.transfer_offers.length > 0 && (
      p.team_id === userTeamId ||
      p.transfer_offers.some(o => o.from_team_id === userTeamId)
    )
  );

  const applyFilters = (list: PlayerData[]) => {
    return list.filter(p => {
      if (posFilter && p.position !== posFilter) return false;
      if (search.length >= 2) {
        const q = search.toLowerCase();
        if (!p.full_name.toLowerCase().includes(q) && !p.nationality.toLowerCase().includes(q)) return false;
      }
      return true;
    });
  };

  const positions = ["Goalkeeper", "Defender", "Midfielder", "Forward"];

  const tabs: { id: TabView; label: string; icon: React.ReactNode; count: number }[] = [
    { id: "my_list", label: "My Transfer List", icon: <ShoppingCart className="w-4 h-4" />, count: myTransferList.length + myLoanList.length },
    { id: "market", label: "Transfer Market", icon: <TrendingUp className="w-4 h-4" />, count: marketPlayers.length },
    { id: "loans", label: "Loan Market", icon: <ArrowRightLeft className="w-4 h-4" />, count: loanPlayers.length },
    { id: "offers", label: "Offers", icon: <Handshake className="w-4 h-4" />, count: playersWithOffers.length },
  ];

  const currentList =
    view === "my_list" ? [...myTransferList, ...myLoanList] :
    view === "market" ? marketPlayers :
    view === "loans" ? loanPlayers :
    playersWithOffers;

  const filteredList = applyFilters(currentList);

  return (
    <div className="max-w-6xl mx-auto">
      {/* Budget header */}
      {myTeam && (
        <Card accent="primary" className="mb-5">
          <div className="bg-gradient-to-r from-navy-700 to-navy-800 p-5 rounded-t-xl flex items-center gap-6">
            <div className="flex-1">
              <h2 className="text-lg font-heading font-bold text-white uppercase tracking-wide flex items-center gap-2">
                <TrendingUp className="w-5 h-5 text-accent-400" />
                Transfer Centre
              </h2>
              <p className="text-gray-400 text-xs mt-0.5">{myTeam.name} — Transfer Window</p>
            </div>
            <div className="hidden md:flex gap-4">
              <div className="bg-white/5 rounded-xl px-4 py-2 text-center">
                <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">Transfer Budget</p>
                <p className="font-heading font-bold text-lg text-accent-400">{formatVal(myTeam.transfer_budget)}</p>
              </div>
              <div className="bg-white/5 rounded-xl px-4 py-2 text-center">
                <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">Wage Budget</p>
                <p className="font-heading font-bold text-lg text-white">{formatVal(myTeam.wage_budget)}/wk</p>
              </div>
              <div className="bg-white/5 rounded-xl px-4 py-2 text-center">
                <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">Listed</p>
                <p className="font-heading font-bold text-lg text-white">{myTransferList.length + myLoanList.length}</p>
              </div>
            </div>
          </div>
        </Card>
      )}

      {/* Tab navigation */}
      <div className="flex gap-2 mb-4 flex-wrap">
        {tabs.map(tab => (
          <button
            key={tab.id}
            onClick={() => setView(tab.id)}
            className={`px-4 py-2 rounded-lg font-heading font-bold text-sm uppercase tracking-wider transition-all flex items-center gap-1.5 ${
              view === tab.id
                ? "bg-primary-500 text-white shadow-md shadow-primary-500/20"
                : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600 hover:text-gray-700 dark:hover:text-gray-200"
            }`}
          >
            {tab.icon} {tab.label} ({tab.count})
          </button>
        ))}
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-3 mb-4 items-center">
        <div className="relative flex-1 min-w-[180px] max-w-xs">
          <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 dark:text-gray-500" />
          <input
            type="text"
            placeholder="Search by name..."
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2 rounded-lg bg-white dark:bg-navy-800 border border-gray-200 dark:border-navy-600 text-sm text-gray-800 dark:text-gray-200 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-500/50"
          />
        </div>
        <div className="flex gap-1.5">
          <button onClick={() => setPosFilter(null)} className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${!posFilter ? "bg-primary-500 text-white shadow-sm" : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600"}`}>All</button>
          {positions.map(pos => (
            <button key={pos} onClick={() => setPosFilter(posFilter === pos ? null : pos)} className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${posFilter === pos ? "bg-primary-500 text-white shadow-sm" : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600"}`}>
              {pos.substring(0, 3)}
            </button>
          ))}
        </div>
        <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase tracking-wider">
          <Filter className="w-3.5 h-3.5 inline mr-1 -mt-0.5" />
          {filteredList.length} result{filteredList.length !== 1 ? "s" : ""}
        </p>
      </div>

      {/* Content */}
      {view === "my_list" && filteredList.length === 0 && (
        <Card>
          <CardBody>
            <div className="text-center py-8">
              <ShoppingCart className="w-10 h-10 text-gray-300 dark:text-navy-600 mx-auto mb-3" />
              <p className="text-sm text-gray-500 dark:text-gray-400">You have no players on the transfer or loan list.</p>
              <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">Go to a player's profile to list them for transfer or loan.</p>
            </div>
          </CardBody>
        </Card>
      )}

      {view === "offers" && filteredList.length === 0 && (
        <Card>
          <CardBody>
            <div className="text-center py-8">
              <Handshake className="w-10 h-10 text-gray-300 dark:text-navy-600 mx-auto mb-3" />
              <p className="text-sm text-gray-500 dark:text-gray-400">No active transfer offers at this time.</p>
            </div>
          </CardBody>
        </Card>
      )}

      {filteredList.length > 0 && (
        <Card>
          <CardBody className="p-0">
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Pos</th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Player</th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Age</th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Team</th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Value</th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Wage</th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">OVR</th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Status</th>
                    {view === "offers" && (
                      <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Offers</th>
                    )}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                  {filteredList.map(player => {
                    const ovr = calcOvr(player);
                    const age = calcAge(player.date_of_birth);
                    const offersForThisPlayer = player.transfer_offers;
                    return (
                      <tr key={player.id} className="hover:bg-gray-50 dark:hover:bg-navy-700/50 transition-colors cursor-pointer group" onClick={() => onSelectPlayer(player.id)}>
                        <td className="py-2.5 px-4">
                          <Badge variant={positionBadgeVariant(player.position)} size="sm">{player.position.substring(0, 3).toUpperCase()}</Badge>
                        </td>
                        <td className="py-2.5 px-4">
                          <span className="font-semibold text-sm text-gray-800 dark:text-gray-200 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors">{player.full_name}</span>
                          <span className="text-xs text-gray-400 dark:text-gray-500 ml-1.5">{player.nationality}</span>
                        </td>
                        <td className="py-2.5 px-4 text-sm text-gray-600 dark:text-gray-400 tabular-nums">{age}</td>
                        <td className="py-2.5 px-4">
                          <button onClick={e => { e.stopPropagation(); if (player.team_id) onSelectTeam(player.team_id); }} className="text-sm text-gray-600 dark:text-gray-400 hover:text-primary-500 hover:underline transition-colors">
                            {getTeamName(gameState.teams, player.team_id)}
                          </button>
                        </td>
                        <td className="py-2.5 px-4 text-sm text-gray-600 dark:text-gray-400 font-medium tabular-nums">{formatVal(player.market_value)}</td>
                        <td className="py-2.5 px-4 text-sm text-gray-600 dark:text-gray-400 tabular-nums">{formatVal(player.wage * 52)}/yr</td>
                        <td className="py-2.5 px-4">
                          <span className={`font-heading font-bold text-base tabular-nums ${ovr >= 75 ? "text-primary-500" : ovr >= 55 ? "text-accent-500" : "text-gray-400"}`}>{ovr}</span>
                        </td>
                        <td className="py-2.5 px-4">
                          <div className="flex gap-1">
                            {player.transfer_listed && <Badge variant="accent" size="sm">Transfer</Badge>}
                            {player.loan_listed && <Badge variant="primary" size="sm">Loan</Badge>}
                          </div>
                        </td>
                        {view === "offers" && (
                          <td className="py-2.5 px-4">
                            <div className="flex flex-col gap-1">
                              {offersForThisPlayer.length === 0 ? (
                                <span className="text-xs text-gray-400">None</span>
                              ) : (
                                offersForThisPlayer.map(offer => (
                                  <div key={offer.id} className="flex items-center gap-2">
                                    <span className="text-xs text-gray-600 dark:text-gray-300 font-medium">
                                      {getTeamName(gameState.teams, offer.from_team_id)}
                                    </span>
                                    <Badge
                                      variant={offer.status === "Pending" ? "accent" : offer.status === "Accepted" ? "success" : "danger"}
                                      size="sm"
                                    >
                                      {formatVal(offer.fee)} — {offer.status}
                                    </Badge>
                                  </div>
                                ))
                              )}
                            </div>
                          </td>
                        )}
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </CardBody>
        </Card>
      )}

      {(view === "market" || view === "loans") && filteredList.length === 0 && (
        <Card>
          <CardBody>
            <div className="text-center py-8">
              <TrendingUp className="w-10 h-10 text-gray-300 dark:text-navy-600 mx-auto mb-3" />
              <p className="text-sm text-gray-500 dark:text-gray-400">
                No players currently {view === "market" ? "available for transfer" : "available for loan"}.
              </p>
            </div>
          </CardBody>
        </Card>
      )}
    </div>
  );
}
