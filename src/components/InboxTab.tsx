import { useEffect, useMemo, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  ArrowLeft,
  CheckCheck,
  CheckCircle2,
  ClipboardList,
  Crosshair,
  DollarSign,
  Dumbbell,
  FileText,
  Info,
  Landmark,
  Mail,
  MailOpen,
  MessageCircle,
  Newspaper,
  ScanSearch,
  Smile,
  Stethoscope,
  TableProperties,
  Trash2,
  TrendingUp,
  Trophy,
} from "lucide-react";
import type { ChangeEvent, JSX, ReactNode } from "react";
import { useTranslation } from "react-i18next";

import { formatDateFull, formatDateShort, getTeamName } from "../lib/helpers";
import type {
  GameStateData,
  MessageAction,
  MessageData,
} from "../store/gameStore";
import { resolveBackendText, resolveMessage } from "../utils/backendI18n";
import DashboardModalFrame from "./dashboard/DashboardModalFrame";
import ScoutPlayerCard from "./ScoutPlayerCard";
import { Badge, Button, Select } from "./ui";

interface InboxTabProps {
  gameState: GameStateData;
  onGameUpdate: (g: GameStateData) => void;
  initialMessageId?: string | null;
  onNavigate?: (tab: string, context?: { messageId?: string }) => void;
}

interface NavigateActionType {
  NavigateTo: { route: string };
}

interface ChooseOptionActionType {
  ChooseOption: {
    options: { id: string; label: string; description: string }[];
  };
}

interface NavigationTarget {
  tab: string;
  context?: { messageId?: string };
  shouldResolveAction: boolean;
}

interface ResolveMessageActionResult {
  game: GameStateData;
  effect: string | null;
  effect_i18n_key?: string | null;
  effect_i18n_params?: Record<string, string> | null;
}

type MessageSortOrder = "newest" | "oldest";

type DeleteModalState =
  | { mode: "single"; messageId: string; subject: string }
  | { mode: "bulk"; messageIds: string[] }
  | null;

const UNREAD_FILTER = "__unread";
const FILTER_BUTTON_BASE_CLASS =
  "px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all";
const FILTER_BUTTON_ACTIVE_CLASS = "bg-primary-500 text-white shadow-sm";
const FILTER_BUTTON_INACTIVE_CLASS =
  "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600 hover:text-gray-700 dark:hover:text-gray-200";
const ROUTE_TAB_MAP: Record<string, string> = {
  squad: "Squad",
  tactics: "Tactics",
  training: "Training",
  schedule: "Schedule",
  finances: "Finances",
  transfers: "Transfers",
  players: "Players",
  teams: "Teams",
  tournaments: "Tournaments",
  staff: "Staff",
  inbox: "Inbox",
  manager: "Manager",
  home: "Home",
};

const PLAYER_EVENT_MESSAGE_PREFIXES = [
  "morale_talk_",
  "bench_complaint_",
  "happy_player_",
  "contract_concern_",
];

const CATEGORY_ICONS: Record<string, ReactNode> = {
  Welcome: <Trophy className="w-4 h-4" />,
  LeagueInfo: <ClipboardList className="w-4 h-4" />,
  MatchPreview: <Crosshair className="w-4 h-4" />,
  MatchResult: <TableProperties className="w-4 h-4" />,
  Transfer: <TrendingUp className="w-4 h-4" />,
  BoardDirective: <Landmark className="w-4 h-4" />,
  PlayerMorale: <Smile className="w-4 h-4" />,
  Injury: <Stethoscope className="w-4 h-4" />,
  Training: <Dumbbell className="w-4 h-4" />,
  Finance: <DollarSign className="w-4 h-4" />,
  Contract: <FileText className="w-4 h-4" />,
  ScoutReport: <ScanSearch className="w-4 h-4" />,
  Media: <Newspaper className="w-4 h-4" />,
  System: <Info className="w-4 h-4" />,
};
const CATEGORY_COLORS: Record<string, string> = {
  Welcome: "text-primary-500",
  LeagueInfo: "text-blue-500",
  MatchPreview: "text-accent-500",
  MatchResult: "text-accent-600",
  Transfer: "text-purple-500",
  BoardDirective: "text-red-500",
  PlayerMorale: "text-yellow-500",
  Injury: "text-red-400",
  Training: "text-green-500",
  Finance: "text-emerald-500",
  Contract: "text-indigo-500",
  ScoutReport: "text-cyan-500",
  Media: "text-orange-500",
  System: "text-gray-400",
};

function getCategoryIcon(category: string): ReactNode {
  return CATEGORY_ICONS[category] ?? CATEGORY_ICONS.System;
}

function getCategoryColor(category: string): string {
  return CATEGORY_COLORS[category] ?? CATEGORY_COLORS.System;
}

function getFilterButtonClassName(
  isActive: boolean,
  extraClasses = "",
): string {
  let className = FILTER_BUTTON_BASE_CLASS;

  if (extraClasses.length > 0) {
    className = `${className} ${extraClasses}`;
  }

  if (isActive) {
    return `${className} ${FILTER_BUTTON_ACTIVE_CLASS}`;
  }

  return `${className} ${FILTER_BUTTON_INACTIVE_CLASS}`;
}

function getFilteredMessages(
  messages: MessageData[],
  categoryFilter: string | null,
): MessageData[] {
  if (categoryFilter === UNREAD_FILTER) {
    return messages.filter((message) => !message.read);
  }

  if (categoryFilter) {
    return messages.filter((message) => message.category === categoryFilter);
  }

  return messages;
}

function getMessageDateValue(date: string): number {
  const value = Date.parse(date);

  if (Number.isNaN(value)) {
    return 0;
  }

  return value;
}

function sortInboxMessages(
  messages: MessageData[],
  sortOrder: MessageSortOrder,
): MessageData[] {
  return [...messages].sort((leftMessage, rightMessage) => {
    const leftDateValue = getMessageDateValue(leftMessage.date);
    const rightDateValue = getMessageDateValue(rightMessage.date);

    if (sortOrder === "oldest") {
      return leftDateValue - rightDateValue;
    }

    return rightDateValue - leftDateValue;
  });
}

function getListPaneClassName(hasSelectedMessage: boolean): string {
  const visibilityClassName = hasSelectedMessage ? "hidden md:flex" : "flex";

  return `${visibilityClassName} flex-col w-full md:w-96 md:min-w-[384px] border-r border-gray-200 dark:border-navy-600`;
}

function getMessageRowClassName(isSelected: boolean, isRead: boolean): string {
  const baseClassName =
    "flex gap-3 px-4 py-3 cursor-pointer transition-colors border-b border-gray-100 dark:border-navy-600/50";

  if (isSelected) {
    return `${baseClassName} bg-primary-50 dark:bg-primary-500/10 border-l-2 border-l-primary-500`;
  }

  if (!isRead) {
    return `${baseClassName} bg-white dark:bg-navy-800 border-l-2 border-l-accent-500 hover:bg-gray-50 dark:hover:bg-navy-700/50`;
  }

  return `${baseClassName} border-l-2 border-l-transparent hover:bg-gray-50 dark:hover:bg-navy-700/30`;
}

function getMessageIconClassName(
  categoryColor: string,
  isSelected: boolean,
  isRead: boolean,
): string {
  const baseClassName =
    "w-8 h-8 rounded-lg flex items-center justify-center shrink-0";

  if (isSelected) {
    return `${baseClassName} ${categoryColor} bg-primary-500/10`;
  }

  if (isRead) {
    return `${baseClassName} text-gray-400 bg-gray-100 dark:bg-navy-600`;
  }

  return `${baseClassName} ${categoryColor} bg-primary-500/10 dark:bg-primary-500/20`;
}

function getMessageSubjectClassName(isRead: boolean): string {
  if (isRead) {
    return "text-sm truncate flex-1 font-medium text-gray-500 dark:text-gray-400";
  }

  return "text-sm truncate flex-1 font-bold text-gray-900 dark:text-gray-100";
}

function getActionButtonClassName(action: MessageAction): string {
  const baseClassName =
    "px-5 py-2.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all mr-2 mb-2";

  if (action.resolved) {
    return `${baseClassName} bg-gray-100 dark:bg-navy-700 text-gray-400 dark:text-gray-500 cursor-default`;
  }

  if (
    action.action_type === "Acknowledge" ||
    action.action_type === "Dismiss"
  ) {
    return `${baseClassName} bg-gray-200 dark:bg-navy-600 text-gray-700 dark:text-gray-300 hover:bg-gray-300 dark:hover:bg-navy-500`;
  }

  return `${baseClassName} bg-primary-500 text-white hover:bg-primary-600 shadow-sm hover:shadow-md hover:shadow-primary-500/20`;
}

function renderMessageBodyLine(line: string, index: number): JSX.Element {
  const baseClassName = "text-sm leading-relaxed mb-1";

  if (line.trim() === "") {
    return (
      <p key={index} className={`${baseClassName} h-3`}>
        {line}
      </p>
    );
  }

  if (line.startsWith("•")) {
    return (
      <p
        key={index}
        className={`${baseClassName} text-gray-700 dark:text-gray-300`}
      >
        <span className="flex items-start gap-2">
          <span className="text-primary-500 mt-0.5">•</span>
          <span>{line.replace("•", "").trim()}</span>
        </span>
      </p>
    );
  }

  return (
    <p
      key={index}
      className={`${baseClassName} text-gray-700 dark:text-gray-300`}
    >
      {line}
    </p>
  );
}

function isNavigateAction(
  actionType: MessageAction["action_type"],
): actionType is NavigateActionType {
  return typeof actionType === "object" && "NavigateTo" in actionType;
}

function isChooseOptionAction(
  actionType: MessageAction["action_type"],
): actionType is ChooseOptionActionType {
  return typeof actionType === "object" && "ChooseOption" in actionType;
}

function getNavigationTarget(route: string): NavigationTarget {
  const teamMatch = route.match(/^\/team\/(.+)$/);

  if (teamMatch) {
    return {
      tab: "__selectTeam",
      context: { messageId: teamMatch[1] },
      shouldResolveAction: false,
    };
  }

  const tabMatch = route.match(/[?&]tab=([^&]+)/i);

  if (tabMatch) {
    return {
      tab: tabMatch[1],
      shouldResolveAction: true,
    };
  }

  const simpleRoute = route.replace(/^\/+/, "").split(/[/?#]/)[0].toLowerCase();
  const resolvedTab = ROUTE_TAB_MAP[simpleRoute] ?? "Home";

  return {
    tab: resolvedTab,
    shouldResolveAction: true,
  };
}

function isPlayerEventMessage(messageId: string): boolean {
  return PLAYER_EVENT_MESSAGE_PREFIXES.some((prefix) =>
    messageId.startsWith(prefix),
  );
}

function InboxDeleteConfirmModal({
  deleteModalState,
  isDeleting,
  onCancel,
  onConfirm,
}: {
  deleteModalState: DeleteModalState;
  isDeleting: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}): JSX.Element | null {
  const { t } = useTranslation();

  if (!deleteModalState) {
    return null;
  }

  const title =
    deleteModalState.mode === "single"
      ? t("inbox.deleteMessageTitle", "Delete message?")
      : t("inbox.deleteSelectedTitle", "Delete selected messages?");
  const message =
    deleteModalState.mode === "single"
      ? t(
          "inbox.deleteMessageBody",
          'This will permanently delete "{{subject}}". This action cannot be undone.',
          { subject: deleteModalState.subject },
        )
      : t(
          "inbox.deleteSelectedBody",
          "This will permanently delete {{count}} selected message(s). This action cannot be undone.",
          { count: deleteModalState.messageIds.length },
        );

  return (
    <DashboardModalFrame maxWidthClassName="max-w-md">
      <div className="space-y-4" data-testid="inbox-delete-confirm-modal">
        <div>
          <h3 className="text-lg font-heading font-bold text-gray-900 dark:text-gray-100">
            {title}
          </h3>
          <p className="mt-2 text-sm text-gray-600 dark:text-gray-300">
            {message}
          </p>
        </div>
        <div className="flex items-center justify-end gap-3">
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={onCancel}
            disabled={isDeleting}
          >
            {t("common.cancel", "Cancel")}
          </Button>
          <Button
            type="button"
            size="sm"
            onClick={onConfirm}
            disabled={isDeleting}
            className="bg-red-500 hover:bg-red-600 active:bg-red-700 focus:ring-red-500"
            data-testid="inbox-confirm-delete"
          >
            {t("inbox.deleteAction", "Delete")}
          </Button>
        </div>
      </div>
    </DashboardModalFrame>
  );
}

export default function InboxTab({
  gameState,
  onGameUpdate,
  initialMessageId,
  onNavigate,
}: InboxTabProps): JSX.Element {
  const { t, i18n } = useTranslation();
  const messages = gameState.messages ?? [];
  const allMessages = useMemo(() => messages.map(resolveMessage), [messages]);
  const [selectedMessageId, setSelectedMessageId] = useState<string | null>(
    initialMessageId || null,
  );
  const [categoryFilter, setCategoryFilter] = useState<string | null>(null);
  const [sortOrder, setSortOrder] = useState<MessageSortOrder>("newest");
  const [bulkSelectionEnabled, setBulkSelectionEnabled] = useState(false);
  const [selectedMessageIds, setSelectedMessageIds] = useState<string[]>([]);
  const [deleteModalState, setDeleteModalState] =
    useState<DeleteModalState>(null);
  const [effectFeedback, setEffectFeedback] = useState<string | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);
  const categoryCounts = new Map<string, number>();

  useEffect(() => {
    const availableMessageIds = new Set(
      allMessages.map((message) => message.id),
    );

    setSelectedMessageIds((currentIds) =>
      currentIds.filter((messageId) => availableMessageIds.has(messageId)),
    );

    if (selectedMessageId && !availableMessageIds.has(selectedMessageId)) {
      setSelectedMessageId(null);
    }
  }, [allMessages, selectedMessageId]);

  for (const message of allMessages) {
    const currentCount = categoryCounts.get(message.category) ?? 0;
    categoryCounts.set(message.category, currentCount + 1);
  }

  const categories = Array.from(categoryCounts.keys());
  const filteredMessages = useMemo(
    () =>
      sortInboxMessages(
        getFilteredMessages(allMessages, categoryFilter),
        sortOrder,
      ),
    [allMessages, categoryFilter, sortOrder],
  );
  const unreadCount = allMessages.filter((message) => !message.read).length;
  const selectedMessage =
    allMessages.find((message) => message.id === selectedMessageId) ?? null;

  async function handleSelectMessage(msgId: string): Promise<void> {
    setSelectedMessageId(msgId);
    const message = allMessages.find(
      (currentMessage) => currentMessage.id === msgId,
    );

    if (message && !message.read) {
      try {
        const g = await invoke<GameStateData>("mark_message_read", {
          messageId: msgId,
        });
        onGameUpdate(g);
      } catch {}
    }
  }

  async function handleAction(
    msgId: string,
    actionId: string,
    optionId?: string,
  ): Promise<void> {
    const message = allMessages.find(
      (currentMessage) => currentMessage.id === msgId,
    );
    const action = message?.actions.find(
      (currentAction) => currentAction.id === actionId,
    );

    if (action && isNavigateAction(action.action_type)) {
      const navigationTarget = getNavigationTarget(
        action.action_type.NavigateTo.route,
      );
      onNavigate?.(navigationTarget.tab, navigationTarget.context);

      if (!navigationTarget.shouldResolveAction) {
        return;
      }
    }

    try {
      const result = await invoke<ResolveMessageActionResult>(
        "resolve_message_action",
        {
          messageId: msgId,
          actionId,
          optionId: optionId || null,
        },
      );
      onGameUpdate(result.game);
      if (result.effect) {
        const resolvedEffect = resolveBackendText(
          result.effect_i18n_key ?? undefined,
          result.effect,
          result.effect_i18n_params ?? undefined,
        );
        setEffectFeedback(resolvedEffect);
        setTimeout(() => setEffectFeedback(null), 4000);
      }
    } catch {}
  }

  async function handleMarkAllRead(): Promise<void> {
    try {
      const g = await invoke<GameStateData>("mark_all_messages_read");
      onGameUpdate(g);
    } catch {}
  }

  async function handleClearOld(): Promise<void> {
    try {
      const g = await invoke<GameStateData>("clear_old_messages");
      onGameUpdate(g);
      setSelectedMessageId(null);
    } catch {}
  }

  async function handleConfirmDelete(): Promise<void> {
    if (!deleteModalState) {
      return;
    }

    setIsDeleting(true);

    try {
      let updatedGameState: GameStateData;
      let deletedMessageIds: string[];

      if (deleteModalState.mode === "single") {
        deletedMessageIds = [deleteModalState.messageId];
        updatedGameState = await invoke<GameStateData>("delete_message", {
          messageId: deleteModalState.messageId,
        });
      } else {
        deletedMessageIds = deleteModalState.messageIds;
        updatedGameState = await invoke<GameStateData>("delete_messages", {
          messageIds: deleteModalState.messageIds,
        });
        setBulkSelectionEnabled(false);
      }

      onGameUpdate(updatedGameState);
      setSelectedMessageIds((currentIds) =>
        currentIds.filter(
          (messageId) => !deletedMessageIds.includes(messageId),
        ),
      );

      if (selectedMessageId && deletedMessageIds.includes(selectedMessageId)) {
        setSelectedMessageId(null);
      }

      setDeleteModalState(null);
    } catch {
    } finally {
      setIsDeleting(false);
    }
  }

  function handleCloseDeleteModal(): void {
    if (isDeleting) {
      return;
    }

    setDeleteModalState(null);
  }

  function handleSortOrderChange(event: ChangeEvent<HTMLSelectElement>): void {
    setSortOrder(event.target.value as MessageSortOrder);
  }

  function handleToggleBulkSelectionMode(): void {
    setBulkSelectionEnabled((currentValue) => {
      if (currentValue) {
        setSelectedMessageIds([]);
      }

      return !currentValue;
    });
  }

  function handleToggleMessageSelection(messageId: string): void {
    setSelectedMessageIds((currentIds) => {
      if (currentIds.includes(messageId)) {
        return currentIds.filter((currentId) => currentId !== messageId);
      }

      return [...currentIds, messageId];
    });
  }

  function handleRequestBulkDelete(): void {
    if (selectedMessageIds.length === 0) {
      return;
    }

    setDeleteModalState({
      mode: "bulk",
      messageIds: selectedMessageIds,
    });
  }

  function handleRequestSingleDelete(): void {
    if (!selectedMessage) {
      return;
    }

    setDeleteModalState({
      mode: "single",
      messageId: selectedMessage.id,
      subject: selectedMessage.subject,
    });
  }

  function handleShowAll(): void {
    setCategoryFilter(null);
  }

  function handleShowUnread(): void {
    setCategoryFilter(UNREAD_FILTER);
  }

  function handleToggleCategory(category: string): void {
    setCategoryFilter((currentFilter) => {
      if (currentFilter === category) {
        return null;
      }

      return category;
    });
  }

  function handleCloseSelectedMessage(): void {
    setSelectedMessageId(null);
  }

  function handleScoutPlayerClick(playerId: string): void {
    onNavigate?.("__selectPlayer", { messageId: playerId });
  }

  return (
    <div className="max-w-6xl mx-auto flex flex-col h-full">
      {/* Filter bar */}
      <div className="flex gap-2 mb-4 flex-wrap shrink-0">
        <button
          onClick={handleShowAll}
          className={getFilterButtonClassName(!categoryFilter)}
        >
          {t("common.all")} ({allMessages.length})
        </button>
        {unreadCount > 0 && (
          <button
            onClick={handleShowUnread}
            className={getFilterButtonClassName(
              categoryFilter === UNREAD_FILTER,
            )}
          >
            {t("inbox.unread", { count: unreadCount })}
          </button>
        )}
        {categories.map((cat) => {
          const catIcon = getCategoryIcon(cat);
          const count = categoryCounts.get(cat) ?? 0;

          return (
            <button
              key={cat}
              onClick={() => handleToggleCategory(cat)}
              className={getFilterButtonClassName(
                categoryFilter === cat,
                "flex items-center gap-1.5",
              )}
            >
              {catIcon} {t(`inbox.categories.${cat}`)} ({count})
            </button>
          );
        })}

        {/* Inbox management actions */}
        <div className="ml-auto flex flex-wrap items-center justify-end gap-2">
          <div className="flex items-center gap-2">
            <label
              htmlFor="inbox-sort-order"
              className="text-xs font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400"
            >
              {t("inbox.sortLabel", "Sort")}
            </label>
            <Select
              id="inbox-sort-order"
              value={sortOrder}
              onChange={handleSortOrderChange}
              selectSize="sm"
              wrapperClassName="min-w-[170px]"
              aria-label={t("inbox.sortByDate", "Sort messages by date")}
            >
              <option value="newest">
                {t("inbox.sortNewest", "Newest first")}
              </option>
              <option value="oldest">
                {t("inbox.sortOldest", "Oldest first")}
              </option>
            </Select>
          </div>
          <Button
            type="button"
            variant={bulkSelectionEnabled ? "primary" : "outline"}
            size="sm"
            onClick={handleToggleBulkSelectionMode}
            data-testid="inbox-toggle-selection-mode"
          >
            {bulkSelectionEnabled
              ? t("inbox.cancelSelection", "Cancel selection")
              : t("inbox.selectMessages", "Select messages")}
          </Button>
          {bulkSelectionEnabled ? (
            <>
              <Badge variant="neutral" size="sm">
                {t("inbox.selectedCount", "{{count}} selected", {
                  count: selectedMessageIds.length,
                })}
              </Badge>
              <Button
                type="button"
                size="sm"
                onClick={handleRequestBulkDelete}
                disabled={selectedMessageIds.length === 0}
                icon={<Trash2 className="w-4 h-4" />}
                className="bg-red-500 hover:bg-red-600 active:bg-red-700 focus:ring-red-500"
                data-testid="inbox-delete-selected"
              >
                {t("inbox.deleteSelected", "Delete selected")}
              </Button>
            </>
          ) : null}
          {unreadCount > 0 && (
            <button
              onClick={handleMarkAllRead}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600 hover:text-primary-500 hover:border-primary-300 transition-all"
            >
              <CheckCheck className="w-3.5 h-3.5" />
              {t("inbox.markAllRead", "Mark all read")}
            </button>
          )}
          <button
            onClick={handleClearOld}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600 hover:text-red-500 hover:border-red-300 transition-all"
          >
            <Trash2 className="w-3.5 h-3.5" />{" "}
            {t("inbox.clearOld", "Clear old")}
          </button>
        </div>
      </div>

      {/* Two-pane inbox layout */}
      <div className="flex-1 flex gap-0 rounded-xl overflow-hidden border border-gray-200 dark:border-navy-600 bg-white dark:bg-navy-800 min-h-0">
        {/* Message list pane */}
        <div className={getListPaneClassName(selectedMessage !== null)}>
          {/* List header */}
          <div className="bg-linear-to-r from-navy-700 to-navy-800 shrink-0 border-b border-gray-100 p-4 dark:border-navy-600">
            <h3 className="text-sm font-heading font-bold text-white flex items-center gap-2 uppercase tracking-wide">
              <Mail className="w-4 h-4 text-accent-400" />
              {t("inbox.title")}
            </h3>
            <p className="text-xs text-gray-400 mt-0.5 font-heading uppercase tracking-wider">
              {t("inbox.nMessages", { count: filteredMessages.length })}
            </p>
          </div>

          {/* Message list */}
          <div className="flex-1 overflow-y-auto">
            {filteredMessages.length === 0 ? (
              <div className="p-6 text-center">
                <MailOpen className="w-8 h-8 text-gray-300 dark:text-navy-600 mx-auto mb-2" />
                <p className="text-sm text-gray-400 dark:text-gray-500">
                  {categoryFilter
                    ? t("inbox.noMessagesInCategory")
                    : t("inbox.noMessages")}
                </p>
              </div>
            ) : (
              filteredMessages.map((message) => {
                const catIcon = getCategoryIcon(message.category);
                const catColor = getCategoryColor(message.category);
                const isSelected = selectedMessageId === message.id;

                return (
                  <div
                    key={message.id}
                    onClick={() => handleSelectMessage(message.id)}
                    className={getMessageRowClassName(isSelected, message.read)}
                    data-testid={`inbox-row-${message.id}`}
                  >
                    {bulkSelectionEnabled ? (
                      <div
                        className="mt-1 flex shrink-0 items-center"
                        onClick={(event) => event.stopPropagation()}
                      >
                        <input
                          type="checkbox"
                          checked={selectedMessageIds.includes(message.id)}
                          onChange={() =>
                            handleToggleMessageSelection(message.id)
                          }
                          aria-label={t(
                            "inbox.selectMessageForDeletion",
                            "Select {{subject}}",
                            { subject: message.subject },
                          )}
                          data-testid={`inbox-select-message-${message.id}`}
                          className="h-4 w-4 rounded border-gray-300 text-primary-500 focus:ring-primary-500/30"
                        />
                      </div>
                    ) : null}
                    <div
                      className={getMessageIconClassName(
                        catColor,
                        isSelected,
                        message.read,
                      )}
                    >
                      {catIcon}
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-1.5">
                        <h4
                          className={getMessageSubjectClassName(message.read)}
                        >
                          {message.subject}
                        </h4>
                        {!message.read && (
                          <span className="w-2 h-2 rounded-full bg-primary-500 shrink-0" />
                        )}
                      </div>
                      <p className="text-xs text-gray-400 dark:text-gray-500 truncate mt-0.5">
                        {message.sender}
                      </p>
                      <p className="text-xs text-gray-400 dark:text-gray-500 mt-0.5">
                        {formatDateShort(message.date, i18n.language)}
                      </p>
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
              <div className="shrink-0 border-b border-gray-100 p-5 dark:border-navy-600">
                <button
                  onClick={handleCloseSelectedMessage}
                  className="md:hidden flex items-center gap-1.5 text-xs text-gray-500 dark:text-gray-400 hover:text-gray-800 dark:hover:text-gray-200 mb-3"
                >
                  <ArrowLeft className="w-3.5 h-3.5" /> {t("inbox.backToInbox")}
                </button>
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-start gap-3 min-w-0 flex-1">
                    <div
                      className={`w-10 h-10 rounded-lg flex items-center justify-center shrink-0 ${getCategoryColor(selectedMessage.category)} bg-primary-500/10 dark:bg-primary-500/20`}
                    >
                      {getCategoryIcon(selectedMessage.category)}
                    </div>
                    <div className="flex-1 min-w-0">
                      <h3 className="font-heading font-bold text-lg text-gray-900 dark:text-gray-100">
                        {selectedMessage.subject}
                      </h3>
                      <div className="flex items-center gap-3 mt-1">
                        <span className="text-sm font-medium text-gray-600 dark:text-gray-300">
                          {selectedMessage.sender}
                          {selectedMessage.sender_role
                            ? ` — ${selectedMessage.sender_role}`
                            : ""}
                        </span>
                        <span className="text-xs text-gray-400 dark:text-gray-500">
                          {formatDateFull(selectedMessage.date, i18n.language)}
                        </span>
                      </div>
                      <div className="flex items-center gap-2 mt-1.5">
                        <Badge variant="neutral" size="sm">
                          {t(`inbox.categories.${selectedMessage.category}`)}
                        </Badge>
                        {selectedMessage.priority === "Urgent" && (
                          <Badge variant="danger" size="sm">
                            {t("inbox.urgent")}
                          </Badge>
                        )}
                        {selectedMessage.priority === "High" && (
                          <Badge variant="accent" size="sm">
                            {t("inbox.important")}
                          </Badge>
                        )}
                      </div>
                    </div>
                  </div>
                  <Button
                    type="button"
                    size="sm"
                    onClick={handleRequestSingleDelete}
                    icon={<Trash2 className="w-4 h-4" />}
                    className="bg-red-500 hover:bg-red-600 active:bg-red-700 focus:ring-red-500"
                    data-testid="inbox-delete-message"
                  >
                    {t("inbox.deleteMessage", "Delete message")}
                  </Button>
                </div>
              </div>

              {/* Detail body */}
              <div className="flex-1 overflow-y-auto p-6">
                <div className="max-w-2xl">
                  {selectedMessage.body
                    .split("\n")
                    .map((line, index) => renderMessageBodyLine(line, index))}

                  {/* Scout report player card */}
                  {selectedMessage.context?.scout_report && (
                    <ScoutPlayerCard
                      report={selectedMessage.context.scout_report}
                      onPlayerClick={handleScoutPlayerClick}
                    />
                  )}

                  {/* Match result context */}
                  {selectedMessage.context?.match_result && (
                    <div className="mt-6 p-4 bg-gray-50 dark:bg-navy-700 rounded-xl flex items-center justify-center gap-8 border border-gray-100 dark:border-navy-600">
                      <span className="font-heading font-bold text-sm text-gray-700 dark:text-gray-200">
                        {getTeamName(
                          gameState.teams,
                          selectedMessage.context.match_result.home_team_id,
                        )}
                      </span>
                      <span className="font-heading font-bold text-2xl text-gray-800 dark:text-gray-100">
                        {selectedMessage.context.match_result.home_goals} -{" "}
                        {selectedMessage.context.match_result.away_goals}
                      </span>
                      <span className="font-heading font-bold text-sm text-gray-700 dark:text-gray-200">
                        {getTeamName(
                          gameState.teams,
                          selectedMessage.context.match_result.away_team_id,
                        )}
                      </span>
                    </div>
                  )}

                  {/* Effect feedback toast */}
                  {effectFeedback && (
                    <div className="mt-4 p-3 bg-primary-50 dark:bg-primary-500/10 border border-primary-200 dark:border-primary-500/30 rounded-xl flex items-center gap-2 animate-pulse">
                      <CheckCircle2 className="w-4 h-4 text-primary-500 shrink-0" />
                      <span className="text-sm font-medium text-primary-700 dark:text-primary-300">
                        {t("inbox.effectOutcomeLabel", "Outcome")}:{" "}
                        {effectFeedback}
                      </span>
                    </div>
                  )}

                  {/* Action buttons */}
                  {selectedMessage.actions.length > 0 && (
                    <div className="mt-6">
                      {selectedMessage.actions.map((action) => {
                        // ChooseOption: render option cards
                        if (isChooseOptionAction(action.action_type)) {
                          const opts = action.action_type.ChooseOption.options;

                          if (action.resolved) {
                            return (
                              <div
                                key={action.id}
                                className="flex items-center gap-2 text-sm text-gray-400 dark:text-gray-500 mt-2"
                              >
                                <CheckCircle2 className="w-4 h-4 text-primary-500" />
                                <span className="font-heading font-bold uppercase tracking-wider text-xs">
                                  {t("inbox.responded", "Response sent")}
                                </span>
                              </div>
                            );
                          }
                          return (
                            <div key={action.id} className="space-y-2">
                              <p className="text-xs font-heading font-bold uppercase tracking-widest text-gray-400 dark:text-gray-500 flex items-center gap-1.5 mb-3">
                                <MessageCircle className="w-3.5 h-3.5" />
                                {isPlayerEventMessage(selectedMessage.id)
                                  ? t(
                                      "inbox.chooseResponseOutcomeVaries",
                                      "Choose your response — outcome varies",
                                    )
                                  : t(
                                      "inbox.chooseResponse",
                                      "Choose your response",
                                    )}
                              </p>
                              {opts.map((opt) => (
                                <button
                                  key={opt.id}
                                  onClick={() =>
                                    handleAction(
                                      selectedMessage.id,
                                      action.id,
                                      opt.id,
                                    )
                                  }
                                  className="w-full text-left p-4 rounded-xl border border-gray-200 dark:border-navy-600 hover:border-primary-400 dark:hover:border-primary-500 hover:bg-primary-50/50 dark:hover:bg-primary-500/5 transition-all group"
                                >
                                  <p className="text-sm font-heading font-bold text-gray-800 dark:text-gray-200 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors">
                                    {opt.label}
                                  </p>
                                  <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                                    {opt.description}
                                  </p>
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
                            onClick={() =>
                              handleAction(selectedMessage.id, action.id)
                            }
                            className={getActionButtonClassName(action)}
                          >
                            {action.resolved
                              ? `✓ ${action.label}`
                              : action.label}
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
                <p className="text-sm text-gray-400 dark:text-gray-500 font-heading uppercase tracking-wider">
                  {t("inbox.selectMessage")}
                </p>
              </div>
            </div>
          )}
        </div>
      </div>
      <InboxDeleteConfirmModal
        deleteModalState={deleteModalState}
        isDeleting={isDeleting}
        onCancel={handleCloseDeleteModal}
        onConfirm={handleConfirmDelete}
      />
    </div>
  );
}
