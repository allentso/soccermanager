import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { GameStateData } from "../store/gameStore";
import { Badge } from "./ui";
import { Mail, MailOpen, ArrowLeft, Trophy, ClipboardList, Crosshair, TableProperties, TrendingUp, Landmark, Smile, Stethoscope, Dumbbell, DollarSign, FileText, ScanSearch, Newspaper, Info, MessageCircle, CheckCircle2, CheckCheck, Trash2 } from "lucide-react";
import { getTeamName } from "../lib/helpers";
import { useTranslation } from "react-i18next";
import { resolveMessage } from "../utils/backendI18n";

interface InboxTabProps {
  gameState: GameStateData;
  onGameUpdate: (g: GameStateData) => void;
  initialMessageId?: string | null;
  onNavigate?: (tab: string, context?: { messageId?: string }) => void;
}

const CATEGORY_ICONS: Record<string, React.ReactNode> = {
  Welcome: <Trophy className="w-4 h-4" />, LeagueInfo: <ClipboardList className="w-4 h-4" />,
  MatchPreview: <Crosshair className="w-4 h-4" />, MatchResult: <TableProperties className="w-4 h-4" />,
  Transfer: <TrendingUp className="w-4 h-4" />, BoardDirective: <Landmark className="w-4 h-4" />,
  PlayerMorale: <Smile className="w-4 h-4" />, Injury: <Stethoscope className="w-4 h-4" />,
  Training: <Dumbbell className="w-4 h-4" />, Finance: <DollarSign className="w-4 h-4" />,
  Contract: <FileText className="w-4 h-4" />, ScoutReport: <ScanSearch className="w-4 h-4" />,
  Media: <Newspaper className="w-4 h-4" />, System: <Info className="w-4 h-4" />,
};
const CATEGORY_COLORS: Record<string, string> = {
  Welcome: "text-primary-500", LeagueInfo: "text-blue-500", MatchPreview: "text-accent-500",
  MatchResult: "text-accent-600", Transfer: "text-purple-500", BoardDirective: "text-red-500",
  PlayerMorale: "text-yellow-500", Injury: "text-red-400", Training: "text-green-500",
  Finance: "text-emerald-500", Contract: "text-indigo-500", ScoutReport: "text-cyan-500",
  Media: "text-orange-500", System: "text-gray-400",
};

export default function InboxTab({ gameState, onGameUpdate, initialMessageId, onNavigate }: InboxTabProps) {
  const { t } = useTranslation();
  const allMessages = [...(gameState.messages || [])].reverse().map(resolveMessage);
  const [selectedMsgId, setSelectedMsgId] = useState<string | null>(initialMessageId || null);
  const [categoryFilter, setCategoryFilter] = useState<string | null>(null);
  const [effectFeedback, setEffectFeedback] = useState<string | null>(null);

  const handleSelectMessage = async (msgId: string) => {
    setSelectedMsgId(msgId);
    const msg = allMessages.find(m => m.id === msgId);
    if (msg && !msg.read) {
      try { const g = await invoke<GameStateData>("mark_message_read", { messageId: msgId }); onGameUpdate(g); } catch {}
    }
  };

  const handleAction = async (msgId: string, actionId: string, optionId?: string) => {
    // Check if the action is a NavigateTo type
    const msg = allMessages.find(m => m.id === msgId);
    const action = msg?.actions.find(a => a.id === actionId);
    if (action && typeof action.action_type === "object" && "NavigateTo" in action.action_type) {
      const route = (action.action_type as { NavigateTo: { route: string } }).NavigateTo.route;
      // Parse dashboard tab from routes like "/dashboard?tab=Squad"
      const tabMatch = route.match(/[?&]tab=([^&]+)/i);
      if (tabMatch) {
        onNavigate?.(tabMatch[1]);
      } else {
        // Map simple route names to dashboard tab names
        const routeMap: Record<string, string> = {
          "squad": "Squad", "tactics": "Tactics", "training": "Training",
          "schedule": "Schedule", "finances": "Finances", "transfers": "Transfers",
          "players": "Players", "teams": "Teams", "tournaments": "Tournaments",
          "staff": "Staff", "inbox": "Inbox", "manager": "Manager", "home": "Home",
        };
        const simple = route.replace(/^\/+/, "").split(/[/?#]/)[0].toLowerCase();
        const tab = routeMap[simple] || "Home";
        onNavigate?.(tab);
      }
    }
    try {
      const result = await invoke<{ game: GameStateData; effect: string | null }>("resolve_message_action", {
        messageId: msgId, actionId, optionId: optionId || null
      });
      onGameUpdate(result.game);
      if (result.effect) {
        setEffectFeedback(result.effect);
        setTimeout(() => setEffectFeedback(null), 4000);
      }
    } catch {}
  };

  const categories = Array.from(new Set(allMessages.map(m => m.category)));
  const filteredMessages = categoryFilter === "__unread"
    ? allMessages.filter(m => !m.read)
    : categoryFilter
      ? allMessages.filter(m => m.category === categoryFilter)
      : allMessages;
  const unreadCount = allMessages.filter(m => !m.read).length;
  const selectedMessage = allMessages.find(m => m.id === selectedMsgId) || null;

  const handleMarkAllRead = async () => {
    try { const g = await invoke<GameStateData>("mark_all_messages_read"); onGameUpdate(g); } catch {}
  };
  const handleClearOld = async () => {
    try { const g = await invoke<GameStateData>("clear_old_messages"); onGameUpdate(g); setSelectedMsgId(null); } catch {}
  };

  return (
    <div className="max-w-6xl mx-auto flex flex-col h-full">
      {/* Filter bar */}
      <div className="flex gap-2 mb-4 flex-wrap flex-shrink-0">
        <button
          onClick={() => { setCategoryFilter(null); }}
          className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
            !categoryFilter
              ? "bg-primary-500 text-white shadow-sm"
              : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600 hover:text-gray-700 dark:hover:text-gray-200"
          }`}
        >
          {t('common.all')} ({allMessages.length})
        </button>
        {unreadCount > 0 && (
          <button
            onClick={() => setCategoryFilter("__unread")}
            className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
              categoryFilter === "__unread"
                ? "bg-primary-500 text-white shadow-sm"
                : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600 hover:text-gray-700 dark:hover:text-gray-200"
            }`}
          >
            {t('inbox.unread', { count: unreadCount })}
          </button>
        )}
        {categories.map(cat => {
          const catIcon = CATEGORY_ICONS[cat] || CATEGORY_ICONS.System;
          const count = allMessages.filter(m => m.category === cat).length;
          return (
            <button
              key={cat}
              onClick={() => setCategoryFilter(cat === categoryFilter ? null : cat)}
              className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all flex items-center gap-1.5 ${
                categoryFilter === cat
                  ? "bg-primary-500 text-white shadow-sm"
                  : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600 hover:text-gray-700 dark:hover:text-gray-200"
              }`}
            >
              {catIcon} {t(`inbox.categories.${cat}`)} ({count})
            </button>
          );
        })}

        {/* Inbox management actions */}
        <div className="ml-auto flex items-center gap-2">
          {unreadCount > 0 && (
            <button
              onClick={handleMarkAllRead}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600 hover:text-primary-500 hover:border-primary-300 transition-all"
            >
              <CheckCheck className="w-3.5 h-3.5" /> Mark all read
            </button>
          )}
          <button
            onClick={handleClearOld}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600 hover:text-red-500 hover:border-red-300 transition-all"
          >
            <Trash2 className="w-3.5 h-3.5" /> Clear old
          </button>
        </div>
      </div>

      {/* Two-pane inbox layout */}
      <div className="flex-1 flex gap-0 rounded-xl overflow-hidden border border-gray-200 dark:border-navy-600 bg-white dark:bg-navy-800 min-h-0">
        {/* Message list pane */}
        <div className={`${selectedMessage ? "hidden md:flex" : "flex"} flex-col w-full md:w-96 md:min-w-[384px] border-r border-gray-200 dark:border-navy-600`}>
          {/* List header */}
          <div className="p-4 border-b border-gray-100 dark:border-navy-600 bg-gradient-to-r from-navy-700 to-navy-800 flex-shrink-0">
            <h3 className="text-sm font-heading font-bold text-white flex items-center gap-2 uppercase tracking-wide">
              <Mail className="w-4 h-4 text-accent-400" />
              {t('inbox.title')}
            </h3>
            <p className="text-xs text-gray-400 mt-0.5 font-heading uppercase tracking-wider">
              {t('inbox.nMessages', { count: filteredMessages.length })}
            </p>
          </div>

          {/* Message list */}
          <div className="flex-1 overflow-y-auto">
            {filteredMessages.length === 0 ? (
              <div className="p-6 text-center">
                <MailOpen className="w-8 h-8 text-gray-300 dark:text-navy-600 mx-auto mb-2" />
                <p className="text-sm text-gray-400 dark:text-gray-500">{categoryFilter ? t('inbox.noMessagesInCategory') : t('inbox.noMessages')}</p>
              </div>
            ) : (
              filteredMessages.map(message => {
                const catIcon = CATEGORY_ICONS[message.category] || CATEGORY_ICONS.System;
                const catColor = CATEGORY_COLORS[message.category] || CATEGORY_COLORS.System;
                const isSelected = selectedMsgId === message.id;
                return (
                  <div
                    key={message.id}
                    onClick={() => handleSelectMessage(message.id)}
                    className={`flex gap-3 px-4 py-3 cursor-pointer transition-colors border-b border-gray-100 dark:border-navy-600/50 ${
                      isSelected
                        ? "bg-primary-50 dark:bg-primary-500/10 border-l-2 border-l-primary-500"
                        : !message.read
                          ? "bg-white dark:bg-navy-800 border-l-2 border-l-accent-500 hover:bg-gray-50 dark:hover:bg-navy-700/50"
                          : "border-l-2 border-l-transparent hover:bg-gray-50 dark:hover:bg-navy-700/30"
                    }`}
                  >
                    <div className={`w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 ${
                      isSelected ? catColor + " bg-primary-500/10" :
                      message.read ? "text-gray-400 bg-gray-100 dark:bg-navy-600" : catColor + " bg-primary-500/10 dark:bg-primary-500/20"
                    }`}>
                      {catIcon}
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-1.5">
                        <h4 className={`text-sm truncate flex-1 ${!message.read ? "font-bold text-gray-900 dark:text-gray-100" : "font-medium text-gray-500 dark:text-gray-400"}`}>
                          {message.subject}
                        </h4>
                        {!message.read && <span className="w-2 h-2 rounded-full bg-primary-500 flex-shrink-0" />}
                      </div>
                      <p className="text-xs text-gray-400 dark:text-gray-500 truncate mt-0.5">{message.sender}</p>
                      <p className="text-xs text-gray-400 dark:text-gray-500 mt-0.5">{new Date(message.date).toLocaleDateString()}</p>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>

        {/* Detail pane */}
        <div className="flex-1 flex flex-col min-w-0">
          {selectedMessage ? (
            <>
              {/* Detail header */}
              <div className="p-5 border-b border-gray-100 dark:border-navy-600 flex-shrink-0">
                <button
                  onClick={() => setSelectedMsgId(null)}
                  className="md:hidden flex items-center gap-1.5 text-xs text-gray-500 dark:text-gray-400 hover:text-gray-800 dark:hover:text-gray-200 mb-3"
                >
                  <ArrowLeft className="w-3.5 h-3.5" /> {t('inbox.backToInbox')}
                </button>
                <div className="flex items-start gap-3">
                  <div className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 ${
                    CATEGORY_COLORS[selectedMessage.category] || CATEGORY_COLORS.System
                  } bg-primary-500/10 dark:bg-primary-500/20`}>
                    {CATEGORY_ICONS[selectedMessage.category] || CATEGORY_ICONS.System}
                  </div>
                  <div className="flex-1 min-w-0">
                    <h3 className="font-heading font-bold text-lg text-gray-900 dark:text-gray-100">{selectedMessage.subject}</h3>
                    <div className="flex items-center gap-3 mt-1">
                      <span className="text-sm font-medium text-gray-600 dark:text-gray-300">
                        {selectedMessage.sender}{selectedMessage.sender_role ? ` — ${selectedMessage.sender_role}` : ""}
                      </span>
                      <span className="text-xs text-gray-400 dark:text-gray-500">
                        {new Date(selectedMessage.date).toLocaleDateString(undefined, { weekday: "long", year: "numeric", month: "long", day: "numeric" })}
                      </span>
                    </div>
                    <div className="flex items-center gap-2 mt-1.5">
                      <Badge variant="neutral" size="sm">{t(`inbox.categories.${selectedMessage.category}`)}</Badge>
                      {selectedMessage.priority === "Urgent" && <Badge variant="danger" size="sm">{t('inbox.urgent')}</Badge>}
                      {selectedMessage.priority === "High" && <Badge variant="accent" size="sm">{t('inbox.important')}</Badge>}
                    </div>
                  </div>
                </div>
              </div>

              {/* Detail body */}
              <div className="flex-1 overflow-y-auto p-6">
                <div className="max-w-2xl">
                  {selectedMessage.body.split("\n").map((line, i) => (
                    <p key={i} className={`text-sm leading-relaxed mb-1 ${line.trim() === "" ? "h-3" : "text-gray-700 dark:text-gray-300"}`}>
                      {line.startsWith("•") ? (
                        <span className="flex items-start gap-2">
                          <span className="text-primary-500 mt-0.5">•</span>
                          <span>{line.replace("•", "").trim()}</span>
                        </span>
                      ) : line}
                    </p>
                  ))}

                  {/* Match result context */}
                  {selectedMessage.context?.match_result && (
                    <div className="mt-6 p-4 bg-gray-50 dark:bg-navy-700 rounded-xl flex items-center justify-center gap-8 border border-gray-100 dark:border-navy-600">
                      <span className="font-heading font-bold text-sm text-gray-700 dark:text-gray-200">
                        {getTeamName(gameState.teams, selectedMessage.context.match_result.home_team_id)}
                      </span>
                      <span className="font-heading font-bold text-2xl text-gray-800 dark:text-gray-100">
                        {selectedMessage.context.match_result.home_goals} - {selectedMessage.context.match_result.away_goals}
                      </span>
                      <span className="font-heading font-bold text-sm text-gray-700 dark:text-gray-200">
                        {getTeamName(gameState.teams, selectedMessage.context.match_result.away_team_id)}
                      </span>
                    </div>
                  )}

                  {/* Effect feedback toast */}
                  {effectFeedback && (
                    <div className="mt-4 p-3 bg-primary-50 dark:bg-primary-500/10 border border-primary-200 dark:border-primary-500/30 rounded-xl flex items-center gap-2 animate-pulse">
                      <CheckCircle2 className="w-4 h-4 text-primary-500 flex-shrink-0" />
                      <span className="text-sm font-medium text-primary-700 dark:text-primary-300">{effectFeedback}</span>
                    </div>
                  )}

                  {/* Action buttons */}
                  {selectedMessage.actions.length > 0 && (
                    <div className="mt-6">
                      {selectedMessage.actions.map(action => {
                        // ChooseOption: render option cards
                        if (typeof action.action_type === "object" && "ChooseOption" in action.action_type) {
                          const opts = (action.action_type as { ChooseOption: { options: { id: string; label: string; description: string }[] } }).ChooseOption.options;
                          if (action.resolved) {
                            return (
                              <div key={action.id} className="flex items-center gap-2 text-sm text-gray-400 dark:text-gray-500 mt-2">
                                <CheckCircle2 className="w-4 h-4 text-primary-500" />
                                <span className="font-heading font-bold uppercase tracking-wider text-xs">{t('inbox.responded', 'Response sent')}</span>
                              </div>
                            );
                          }
                          return (
                            <div key={action.id} className="space-y-2">
                              <p className="text-xs font-heading font-bold uppercase tracking-widest text-gray-400 dark:text-gray-500 flex items-center gap-1.5 mb-3">
                                <MessageCircle className="w-3.5 h-3.5" />
                                {t('inbox.chooseResponse', 'Choose your response')}
                              </p>
                              {opts.map(opt => (
                                <button
                                  key={opt.id}
                                  onClick={() => handleAction(selectedMessage.id, action.id, opt.id)}
                                  className="w-full text-left p-4 rounded-xl border border-gray-200 dark:border-navy-600 hover:border-primary-400 dark:hover:border-primary-500 hover:bg-primary-50/50 dark:hover:bg-primary-500/5 transition-all group"
                                >
                                  <p className="text-sm font-heading font-bold text-gray-800 dark:text-gray-200 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors">{opt.label}</p>
                                  <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">{opt.description}</p>
                                </button>
                              ))}
                            </div>
                          );
                        }

                        // Standard button actions
                        return (
                          <button
                            key={action.id}
                            disabled={action.resolved}
                            onClick={() => handleAction(selectedMessage.id, action.id)}
                            className={`px-5 py-2.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all mr-2 mb-2 ${
                              action.resolved
                                ? "bg-gray-100 dark:bg-navy-700 text-gray-400 dark:text-gray-500 cursor-default"
                                : action.action_type === "Acknowledge" || action.action_type === "Dismiss"
                                  ? "bg-gray-200 dark:bg-navy-600 text-gray-700 dark:text-gray-300 hover:bg-gray-300 dark:hover:bg-navy-500"
                                  : "bg-primary-500 text-white hover:bg-primary-600 shadow-sm hover:shadow-md hover:shadow-primary-500/20"
                            }`}
                          >
                            {action.resolved ? `✓ ${action.label}` : action.label}
                          </button>
                        );
                      })}
                    </div>
                  )}
                </div>
              </div>
            </>
          ) : (
            <div className="flex-1 flex items-center justify-center">
              <div className="text-center">
                <MailOpen className="w-12 h-12 text-gray-300 dark:text-navy-600 mx-auto mb-3" />
                <p className="text-sm text-gray-400 dark:text-gray-500 font-heading uppercase tracking-wider">{t('inbox.selectMessage')}</p>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
