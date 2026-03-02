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
import ScoutingTab from "../components/ScoutingTab";
import StaffTab from "../components/StaffTab";
import InboxTab from "../components/InboxTab";
import ManagerTab from "../components/ManagerTab";
import NewsTab from "../components/NewsTab";
import EndOfSeasonScreen from "../components/EndOfSeasonScreen";
import { Users, Calendar as CalendarIcon, Mail, Settings, ChevronRight, ChevronDown, Briefcase, Trophy, TrendingUp, Crosshair, Dumbbell, DollarSign, Search, User, UsersRound, Building2, UserCog, Newspaper, LogOut, ArrowLeft, Eye, Cpu, Gamepad2, AlertCircle } from "lucide-react";
import { getTeamName } from "../lib/helpers";
import { useTranslation } from "react-i18next";
import { useSettingsStore } from "../store/settingsStore";

export default function Dashboard() {
  const navigate = useNavigate();
  const { hasActiveGame, managerName, gameState, setGameState, clearGame } = useGameStore();
  const { t } = useTranslation();
  const { settings, loaded: settingsLoaded, loadSettings } = useSettingsStore();

  // Load settings on mount
  useEffect(() => {
    if (!settingsLoaded) loadSettings();
  }, [settingsLoaded, loadSettings]);
  const [isAdvancing, setIsAdvancing] = useState(false);
  const [activeTab, setActiveTab] = useState("Home");
  const [showContinueMenu, setShowContinueMenu] = useState(false);
  const [showExitConfirm, setShowExitConfirm] = useState(false);
  const [showMatchConfirm, setShowMatchConfirm] = useState(false);
  const [matchMode, setMatchMode] = useState<"live" | "spectator" | "delegate">("live");

  // Sync matchMode with settings when loaded
  useEffect(() => {
    if (settingsLoaded && settings.default_match_mode) {
      setMatchMode(settings.default_match_mode);
    }
  }, [settingsLoaded, settings.default_match_mode]);
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

  // Check if user has a match today
  const hasMatchToday = gameState?.league?.fixtures.some(f => {
    const today = gameState.clock.current_date.split('T')[0];
    return f.date === today
      && f.status === 'Scheduled'
      && (f.home_team_id === gameState.manager.team_id || f.away_team_id === gameState.manager.team_id);
  }) ?? false;

  // Detect if season is complete (all fixtures played)
  const seasonComplete = gameState?.league?.fixtures
    ? gameState.league.fixtures.length > 0 && gameState.league.fixtures.every(f => f.status === "Completed")
    : false;

  const handleContinue = async (mode?: string) => {
    const effectiveMode = mode || matchMode;
    // If there's a match today, show confirmation modal first
    if (hasMatchToday && !showMatchConfirm) {
      if (mode) setMatchMode(mode as "live" | "spectator" | "delegate");
      setShowContinueMenu(false);
      setShowMatchConfirm(true);
      return;
    }
    if (isAdvancing) return;
    setIsAdvancing(true);
    setShowContinueMenu(false);
    setShowMatchConfirm(false);
    try {
      const result = await invoke<{ action: string; game?: GameStateData; snapshot?: unknown; fixture_index?: number; mode?: string }>("advance_time_with_mode", { mode: effectiveMode });
      if (result.action === "live_match") {
        navigate("/match", { state: { mode: result.mode || effectiveMode } });
      } else if (result.action === "advanced" && result.game) {
        setGameState(result.game as GameStateData);
      }
    } catch (err) {
      console.error("Failed to advance time:", err);
    } finally {
      setIsAdvancing(false);
    }
  };

  const handleConfirmMatch = () => {
    // Force-call handleContinue bypassing the confirmation guard
    setShowMatchConfirm(false);
    setIsAdvancing(true);
    setShowContinueMenu(false);
    (async () => {
      try {
        const result = await invoke<{ action: string; game?: GameStateData; snapshot?: unknown; fixture_index?: number; mode?: string }>("advance_time_with_mode", { mode: matchMode });
        if (result.action === "live_match") {
          navigate("/match", { state: { mode: result.mode || matchMode } });
        } else if (result.action === "advanced" && result.game) {
          setGameState(result.game as GameStateData);
        }
      } catch (err) {
        console.error("Failed to advance time:", err);
      } finally {
        setIsAdvancing(false);
      }
    })();
  };

  const MODE_META: Record<string, { label: string; icon: React.ReactNode; desc: string; color: string }> = {
    live: { label: t('continueMenu.goToField'), icon: <Gamepad2 className="w-4 h-4" />, desc: t('continueMenu.goToFieldDesc'), color: 'from-primary-500 to-primary-600' },
    spectator: { label: t('continueMenu.watchSpectator'), icon: <Eye className="w-4 h-4" />, desc: t('continueMenu.watchSpectatorDesc'), color: 'from-indigo-500 to-indigo-600' },
    delegate: { label: t('continueMenu.delegateAssistant'), icon: <Cpu className="w-4 h-4" />, desc: t('continueMenu.delegateAssistantDesc'), color: 'from-amber-500 to-amber-600' },
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

  const LANG_LOCALE: Record<string, string> = { en: "en-US", es: "es-ES", pt: "pt-BR", fr: "fr-FR", de: "de-DE" };
  const uiLocale = LANG_LOCALE[settings.language] || settings.language || "en-US";
  const currentDate = new Date(gameState.clock.current_date).toLocaleDateString(uiLocale, {
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
          <NavItem icon={<Briefcase />} label={t('dashboard.home')} active={activeTab === "Home"} onClick={() => handleNavClick("Home")} />
          <NavItem icon={<Mail />} label={t('dashboard.inbox')} badge={unreadMessagesCount > 0 ? unreadMessagesCount : undefined} active={activeTab === "Inbox"} onClick={() => handleNavClick("Inbox")} />
          <NavItem icon={<User />} label={t('dashboard.manager')} active={activeTab === "Manager"} onClick={() => handleNavClick("Manager")} />

          <p className="text-[10px] text-gray-500 uppercase tracking-widest font-heading px-3 pt-3 pb-1">{t('dashboard.sectionClub')}</p>
          <NavItem icon={<Users />} label={t('dashboard.squad')} active={activeTab === "Squad"} onClick={() => handleNavClick("Squad")} />
          <NavItem icon={<Crosshair />} label={t('dashboard.tactics')} active={activeTab === "Tactics"} onClick={() => handleNavClick("Tactics")} />
          <NavItem icon={<Dumbbell />} label={t('dashboard.training')} active={activeTab === "Training"} onClick={() => handleNavClick("Training")} />
          <NavItem icon={<UserCog />} label={t('dashboard.staff')} active={activeTab === "Staff"} onClick={() => handleNavClick("Staff")} />
          <NavItem icon={<Eye />} label="Scouting" active={activeTab === "Scouting"} onClick={() => handleNavClick("Scouting")} />
          <NavItem icon={<DollarSign />} label={t('dashboard.finances')} active={activeTab === "Finances"} onClick={() => handleNavClick("Finances")} />
          <NavItem icon={<TrendingUp />} label={t('dashboard.transfers')} active={activeTab === "Transfers"} onClick={() => handleNavClick("Transfers")} />

          <p className="text-[10px] text-gray-500 uppercase tracking-widest font-heading px-3 pt-3 pb-1">{t('dashboard.sectionWorld')}</p>
          <NavItem icon={<UsersRound />} label={t('dashboard.players')} active={activeTab === "Players"} onClick={() => handleNavClick("Players")} />
          <NavItem icon={<Building2 />} label={t('dashboard.teams')} active={activeTab === "Teams"} onClick={() => handleNavClick("Teams")} />
          <NavItem icon={<Trophy />} label={t('dashboard.tournaments')} active={activeTab === "Tournaments"} onClick={() => handleNavClick("Tournaments")} />
          <NavItem icon={<CalendarIcon />} label={t('dashboard.schedule')} active={activeTab === "Schedule"} onClick={() => handleNavClick("Schedule")} />
          <NavItem icon={<Newspaper />} label={t('dashboard.news')} active={activeTab === "News"} onClick={() => handleNavClick("News")} />
        </nav>
        
        {/* Settings & Exit */}
        <div className="p-3 border-t border-navy-700 flex flex-col gap-1">
          <button 
            onClick={() => navigate("/settings", { state: { from: "/dashboard" } })}
            className="flex items-center gap-3 w-full p-3 hover:bg-white/5 rounded-lg transition-colors text-gray-500 hover:text-gray-300"
          >
            <Settings className="w-5 h-5" />
            <span className="font-heading text-sm uppercase tracking-wider">{t('dashboard.settings')}</span>
          </button>
          <button 
            onClick={() => setShowExitConfirm(true)}
            className="flex items-center gap-3 w-full p-3 hover:bg-red-500/10 rounded-lg transition-colors text-gray-500 hover:text-red-400"
          >
            <LogOut className="w-5 h-5" />
            <span className="font-heading text-sm uppercase tracking-wider">{t('dashboard.exitToMenu')}</span>
          </button>
        </div>
      </aside>

      {/* Exit Confirmation Modal */}
      {showExitConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm">
          <div className="bg-white dark:bg-navy-800 rounded-2xl shadow-2xl border border-gray-200 dark:border-navy-600 w-full max-w-sm p-6 mx-4">
            <h3 className="text-lg font-heading font-bold uppercase tracking-wide text-gray-900 dark:text-white">
              {t('exitConfirm.title')}
            </h3>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              {t('exitConfirm.message')}
            </p>
            <div className="flex gap-3 mt-6">
              <button
                onClick={() => setShowExitConfirm(false)}
                className="flex-1 py-2.5 px-4 bg-gray-100 dark:bg-navy-700 hover:bg-gray-200 dark:hover:bg-navy-600 text-gray-700 dark:text-gray-300 font-heading font-bold text-sm uppercase tracking-wider rounded-lg transition-colors"
              >
                {t('exitConfirm.cancel')}
              </button>
              <button
                onClick={() => { setShowExitConfirm(false); handleExitToMenu(); }}
                className="flex-1 py-2.5 px-4 bg-red-500 hover:bg-red-600 text-white font-heading font-bold text-sm uppercase tracking-wider rounded-lg transition-colors"
              >
                {t('exitConfirm.saveExit')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Match Confirmation Modal */}
      {showMatchConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm">
          <div className="bg-white dark:bg-navy-800 rounded-2xl shadow-2xl border border-gray-200 dark:border-navy-600 w-full max-w-md p-6 mx-4">
            <div className="flex items-center gap-3 mb-4">
              <div className={`w-10 h-10 rounded-xl bg-gradient-to-br ${MODE_META[matchMode]?.color} flex items-center justify-center text-white`}>
                {MODE_META[matchMode]?.icon}
              </div>
              <div>
                <h3 className="text-lg font-heading font-bold uppercase tracking-wide text-gray-900 dark:text-white">
                  {t('continueMenu.matchDayTitle', 'Match Day')}
                </h3>
                <p className="text-xs text-gray-500 dark:text-gray-400">
                  {MODE_META[matchMode]?.label}
                </p>
              </div>
            </div>
            {(() => {
              const today = gameState!.clock.current_date.split('T')[0];
              const fixture = gameState!.league?.fixtures.find(f =>
                f.date === today && f.status === 'Scheduled'
                && (f.home_team_id === gameState!.manager.team_id || f.away_team_id === gameState!.manager.team_id)
              );
              if (!fixture) return null;
              const homeName = getTeamName(gameState!.teams, fixture.home_team_id);
              const awayName = getTeamName(gameState!.teams, fixture.away_team_id);
              return (
                <div className="bg-gray-50 dark:bg-navy-700 rounded-xl p-4 mb-4 text-center">
                  <p className="text-xs font-heading uppercase tracking-widest text-gray-400 mb-2">{t('common.matchday', { n: fixture.matchday })}</p>
                  <p className="text-lg font-heading font-bold text-gray-900 dark:text-white">
                    {homeName} <span className="text-gray-400 mx-2">{t('common.vs')}</span> {awayName}
                  </p>
                </div>
              );
            })()}
            <p className="text-sm text-gray-500 dark:text-gray-400 mb-1">{MODE_META[matchMode]?.desc}</p>
            {matchMode === 'delegate' && (
              <p className="text-xs text-amber-500 dark:text-amber-400 flex items-center gap-1 mt-1">
                <AlertCircle className="w-3.5 h-3.5" />
                {t('continueMenu.delegateWarning', 'Your assistant will manage the match. You won\'t be able to intervene.')}
              </p>
            )}
            <div className="flex gap-3 mt-5">
              <button
                onClick={() => setShowMatchConfirm(false)}
                className="flex-1 py-2.5 px-4 bg-gray-100 dark:bg-navy-700 hover:bg-gray-200 dark:hover:bg-navy-600 text-gray-700 dark:text-gray-300 font-heading font-bold text-sm uppercase tracking-wider rounded-lg transition-colors"
              >
                {t('common.cancel')}
              </button>
              <button
                onClick={handleConfirmMatch}
                className={`flex-1 py-2.5 px-4 bg-gradient-to-r ${MODE_META[matchMode]?.color} hover:brightness-110 text-white font-heading font-bold text-sm uppercase tracking-wider rounded-lg transition-all flex items-center justify-center gap-2`}
              >
                {MODE_META[matchMode]?.icon}
                {t('common.confirm')}
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
              placeholder={t('dashboard.searchPlaceholder')}
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

            {/* Continue button with dropdown — shows current mode */}
            <div className="relative">
              <div className="flex">
                <button 
                  onClick={() => handleContinue()}
                  disabled={isAdvancing || seasonComplete}
                  className={`bg-gradient-to-r ${MODE_META[matchMode]?.color || 'from-primary-500 to-primary-600'} hover:brightness-110 text-white pl-4 pr-3 py-2.5 rounded-l-lg font-heading font-bold uppercase tracking-wider text-sm shadow-md hover:shadow-lg transition-all flex items-center gap-2 ${isAdvancing || seasonComplete ? 'opacity-70 cursor-wait' : ''}`}
                >
                  {seasonComplete ? (
                    <span>Season Complete</span>
                  ) : isAdvancing ? (
                    <span>{t('dashboard.simulating')}</span>
                  ) : (
                    <>
                      {MODE_META[matchMode]?.icon}
                      <span>{hasMatchToday ? MODE_META[matchMode]?.label : t('dashboard.continue')}</span>
                    </>
                  )}
                  <ChevronRight className={`w-4 h-4 ${isAdvancing ? 'animate-pulse' : ''}`} />
                </button>
                <button
                  onClick={() => setShowContinueMenu(!showContinueMenu)}
                  className={`bg-gradient-to-r ${matchMode === 'spectator' ? 'from-indigo-600 to-indigo-700' : matchMode === 'delegate' ? 'from-amber-600 to-amber-700' : 'from-primary-600 to-primary-700'} hover:brightness-110 text-white px-2 py-2.5 rounded-r-lg border-l border-white/20 transition-colors`}
                >
                  <ChevronDown className="w-4 h-4" />
                </button>
              </div>

              {/* Dropdown menu */}
              {showContinueMenu && (
                <div className="absolute right-0 top-full mt-1 w-64 bg-white dark:bg-navy-700 rounded-lg shadow-xl border border-gray-200 dark:border-navy-600 py-1 z-20">
                  {(["live", "spectator", "delegate"] as const).map(mode => (
                    <button
                      key={mode}
                      onClick={() => { setMatchMode(mode); setShowContinueMenu(false); }}
                      className={`w-full text-left px-4 py-2.5 hover:bg-gray-50 dark:hover:bg-navy-600 text-sm transition-colors flex items-center gap-3 ${matchMode === mode ? 'bg-gray-50 dark:bg-navy-600' : ''}`}
                    >
                      <span className={`${matchMode === mode ? 'text-primary-500' : 'text-gray-400'}`}>{MODE_META[mode]?.icon}</span>
                      <div className="flex-1">
                        <span className="font-heading font-bold text-gray-800 dark:text-gray-100 uppercase tracking-wide text-xs">{MODE_META[mode]?.label}</span>
                        <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">{MODE_META[mode]?.desc}</p>
                      </div>
                      {matchMode === mode && <span className="text-primary-500 text-xs font-bold">✓</span>}
                    </button>
                  ))}
                  <div className="border-t border-gray-200 dark:border-navy-600 my-1" />
                  <button
                    onClick={handleSkipToMatchDay}
                    className="w-full text-left px-4 py-2.5 hover:bg-gray-50 dark:hover:bg-navy-600 text-sm transition-colors"
                  >
                    <span className="font-heading font-bold text-gray-800 dark:text-gray-100 uppercase tracking-wide text-xs">{t('continueMenu.skipToMatchDay')}</span>
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">{t('continueMenu.skipToMatchDayDesc')}</p>
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
                onGameUpdate={setGameState}
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

          {/* End-of-season screen when all fixtures are complete */}
          {!selectedPlayerId && !selectedTeamId && seasonComplete && activeTab === "Home" && (
            <EndOfSeasonScreen gameState={gameState} onGameUpdate={setGameState} />
          )}

          {/* Tab content — hidden when a profile is open */}
          {!selectedPlayerId && !selectedTeamId && activeTab === "Home" && !seasonComplete && (
            <HomeTab gameState={gameState} onNavigate={handleNavigate} />
          )}

          {!selectedPlayerId && !selectedTeamId && activeTab === "Squad" && (
            <SquadTab gameState={gameState} managerId={gameState.manager.id} onSelectPlayer={selectPlayer} onGameUpdate={setGameState} />
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

          {!selectedPlayerId && !selectedTeamId && activeTab === "Scouting" && (
            <ScoutingTab gameState={gameState} onGameUpdate={setGameState} onSelectPlayer={selectPlayer} />
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
