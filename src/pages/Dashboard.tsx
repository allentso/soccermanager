import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { invoke } from "@tauri-apps/api/core";
import { useGameStore, GameStateData } from "../store/gameStore";
import { Badge, ThemeToggle } from "../components/ui";
import PlayerProfile from "../components/PlayerProfile";
import TeamProfile from "../components/TeamProfile";
import HomeTab from "../components/HomeTab";
import SquadTab from "../components/SquadTab";
import TacticsTab from "../components/TacticsTab";
import TrainingTab from "../components/TrainingTab";
import ScheduleTab from "../components/ScheduleTab";
import FinancesTab from "../components/FinancesTab";
import TransfersTab from "../components/TransfersTab";
import PlayersListTab from "../components/PlayersListTab";
import TeamsListTab from "../components/TeamsListTab";
import TournamentsTab from "../components/TournamentsTab";
import StaffTab from "../components/StaffTab";
import InboxTab from "../components/InboxTab";
import ManagerTab from "../components/ManagerTab";
import NewsTab from "../components/NewsTab";
import { Users, Calendar as CalendarIcon, Mail, Settings, ChevronRight, ChevronDown, Briefcase, Trophy, TrendingUp, Crosshair, Dumbbell, DollarSign, Search, User, UsersRound, Building2, UserCog, Newspaper, LogOut, ArrowLeft } from "lucide-react";
import { getTeamName } from "../lib/helpers";

export default function Dashboard() {
  const navigate = useNavigate();
  const { hasActiveGame, managerName, gameState, setGameState, clearGame } = useGameStore();
  const [isAdvancing, setIsAdvancing] = useState(false);
  const [activeTab, setActiveTab] = useState("Home");
  const [showContinueMenu, setShowContinueMenu] = useState(false);
  const [showExitConfirm, setShowExitConfirm] = useState(false);
  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const [selectedTeamId, setSelectedTeamId] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [searchOpen, setSearchOpen] = useState(false);
  const [initialMessageId, setInitialMessageId] = useState<string | null>(null);
  const [navHistory, setNavHistory] = useState<Array<{ tab: string; playerId: string | null; teamId: string | null }>>([]); 

  // Fetch initial state
  useEffect(() => {
    if (!hasActiveGame) {
      navigate("/");
      return;
    }

    const fetchState = async () => {
      try {
        const state = await invoke<GameStateData>("get_active_game");
        setGameState(state);
      } catch (err) {
        console.error("Failed to fetch game state:", err);
      }
    };

    fetchState();
  }, [hasActiveGame, navigate, setGameState]);

  const handleContinue = async (mode: string = "live") => {
    if (isAdvancing) return;
    setIsAdvancing(true);
    setShowContinueMenu(false);
    try {
      const result = await invoke<{ action: string; game?: GameStateData; snapshot?: unknown; fixture_index?: number }>("advance_time_with_mode", { mode });
      if (result.action === "live_match") {
        // A live match was set up — navigate to match simulation
        navigate("/match");
      } else if (result.action === "advanced" && result.game) {
        setGameState(result.game as GameStateData);
      }
    } catch (err) {
      console.error("Failed to advance time:", err);
    } finally {
      setIsAdvancing(false);
    }
  };

  const handleSkipToMatchDay = async () => {
    if (isAdvancing) return;
    setIsAdvancing(true);
    setShowContinueMenu(false);
    try {
      const updatedGame = await invoke<GameStateData>("skip_to_match_day");
      setGameState(updatedGame);
    } catch (err) {
      console.error("Failed to skip to match day:", err);
    } finally {
      setIsAdvancing(false);
    }
  };

  const handleNavClick = (tab: string) => {
    setNavHistory([]);
    setActiveTab(tab);
    setSelectedPlayerId(null);
    setSelectedTeamId(null);
    setInitialMessageId(null);
  };

  const handleNavigate = (tab: string, context?: { messageId?: string }) => {
    setNavHistory([]);
    setActiveTab(tab);
    setSelectedPlayerId(null);
    setSelectedTeamId(null);
    if (context?.messageId) {
      setInitialMessageId(context.messageId);
    } else {
      setInitialMessageId(null);
    }
  };

  const pushHistory = () => {
    setNavHistory(prev => [...prev, { tab: activeTab, playerId: selectedPlayerId, teamId: selectedTeamId }]);
  };

  const handleBack = () => {
    if (navHistory.length > 0) {
      const prev = navHistory[navHistory.length - 1];
      setNavHistory(h => h.slice(0, -1));
      setActiveTab(prev.tab);
      setSelectedPlayerId(prev.playerId);
      setSelectedTeamId(prev.teamId);
    } else {
      setSelectedPlayerId(null);
      setSelectedTeamId(null);
    }
  };

  const handleExitToMenu = async () => {
    try {
      await invoke("exit_to_menu");
      clearGame();
      navigate("/");
    } catch (err) {
      console.error("Failed to exit:", err);
      // Still navigate even if save fails
      clearGame();
      navigate("/");
    }
  };

  const selectPlayer = (id: string) => {
    pushHistory();
    setSelectedPlayerId(id);
    setSelectedTeamId(null);
  };

  const selectTeam = (id: string) => {
    pushHistory();
    setSelectedTeamId(id);
    setSelectedPlayerId(null);
  };

  if (!gameState) {
    return (
      <div className="min-h-screen bg-gray-100 dark:bg-navy-900 flex items-center justify-center transition-colors">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          <span className="text-gray-500 dark:text-gray-400 font-heading uppercase tracking-wider text-sm">Loading game state...</span>
        </div>
      </div>
    );
  }

  const currentDate = new Date(gameState.clock.current_date).toLocaleDateString(undefined, {
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
  });

  const unreadMessagesCount = gameState.messages?.filter(m => !m.read).length || 0;

  return (
    <div className="min-h-screen bg-gray-100 dark:bg-navy-900 flex transition-colors duration-300">
      {/* Sidebar Navigation */}
      <aside className="w-64 bg-navy-800 dark:bg-navy-800 border-r border-navy-700 text-white flex flex-col flex-shrink-0">
        {/* Brand */}
        <div className="p-5 border-b border-navy-700">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 flex items-center justify-center">
              <img src="../../openfootball.svg" alt="Logo" className="w-8 h-8" />
            </div>
            <div>
              <h1 className="text-sm font-heading font-bold text-white uppercase tracking-wider">OpenFoot</h1>
              <h1 className="text-xs font-heading text-accent-400 uppercase tracking-wider">Manager</h1>
            </div>
          </div>
          <div className="mt-3 pt-3 border-t border-navy-700">
            <p className="text-xs text-gray-400 uppercase tracking-wider">Manager</p>
            <p className="text-sm font-semibold text-white mt-0.5">{managerName}</p>
            {(() => {
              const myTeam = gameState?.teams.find(t => t.id === gameState.manager.team_id);
              return myTeam ? (
                <p className="text-xs text-primary-400 mt-0.5">{myTeam.name}</p>
              ) : null;
            })()}
          </div>
        </div>
        
        {/* Navigation */}
        <nav className="flex-1 py-4 px-3 flex flex-col gap-1 overflow-y-auto">
          <NavItem icon={<Briefcase />} label="Home" active={activeTab === "Home"} onClick={() => handleNavClick("Home")} />
          <NavItem icon={<Mail />} label="Inbox" badge={unreadMessagesCount > 0 ? unreadMessagesCount : undefined} active={activeTab === "Inbox"} onClick={() => handleNavClick("Inbox")} />
          <NavItem icon={<User />} label="Manager" active={activeTab === "Manager"} onClick={() => handleNavClick("Manager")} />

          <p className="text-[10px] text-gray-500 uppercase tracking-widest font-heading px-3 pt-3 pb-1">Club</p>
          <NavItem icon={<Users />} label="Squad" active={activeTab === "Squad"} onClick={() => handleNavClick("Squad")} />
          <NavItem icon={<Crosshair />} label="Tactics" active={activeTab === "Tactics"} onClick={() => handleNavClick("Tactics")} />
          <NavItem icon={<Dumbbell />} label="Training" active={activeTab === "Training"} onClick={() => handleNavClick("Training")} />
          <NavItem icon={<UserCog />} label="Staff" active={activeTab === "Staff"} onClick={() => handleNavClick("Staff")} />
          <NavItem icon={<DollarSign />} label="Finances" active={activeTab === "Finances"} onClick={() => handleNavClick("Finances")} />
          <NavItem icon={<TrendingUp />} label="Transfers" active={activeTab === "Transfers"} onClick={() => handleNavClick("Transfers")} />

          <p className="text-[10px] text-gray-500 uppercase tracking-widest font-heading px-3 pt-3 pb-1">World</p>
          <NavItem icon={<UsersRound />} label="Players" active={activeTab === "Players"} onClick={() => handleNavClick("Players")} />
          <NavItem icon={<Building2 />} label="Teams" active={activeTab === "Teams"} onClick={() => handleNavClick("Teams")} />
          <NavItem icon={<Trophy />} label="Tournaments" active={activeTab === "Tournaments"} onClick={() => handleNavClick("Tournaments")} />
          <NavItem icon={<CalendarIcon />} label="Schedule" active={activeTab === "Schedule"} onClick={() => handleNavClick("Schedule")} />
          <NavItem icon={<Newspaper />} label="News" active={activeTab === "News"} onClick={() => handleNavClick("News")} />
        </nav>
        
        {/* Settings & Exit */}
        <div className="p-3 border-t border-navy-700 flex flex-col gap-1">
          <button 
            onClick={() => navigate("/settings", { state: { from: "/dashboard" } })}
            className="flex items-center gap-3 w-full p-3 hover:bg-white/5 rounded-lg transition-colors text-gray-500 hover:text-gray-300"
          >
            <Settings className="w-5 h-5" />
            <span className="font-heading text-sm uppercase tracking-wider">Settings</span>
          </button>
          <button 
            onClick={() => setShowExitConfirm(true)}
            className="flex items-center gap-3 w-full p-3 hover:bg-red-500/10 rounded-lg transition-colors text-gray-500 hover:text-red-400"
          >
            <LogOut className="w-5 h-5" />
            <span className="font-heading text-sm uppercase tracking-wider">Exit to Menu</span>
          </button>
        </div>
      </aside>

      {/* Exit Confirmation Modal */}
      {showExitConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm">
          <div className="bg-white dark:bg-navy-800 rounded-2xl shadow-2xl border border-gray-200 dark:border-navy-600 w-full max-w-sm p-6 mx-4">
            <h3 className="text-lg font-heading font-bold uppercase tracking-wide text-gray-900 dark:text-white">
              Exit to Main Menu?
            </h3>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              Your game will be saved automatically before returning to the main menu.
            </p>
            <div className="flex gap-3 mt-6">
              <button
                onClick={() => setShowExitConfirm(false)}
                className="flex-1 py-2.5 px-4 bg-gray-100 dark:bg-navy-700 hover:bg-gray-200 dark:hover:bg-navy-600 text-gray-700 dark:text-gray-300 font-heading font-bold text-sm uppercase tracking-wider rounded-lg transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={() => { setShowExitConfirm(false); handleExitToMenu(); }}
                className="flex-1 py-2.5 px-4 bg-red-500 hover:bg-red-600 text-white font-heading font-bold text-sm uppercase tracking-wider rounded-lg transition-colors"
              >
                Save & Exit
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Main Content Area */}
      <main className="flex-1 flex flex-col h-screen overflow-hidden">
        {/* Top Header Bar */}
        <header className="bg-white dark:bg-navy-800 border-b border-gray-200 dark:border-navy-700 px-6 py-3 flex justify-between items-center shadow-sm z-10 transition-colors duration-300">
          <div className="flex items-center gap-3">
            {(navHistory.length > 0 || selectedPlayerId || selectedTeamId) && (
              <button
                onClick={handleBack}
                className="p-2 -ml-2 rounded-lg text-gray-400 hover:text-gray-700 dark:hover:text-white hover:bg-gray-100 dark:hover:bg-navy-700 transition-colors"
                title="Go back"
              >
                <ArrowLeft className="w-5 h-5" />
              </button>
            )}
            <div>
              <h2 className="text-xl font-heading font-bold uppercase tracking-wide text-gray-800 dark:text-gray-100">{activeTab}</h2>
              <p className="text-gray-500 dark:text-gray-400 text-xs flex items-center gap-1.5 mt-0.5">
                <CalendarIcon className="w-3.5 h-3.5" /> 
                <span className="font-medium">{currentDate}</span>
              </p>
            </div>
          </div>
          
          {/* Centered Omni-search */}
          <div className="relative flex-1 max-w-md mx-auto">
            <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 dark:text-gray-500" />
            <input
              type="text"
              placeholder="Search players, teams..."
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              onFocus={() => setSearchOpen(true)}
              onBlur={() => setTimeout(() => setSearchOpen(false), 200)}
              className="w-full pl-9 pr-3 py-2 rounded-lg bg-gray-100 dark:bg-navy-700 border border-gray-200 dark:border-navy-600 text-sm text-gray-800 dark:text-gray-200 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-500/50 transition-all"
            />
            {searchOpen && searchQuery.length >= 2 && (
              <div className="absolute top-full mt-1 left-0 right-0 bg-white dark:bg-navy-700 rounded-lg shadow-xl border border-gray-200 dark:border-navy-600 z-30 max-h-80 overflow-y-auto">
                {(() => {
                  const q = searchQuery.toLowerCase();
                  const matchedPlayers = gameState.players.filter(p => p.full_name.toLowerCase().includes(q) || p.match_name.toLowerCase().includes(q)).slice(0, 5);
                  const matchedTeams = gameState.teams.filter(t => t.name.toLowerCase().includes(q) || t.short_name.toLowerCase().includes(q)).slice(0, 4);
                  if (matchedPlayers.length === 0 && matchedTeams.length === 0) {
                    return <p className="p-3 text-xs text-gray-400 dark:text-gray-500">No results found.</p>;
                  }
                  return (
                    <>
                      {matchedTeams.length > 0 && (
                        <div>
                          <p className="px-3 pt-2 pb-1 text-xs font-heading font-bold uppercase tracking-wider text-gray-400 dark:text-gray-500">Teams</p>
                          {matchedTeams.map(t => (
                            <button key={t.id} onMouseDown={() => { setSelectedTeamId(t.id); setSearchQuery(""); }} className="w-full text-left px-3 py-2 hover:bg-gray-50 dark:hover:bg-navy-600 flex items-center gap-2 transition-colors">
                              <div className="w-6 h-6 rounded flex items-center justify-center text-xs font-bold text-white" style={{ backgroundColor: t.colors.primary }}>{t.short_name.charAt(0)}</div>
                              <span className="text-sm font-medium text-gray-800 dark:text-gray-200">{t.name}</span>
                              <span className="text-xs text-gray-400 ml-auto">{t.city}</span>
                            </button>
                          ))}
                        </div>
                      )}
                      {matchedPlayers.length > 0 && (
                        <div>
                          <p className="px-3 pt-2 pb-1 text-xs font-heading font-bold uppercase tracking-wider text-gray-400 dark:text-gray-500">Players</p>
                          {matchedPlayers.map(p => (
                            <button key={p.id} onMouseDown={() => { setSelectedPlayerId(p.id); setSearchQuery(""); }} className="w-full text-left px-3 py-2 hover:bg-gray-50 dark:hover:bg-navy-600 flex items-center gap-2 transition-colors">
                              <Badge variant={p.position === "Goalkeeper" ? "accent" : p.position === "Defender" ? "primary" : p.position === "Midfielder" ? "success" : "danger"} size="sm">{p.position.substring(0, 3).toUpperCase()}</Badge>
                              <span className="text-sm font-medium text-gray-800 dark:text-gray-200">{p.full_name}</span>
                              <span className="text-xs text-gray-400 ml-auto">{getTeamName(gameState.teams, p.team_id ?? "")}</span>
                            </button>
                          ))}
                        </div>
                      )}
                    </>
                  );
                })()}
              </div>
            )}
          </div>

          <div className="flex items-center gap-3">
            <ThemeToggle />

            {/* Finance badge — real data */}
            {(() => {
              const myTeam = gameState.teams.find(t => t.id === gameState.manager.team_id);
              const bal = myTeam ? myTeam.finance : 0;
              const display = bal >= 1_000_000 ? `€${(bal / 1_000_000).toFixed(1)}M` : bal >= 1_000 ? `€${(bal / 1_000).toFixed(0)}K` : `€${bal}`;
              return (
                <Badge variant={bal > 0 ? "success" : "danger"} size="md">
                  <span className="flex items-center gap-1">{display}</span>
                </Badge>
              );
            })()}

            {/* Continue button with dropdown */}
            <div className="relative">
              <div className="flex">
                <button 
                  onClick={() => handleContinue("live")}
                  disabled={isAdvancing}
                  className={`bg-gradient-to-r from-primary-500 to-primary-600 hover:from-primary-600 hover:to-primary-700 text-white pl-5 pr-4 py-2.5 rounded-l-lg font-heading font-bold uppercase tracking-wider text-sm shadow-md hover:shadow-lg hover:shadow-primary-500/20 transition-all flex items-center gap-2 ${isAdvancing ? 'opacity-70 cursor-wait' : ''}`}
                >
                  <span>{isAdvancing ? 'Simulating...' : 'Continue'}</span>
                  <ChevronRight className={`w-4 h-4 ${isAdvancing ? 'animate-pulse' : ''}`} />
                </button>
                <button
                  onClick={() => setShowContinueMenu(!showContinueMenu)}
                  className="bg-primary-700 hover:bg-primary-800 text-white px-2 py-2.5 rounded-r-lg border-l border-primary-400/30 transition-colors"
                >
                  <ChevronDown className="w-4 h-4" />
                </button>
              </div>

              {/* Dropdown menu */}
              {showContinueMenu && (
                <div className="absolute right-0 top-full mt-1 w-64 bg-white dark:bg-navy-700 rounded-lg shadow-xl border border-gray-200 dark:border-navy-600 py-1 z-20">
                  <button
                    onClick={() => handleContinue("live")}
                    className="w-full text-left px-4 py-2.5 hover:bg-gray-50 dark:hover:bg-navy-600 text-sm transition-colors"
                  >
                    <span className="font-heading font-bold text-gray-800 dark:text-gray-100 uppercase tracking-wide text-xs">Go to the Field</span>
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">Full match control (default)</p>
                  </button>
                  <button
                    onClick={() => handleContinue("spectator")}
                    className="w-full text-left px-4 py-2.5 hover:bg-gray-50 dark:hover:bg-navy-600 text-sm transition-colors"
                  >
                    <span className="font-heading font-bold text-gray-800 dark:text-gray-100 uppercase tracking-wide text-xs">Watch as Spectator</span>
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">Watch the match, no controls</p>
                  </button>
                  <button
                    onClick={() => handleContinue("delegate")}
                    className="w-full text-left px-4 py-2.5 hover:bg-gray-50 dark:hover:bg-navy-600 text-sm transition-colors"
                  >
                    <span className="font-heading font-bold text-gray-800 dark:text-gray-100 uppercase tracking-wide text-xs">Delegate to Assistant</span>
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">AI handles everything instantly</p>
                  </button>
                  <div className="border-t border-gray-200 dark:border-navy-600 my-1" />
                  <button
                    onClick={handleSkipToMatchDay}
                    className="w-full text-left px-4 py-2.5 hover:bg-gray-50 dark:hover:bg-navy-600 text-sm transition-colors"
                  >
                    <span className="font-heading font-bold text-gray-800 dark:text-gray-100 uppercase tracking-wide text-xs">Skip to Match Day</span>
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">Fast-forward to your next fixture</p>
                  </button>
                </div>
              )}
            </div>
          </div>
        </header>

        {/* Dashboard Content */}
        <div className="flex-1 overflow-auto p-6 bg-gray-100 dark:bg-navy-900">
          {/* Inline Player Profile Page */}
          {selectedPlayerId && !selectedTeamId && (() => {
            const player = gameState.players.find(p => p.id === selectedPlayerId);
            if (!player) return null;
            const isOwnClub = player.team_id === gameState.manager.team_id;
            return (
              <PlayerProfile
                player={player}
                gameState={gameState}
                isOwnClub={isOwnClub}
                onClose={handleBack}
                onSelectTeam={selectTeam}
              />
            );
          })()}

          {/* Inline Team Profile Page */}
          {selectedTeamId && (() => {
            const team = gameState.teams.find(t => t.id === selectedTeamId);
            if (!team) return null;
            const isOwnTeam = team.id === gameState.manager.team_id;
            return (
              <TeamProfile
                team={team}
                gameState={gameState}
                isOwnTeam={isOwnTeam}
                onClose={handleBack}
                onSelectPlayer={selectPlayer}
              />
            );
          })()}

          {/* Tab content — hidden when a profile is open */}
          {!selectedPlayerId && !selectedTeamId && activeTab === "Home" && (
            <HomeTab gameState={gameState} onNavigate={handleNavigate} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "Squad" && (
            <SquadTab gameState={gameState} managerId={gameState.manager.id} onSelectPlayer={selectPlayer} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "Tactics" && (
            <TacticsTab gameState={gameState} onSelectPlayer={selectPlayer} onGameUpdate={setGameState} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "Training" && (
            <TrainingTab gameState={gameState} onGameUpdate={setGameState} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "Schedule" && (
            <ScheduleTab gameState={gameState} onSelectTeam={selectTeam} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "Finances" && (
            <FinancesTab gameState={gameState} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "Transfers" && (
            <TransfersTab gameState={gameState} onSelectPlayer={selectPlayer} onSelectTeam={selectTeam} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "Players" && (
            <PlayersListTab gameState={gameState} onSelectPlayer={selectPlayer} onSelectTeam={selectTeam} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "Teams" && (
            <TeamsListTab gameState={gameState} onSelectTeam={selectTeam} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "Tournaments" && (
            <TournamentsTab gameState={gameState} onSelectTeam={selectTeam} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "Staff" && (
            <StaffTab gameState={gameState} onGameUpdate={setGameState} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "Inbox" && (
            <InboxTab gameState={gameState} onGameUpdate={setGameState} initialMessageId={initialMessageId} onNavigate={handleNavigate} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "Manager" && (
            <ManagerTab gameState={gameState} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "News" && (
            <NewsTab gameState={gameState} onSelectTeam={selectTeam} />
          )}

        </div>
      </main>

    </div>
  );
}

function NavItem({ icon, label, active, badge, onClick }: { icon: React.ReactNode, label: string, active?: boolean, badge?: number, onClick?: () => void }) {
  return (
    <button 
      onClick={onClick}
      className={`w-full flex items-center justify-between p-3 rounded-lg transition-all duration-200 ${
        active 
          ? 'bg-gradient-to-r from-primary-500 to-primary-600 text-white shadow-md shadow-primary-500/20' 
          : 'text-gray-400 hover:text-white hover:bg-white/5'
      }`}
    >
      <div className="flex items-center gap-3">
        <div className="[&>svg]:w-5 [&>svg]:h-5">{icon}</div>
        <span className="font-heading font-semibold text-sm uppercase tracking-wider">{label}</span>
      </div>
      {badge !== undefined && badge > 0 && (
        <span className="bg-primary-500 text-white text-xs font-bold px-2 py-0.5 rounded-full min-w-[1.25rem] text-center">
          {badge}
        </span>
      )}
    </button>
  );
}
