import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { GameStateData } from "../store/gameStore";
import { Badge } from "./ui";
import { Mail, MailOpen, ArrowLeft, Trophy, ClipboardList, Crosshair, TableProperties, TrendingUp, Landmark, Smile, Stethoscope, Dumbbell, DollarSign, FileText, ScanSearch, Newspaper, Info } from "lucide-react";
import { getTeamName } from "../lib/helpers";

interface InboxTabProps {
  gameState: GameStateData;
  onGameUpdate: (g: GameStateData) => void;
}

const CATEGORY_META: Record<string, { icon: React.ReactNode; color: string; label: string }> = {
  Welcome:        { icon: <Trophy className="w-4 h-4" />,         color: "text-primary-500",  label: "Welcome" },
  LeagueInfo:     { icon: <ClipboardList className="w-4 h-4" />,  color: "text-blue-500",     label: "League" },
  MatchPreview:   { icon: <Crosshair className="w-4 h-4" />,      color: "text-accent-500",   label: "Match" },
  MatchResult:    { icon: <TableProperties className="w-4 h-4" />,color: "text-accent-600",   label: "Result" },
  Transfer:       { icon: <TrendingUp className="w-4 h-4" />,     color: "text-purple-500",   label: "Transfer" },
  BoardDirective: { icon: <Landmark className="w-4 h-4" />,       color: "text-red-500",      label: "Board" },
  PlayerMorale:   { icon: <Smile className="w-4 h-4" />,          color: "text-yellow-500",   label: "Morale" },
  Injury:         { icon: <Stethoscope className="w-4 h-4" />,    color: "text-red-400",      label: "Injury" },
  Training:       { icon: <Dumbbell className="w-4 h-4" />,       color: "text-green-500",    label: "Training" },
  Finance:        { icon: <DollarSign className="w-4 h-4" />,     color: "text-emerald-500",  label: "Finance" },
  Contract:       { icon: <FileText className="w-4 h-4" />,       color: "text-indigo-500",   label: "Contract" },
  ScoutReport:    { icon: <ScanSearch className="w-4 h-4" />,     color: "text-cyan-500",     label: "Scout" },
  Media:          { icon: <Newspaper className="w-4 h-4" />,      color: "text-orange-500",   label: "Media" },
  System:         { icon: <Info className="w-4 h-4" />,           color: "text-gray-400",     label: "System" },
};

export default function InboxTab({ gameState, onGameUpdate }: InboxTabProps) {
  const allMessages = [...(gameState.messages || [])].reverse();
  const [selectedMsgId, setSelectedMsgId] = useState<string | null>(null);
  const [categoryFilter, setCategoryFilter] = useState<string | null>(null);

  const handleSelectMessage = async (msgId: string) => {
    setSelectedMsgId(msgId);
    const msg = allMessages.find(m => m.id === msgId);
    if (msg && !msg.read) {
      try { const g = await invoke<GameStateData>("mark_message_read", { messageId: msgId }); onGameUpdate(g); } catch {}
    }
  };

  const handleAction = async (msgId: string, actionId: string) => {
    try { const g = await invoke<GameStateData>("resolve_message_action", { messageId: msgId, actionId }); onGameUpdate(g); } catch {}
  };

  const categories = Array.from(new Set(allMessages.map(m => m.category)));
  const filteredMessages = categoryFilter === "__unread"
    ? allMessages.filter(m => !m.read)
    : categoryFilter
      ? allMessages.filter(m => m.category === categoryFilter)
      : allMessages;
  const unreadCount = allMessages.filter(m => !m.read).length;
  const selectedMessage = allMessages.find(m => m.id === selectedMsgId) || null;

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
          All ({allMessages.length})
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
            Unread ({unreadCount})
          </button>
        )}
        {categories.map(cat => {
          const meta = CATEGORY_META[cat] || CATEGORY_META.System;
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
              {meta.icon} {meta.label} ({count})
            </button>
          );
        })}
      </div>

      {/* Two-pane inbox layout */}
      <div className="flex-1 flex gap-0 rounded-xl overflow-hidden border border-gray-200 dark:border-navy-600 bg-white dark:bg-navy-800 min-h-0">
        {/* Message list pane */}
        <div className={`${selectedMessage ? "hidden md:flex" : "flex"} flex-col w-full md:w-96 md:min-w-[384px] border-r border-gray-200 dark:border-navy-600`}>
          {/* List header */}
          <div className="p-4 border-b border-gray-100 dark:border-navy-600 bg-gradient-to-r from-navy-700 to-navy-800 flex-shrink-0">
            <h3 className="text-sm font-heading font-bold text-white flex items-center gap-2 uppercase tracking-wide">
              <Mail className="w-4 h-4 text-accent-400" />
              Inbox
            </h3>
            <p className="text-xs text-gray-400 mt-0.5 font-heading uppercase tracking-wider">
              {filteredMessages.length} message{filteredMessages.length !== 1 ? "s" : ""}
            </p>
          </div>

          {/* Message list */}
          <div className="flex-1 overflow-y-auto">
            {filteredMessages.length === 0 ? (
              <div className="p-6 text-center">
                <MailOpen className="w-8 h-8 text-gray-300 dark:text-navy-600 mx-auto mb-2" />
                <p className="text-sm text-gray-400 dark:text-gray-500">No messages{categoryFilter ? " in this category" : ""}.</p>
              </div>
            ) : (
              filteredMessages.map(message => {
                const meta = CATEGORY_META[message.category] || CATEGORY_META.System;
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
                      isSelected ? meta.color + " bg-primary-500/10" :
                      message.read ? "text-gray-400 bg-gray-100 dark:bg-navy-600" : meta.color + " bg-primary-500/10 dark:bg-primary-500/20"
                    }`}>
                      {meta.icon}
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
                  <ArrowLeft className="w-3.5 h-3.5" /> Back to inbox
                </button>
                <div className="flex items-start gap-3">
                  <div className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 ${
                    (CATEGORY_META[selectedMessage.category] || CATEGORY_META.System).color
                  } bg-primary-500/10 dark:bg-primary-500/20`}>
                    {(CATEGORY_META[selectedMessage.category] || CATEGORY_META.System).icon}
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
                      <Badge variant="neutral" size="sm">{(CATEGORY_META[selectedMessage.category] || CATEGORY_META.System).label}</Badge>
                      {selectedMessage.priority === "Urgent" && <Badge variant="danger" size="sm">Urgent</Badge>}
                      {selectedMessage.priority === "High" && <Badge variant="accent" size="sm">Important</Badge>}
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

                  {/* Action buttons */}
                  {selectedMessage.actions.length > 0 && (
                    <div className="mt-6 flex gap-2 flex-wrap">
                      {selectedMessage.actions.map(action => (
                        <button
                          key={action.id}
                          disabled={action.resolved}
                          onClick={() => handleAction(selectedMessage.id, action.id)}
                          className={`px-5 py-2.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
                            action.resolved
                              ? "bg-gray-100 dark:bg-navy-700 text-gray-400 dark:text-gray-500 cursor-default"
                              : action.action_type === "Acknowledge" || action.action_type === "Dismiss"
                                ? "bg-gray-200 dark:bg-navy-600 text-gray-700 dark:text-gray-300 hover:bg-gray-300 dark:hover:bg-navy-500"
                                : "bg-primary-500 text-white hover:bg-primary-600 shadow-sm hover:shadow-md hover:shadow-primary-500/20"
                          }`}
                        >
                          {action.resolved ? `✓ ${action.label}` : action.label}
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            </>
          ) : (
            <div className="flex-1 flex items-center justify-center">
              <div className="text-center">
                <MailOpen className="w-12 h-12 text-gray-300 dark:text-navy-600 mx-auto mb-3" />
                <p className="text-sm text-gray-400 dark:text-gray-500 font-heading uppercase tracking-wider">Select a message to read</p>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
