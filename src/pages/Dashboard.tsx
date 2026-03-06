import { useEffect, useState, useCallback, useRef } from "react";
import { useNavigate } from "react-router-dom";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useGameStore, GameStateData } from "../store/gameStore";
import { Badge, ThemeToggle } from "../components/ui";
import PlayerProfile from "../components/PlayerProfile";
import TeamProfile from "../components/TeamProfile";
import DashboardSidebar from "../components/dashboard/DashboardSidebar";
import DashboardTabContent from "../components/dashboard/DashboardTabContent";
import { useAdvanceTime } from "../hooks/useAdvanceTime";
import { Calendar as CalendarIcon, ChevronRight, ChevronDown, Search, ArrowLeft, Eye, Cpu, Gamepad2, AlertCircle, Save } from "lucide-react";
import { getTeamName, formatDateFull } from "../lib/helpers";
import { useTranslation } from "react-i18next";
import { useSettingsStore } from "../store/settingsStore";

export default function Dashboard() {
  const navigate = useNavigate();
  const { hasActiveGame, managerName, gameState, setGameState, clearGame, isDirty, markClean } = useGameStore();
  const { t } = useTranslation();
  const { settings, loaded: settingsLoaded, loadSettings } = useSettingsStore();

  // Load settings on mount
  useEffect(() => {
    if (!settingsLoaded) loadSettings();
  }, [settingsLoaded, loadSettings]);
  const [isSaving, setIsSaving] = useState(false);
  const [saveFlash, setSaveFlash] = useState(false);
  const [activeTab, setActiveTab] = useState("Home");
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

  // Advance-time hook
  const {
    isAdvancing,
    showContinueMenu, setShowContinueMenu,
    showMatchConfirm, setShowMatchConfirm,
    matchMode, setMatchMode,
    blockerModal, setBlockerModal,
    handleContinue,
    handleConfirmMatch,
    handleSkipToMatchDay,
  } = useAdvanceTime(setGameState, hasMatchToday, settings.default_match_mode, settingsLoaded);

  const handleSave = useCallback(async () => {
    setIsSaving(true);
    try {
      await invoke("save_game");
      markClean();
      setSaveFlash(true);
      setTimeout(() => setSaveFlash(false), 2000);
    } catch (err) {
      console.error("Failed to save:", err);
    } finally {
      setIsSaving(false);
    }
  }, [markClean]);

  // Intercept window close to warn about unsaved changes
  const [showCloseConfirm, setShowCloseConfirm] = useState(false);
  const isClosingRef = useRef(false);
  useEffect(() => {
    const appWindow = getCurrentWindow();
    const unlisten = appWindow.onCloseRequested(async (event) => {
      if (isClosingRef.current) return;
      if (isDirty) {
        event.preventDefault();
        setShowCloseConfirm(true);
      }
    });
    return () => { unlisten.then(fn => fn()); };
  }, [isDirty]);

  const handleCloseQuit = async (save: boolean) => {
    isClosingRef.current = true;
    setShowCloseConfirm(false);
    if (save) {
      try {
        await invoke("save_game");
        markClean();
      } catch (err) {
        console.error("Auto-save on close failed:", err);
      }
    }
    await getCurrentWindow().destroy();
  };

  const MODE_META: Record<string, { label: string; icon: React.ReactNode; desc: string; color: string }> = {
    live: { label: t('continueMenu.goToField'), icon: <Gamepad2 className="w-4 h-4" />, desc: t('continueMenu.goToFieldDesc'), color: 'from-primary-500 to-primary-600' },
    spectator: { label: t('continueMenu.watchSpectator'), icon: <Eye className="w-4 h-4" />, desc: t('continueMenu.watchSpectatorDesc'), color: 'from-indigo-500 to-indigo-600' },
    delegate: { label: t('continueMenu.delegateAssistant'), icon: <Cpu className="w-4 h-4" />, desc: t('continueMenu.delegateAssistantDesc'), color: 'from-amber-500 to-amber-600' },
  };

  const handleNavClick = (tab: string) => {
    setNavHistory([]);
    setActiveTab(tab);
    setSelectedPlayerId(null);
    setSelectedTeamId(null);
    setInitialMessageId(null);
  };

  const handleNavigate = (tab: string, context?: { messageId?: string }) => {
    // Special: navigate to a team profile
    if (tab === "__selectTeam" && context?.messageId) {
      pushHistory();
      setSelectedTeamId(context.messageId);
      setSelectedPlayerId(null);
      return;
    }
    // Special: navigate to a player profile
    if (tab === "__selectPlayer" && context?.messageId) {
      pushHistory();
      setSelectedPlayerId(context.messageId);
      setSelectedTeamId(null);
      return;
    }
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
          <span className="text-gray-500 dark:text-gray-400 font-heading uppercase tracking-wider text-sm">{t('dashboard.loading')}</span>
        </div>
      </div>
    );
  }

  const currentDate = formatDateFull(gameState.clock.current_date, settings.language);
  const unreadMessagesCount = gameState.messages?.filter(m => !m.read).length || 0;
  const myTeamName = gameState.teams.find(tm => tm.id === gameState.manager.team_id)?.name ?? null;

  return (
    <div className="min-h-screen bg-gray-100 dark:bg-navy-900 flex transition-colors duration-300">
      <DashboardSidebar
        activeTab={activeTab}
        onNavClick={handleNavClick}
        unreadMessagesCount={unreadMessagesCount}
        managerName={managerName}
        teamName={myTeamName}
        onNavigateSettings={() => navigate("/settings", { state: { from: "/dashboard" } })}
        onExitClick={() => setShowExitConfirm(true)}
      />

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

      {/* Window Close Confirmation Modal */}
      {showCloseConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm">
          <div className="bg-white dark:bg-navy-800 rounded-2xl shadow-2xl border border-gray-200 dark:border-navy-600 w-full max-w-sm p-6 mx-4">
            <h3 className="text-lg font-heading font-bold uppercase tracking-wide text-gray-900 dark:text-white">
              {t('closeConfirm.title', 'Unsaved Changes')}
            </h3>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              {t('closeConfirm.message', 'You have unsaved changes. What would you like to do?')}
            </p>
            <div className="flex flex-col gap-2 mt-6">
              <button
                onClick={() => handleCloseQuit(true)}
                className="w-full py-2.5 px-4 bg-primary-500 hover:bg-primary-600 text-white font-heading font-bold text-sm uppercase tracking-wider rounded-lg transition-colors"
              >
                {t('closeConfirm.saveQuit', 'Save & Quit')}
              </button>
              <button
                onClick={() => handleCloseQuit(false)}
                className="w-full py-2.5 px-4 bg-red-500 hover:bg-red-600 text-white font-heading font-bold text-sm uppercase tracking-wider rounded-lg transition-colors"
              >
                {t('closeConfirm.quitNoSave', 'Quit Without Saving')}
              </button>
              <button
                onClick={() => setShowCloseConfirm(false)}
                className="w-full py-2.5 px-4 bg-gray-100 dark:bg-navy-700 hover:bg-gray-200 dark:hover:bg-navy-600 text-gray-700 dark:text-gray-300 font-heading font-bold text-sm uppercase tracking-wider rounded-lg transition-colors"
              >
                {t('common.cancel')}
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

      {/* Blocker Actions Modal */}
      {blockerModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm">
          <div className="bg-white dark:bg-navy-800 rounded-2xl shadow-2xl border border-gray-200 dark:border-navy-600 w-full max-w-md p-6 mx-4">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-xl bg-amber-500/20 flex items-center justify-center">
                <AlertCircle className="w-5 h-5 text-amber-500" />
              </div>
              <div>
                <h3 className="text-lg font-heading font-bold uppercase tracking-wide text-gray-900 dark:text-white">
                  {t('notifications.attentionRequired', 'Attention Required')}
                </h3>
                <p className="text-xs text-gray-500 dark:text-gray-400">
                  {t('notifications.resolveBeforeContinuing', 'Resolve these issues before continuing')}
                </p>
              </div>
            </div>
            <div className="flex flex-col gap-2 mb-5">
              {blockerModal.blockers.map(b => (
                <button
                  key={b.id}
                  onClick={() => { setBlockerModal(null); handleNavigate(b.tab); }}
                  className={`w-full text-left p-3 rounded-xl border transition-all hover:shadow-sm ${
                    b.severity === "warn"
                      ? "border-amber-500/30 bg-amber-500/5 hover:bg-amber-500/10"
                      : "border-blue-500/30 bg-blue-500/5 hover:bg-blue-500/10"
                  }`}
                >
                  <p className={`text-sm font-medium ${
                    b.severity === "warn" ? "text-amber-600 dark:text-amber-400" : "text-blue-600 dark:text-blue-400"
                  }`}>{b.text}</p>
                  <p className="text-[10px] font-heading uppercase tracking-widest text-gray-400 mt-1">
                    {t('notifications.goTo', 'Go to')} {b.tab} →
                  </p>
                </button>
              ))}
            </div>
            <div className="flex gap-3">
              <button
                onClick={() => setBlockerModal(null)}
                className="flex-1 py-2.5 px-4 bg-gray-100 dark:bg-navy-700 hover:bg-gray-200 dark:hover:bg-navy-600 text-gray-700 dark:text-gray-300 font-heading font-bold text-sm uppercase tracking-wider rounded-lg transition-colors"
              >
                {t('notifications.reviewIssues', 'Review Issues')}
              </button>
              {blockerModal.pendingAction && (
                <button
                  onClick={() => blockerModal.pendingAction!()}
                  className="flex-1 py-2.5 px-4 bg-amber-500 hover:bg-amber-600 text-white font-heading font-bold text-sm uppercase tracking-wider rounded-lg transition-colors"
                >
                  {t('notifications.continueAnyway', 'Continue Anyway')}
                </button>
              )}
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
                    return <p className="p-3 text-xs text-gray-400 dark:text-gray-500">{t('dashboard.noResults')}</p>;
                  }
                  return (
                    <>
                      {matchedTeams.length > 0 && (
                        <div>
                          <p className="px-3 pt-2 pb-1 text-xs font-heading font-bold uppercase tracking-wider text-gray-400 dark:text-gray-500">{t('dashboard.searchTeams')}</p>
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
                          <p className="px-3 pt-2 pb-1 text-xs font-heading font-bold uppercase tracking-wider text-gray-400 dark:text-gray-500">{t('dashboard.searchPlayers')}</p>
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

            {/* Save button */}
            <button
              onClick={handleSave}
              disabled={isSaving}
              className={`flex items-center gap-1.5 px-3 py-2.5 rounded-lg text-sm font-heading font-bold uppercase tracking-wider transition-all ${
                saveFlash
                  ? "bg-green-500 text-white"
                  : "bg-gray-200 dark:bg-navy-700 text-gray-600 dark:text-gray-300 hover:bg-gray-300 dark:hover:bg-navy-600"
              } ${isSaving ? "opacity-70 cursor-wait" : ""}`}
              title="Save game"
            >
              <Save className="w-4 h-4" />
              {saveFlash ? "Saved!" : isSaving ? "Saving..." : "Save"}
            </button>

            {/* Continue button with dropdown — shows current mode */}
            <div className="relative">
              <div className="flex">
                <button 
                  onClick={() => handleContinue()}
                  disabled={isAdvancing || seasonComplete}
                  className={`bg-gradient-to-r ${MODE_META[matchMode]?.color || 'from-primary-500 to-primary-600'} hover:brightness-110 text-white pl-4 pr-3 py-2.5 rounded-l-lg font-heading font-bold uppercase tracking-wider text-sm shadow-md hover:shadow-lg transition-all flex items-center gap-2 ${isAdvancing || seasonComplete ? 'opacity-70 cursor-wait' : ''}`}
                >
                  {seasonComplete ? (
                    <span>{t('endOfSeason.seasonComplete')}</span>
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
          {/* Global Notifications Banner */}
          {!selectedPlayerId && !selectedTeamId && gameState && (() => {
            const alerts: { id: string; text: string; tab: string; severity: "warn" | "info" }[] = [];
            const myTeam = gameState.teams.find(tm => tm.id === gameState.manager.team_id);
            const roster = myTeam ? gameState.players.filter(p => p.team_id === myTeam.id) : [];
            const exhausted = roster.filter(p => p.condition < 25).length;
            const injured = roster.filter(p => p.injury).length;
            const urgentUnread = (gameState.messages || []).filter(m => !m.read && m.priority === "Urgent").length;
            const startingXi = myTeam?.starting_xi_ids || [];
            const xiPlayersOnRoster = startingXi.filter(id => roster.some(p => p.id === id));
            const xiCount = xiPlayersOnRoster.length;
            const injuredInXi = xiPlayersOnRoster.filter(id => roster.find(p => p.id === id)?.injury).length;
            const healthyXiCount = xiCount - injuredInXi;

            if (exhausted >= 3) alerts.push({ id: "exhausted", text: `${exhausted} players in critical condition (<25%)`, tab: "Training", severity: "warn" });
            if (injured >= 2) alerts.push({ id: "injured", text: `${injured} players injured`, tab: "Squad", severity: "info" });
            // Only show XI alerts when a lineup has been explicitly saved
            if (startingXi.length > 0) {
              if (injuredInXi > 0) alerts.push({ id: "injured_xi", text: `${injuredInXi} injured player${injuredInXi > 1 ? "s" : ""} in Starting XI — replace them`, tab: "Squad", severity: "warn" });
              if (healthyXiCount < 11 && injuredInXi === 0 && roster.length >= 11) alerts.push({ id: "xi", text: "Starting XI incomplete — set your lineup", tab: "Squad", severity: "warn" });
            }
            if (urgentUnread > 0) alerts.push({ id: "urgent", text: `${urgentUnread} urgent message${urgentUnread > 1 ? "s" : ""} unread`, tab: "Inbox", severity: "warn" });
            if (hasMatchToday && startingXi.length > 0 && healthyXiCount < 11) alerts.push({ id: "matchxi", text: "Match today! Set your starting XI", tab: "Squad", severity: "warn" });

            if (alerts.length === 0) return null;
            return (
              <div className="mb-4 flex flex-col gap-1.5">
                {alerts.map(a => (
                  <button
                    key={a.id}
                    onClick={() => handleNavigate(a.tab)}
                    className={`flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
                      a.severity === "warn"
                        ? "bg-amber-500/10 text-amber-600 dark:text-amber-400 border border-amber-500/20 hover:bg-amber-500/20"
                        : "bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20 hover:bg-blue-500/20"
                    }`}
                  >
                    <AlertCircle className="w-3.5 h-3.5 flex-shrink-0" />
                    <span className="flex-1 text-left">{a.text}</span>
                    <ChevronRight className="w-3 h-3" />
                  </button>
                ))}
              </div>
            );
          })()}

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

          {/* Tab content — hidden when a profile is open */}
          {!selectedPlayerId && !selectedTeamId && (
            <DashboardTabContent
              activeTab={activeTab}
              gameState={gameState}
              seasonComplete={seasonComplete}
              initialMessageId={initialMessageId}
              onSelectPlayer={selectPlayer}
              onSelectTeam={selectTeam}
              onGameUpdate={setGameState}
              onNavigate={handleNavigate}
            />
          )}

        </div>
      </main>

    </div>
  );
}
