import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { invoke } from "@tauri-apps/api/core";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

import type {
  GameStateData,
  MessageAction,
  MessageData,
} from "../store/gameStore";
import InboxTab from "./InboxTab";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
}));

vi.mock("react-i18next", async (importOriginal) => {
  const actual = await importOriginal<typeof import("react-i18next")>();

  return {
    ...actual,
    useTranslation: () => ({
      t: (key: string, value?: unknown) => {
        if (typeof value === "string") {
          return value;
        }

        return key;
      },
      i18n: { language: "en" },
    }),
  };
});

const mockedInvoke = vi.mocked(invoke);

beforeAll(function defineMatchMedia(): void {
  Object.defineProperty(window, "matchMedia", {
    writable: true,
    value: vi.fn().mockImplementation((query: string) => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    })),
  });
});

beforeEach(function resetMocks(): void {
  mockedInvoke.mockReset();
});

function createMessage(overrides: Partial<MessageData> = {}): MessageData {
  return {
    id: "m1",
    subject: "Test Message",
    body: "Test Body",
    sender: "Sender",
    sender_role: "Role",
    date: "2025-01-01",
    read: false,
    category: "System",
    priority: "Normal",
    actions: [],
    context: {
      team_id: null,
      player_id: null,
      fixture_id: null,
      match_result: null,
    },
    ...overrides,
  };
}

function createGameState(messages: MessageData[]): GameStateData {
  return {
    clock: {
      current_date: "2025-01-01",
      start_date: "2025-01-01",
    },
    manager: {
      id: "manager-1",
      first_name: "John",
      last_name: "Doe",
      date_of_birth: "1980-01-01",
      nationality: "BR",
      reputation: 50,
      satisfaction: 50,
      fan_approval: 50,
      team_id: "t1",
      career_stats: {
        matches_managed: 0,
        wins: 0,
        draws: 0,
        losses: 0,
        trophies: 0,
        best_finish: null,
      },
      career_history: [],
    },
    teams: [],
    players: [],
    staff: [],
    messages,
    news: [],
    league: null,
    scouting_assignments: [],
    board_objectives: [],
  };
}

function renderInboxTab(options: {
  gameState: GameStateData;
  initialMessageId?: string | null;
  onGameUpdate?: (state: GameStateData) => void;
  onNavigate?: (tab: string, context?: { messageId?: string }) => void;
}): void {
  render(
    <InboxTab
      gameState={options.gameState}
      initialMessageId={options.initialMessageId}
      onGameUpdate={options.onGameUpdate ?? vi.fn()}
      onNavigate={options.onNavigate}
    />,
  );
}

describe("InboxTab", function (): void {
  it("renders each message exactly once in the list", function (): void {
    const gameState = createGameState([
      createMessage({ id: "m1", subject: "Test Message 1" }),
      createMessage({ id: "m2", subject: "Test Message 2" }),
      createMessage({ id: "m3", subject: "Test Message 3" }),
    ]);

    renderInboxTab({ gameState });

    expect(screen.getAllByText(/Test Message \d/)).toHaveLength(3);
  });

  it("marks an unread message as read when selected", async function (): Promise<void> {
    const updatedGameState = createGameState([
      createMessage({ id: "m1", read: true }),
    ]);
    const onGameUpdate = vi.fn();

    mockedInvoke.mockResolvedValue(updatedGameState);

    renderInboxTab({
      gameState: createGameState([createMessage({ id: "m1" })]),
      onGameUpdate,
    });

    fireEvent.click(screen.getByText("Test Message"));

    await waitFor(function (): void {
      expect(mockedInvoke).toHaveBeenCalledWith("mark_message_read", {
        messageId: "m1",
      });
    });

    expect(onGameUpdate).toHaveBeenCalledWith(updatedGameState);
  });

  it("navigates to a team route without resolving the message action", async function (): Promise<void> {
    const onNavigate = vi.fn();
    const action: MessageAction = {
      id: "action-1",
      label: "Open Team",
      action_type: { NavigateTo: { route: "/team/team-99" } },
      resolved: false,
    };

    renderInboxTab({
      gameState: createGameState([
        createMessage({ id: "m1", read: true, actions: [action] }),
      ]),
      initialMessageId: "m1",
      onNavigate,
    });

    fireEvent.click(screen.getByRole("button", { name: "Open Team" }));

    await waitFor(function (): void {
      expect(onNavigate).toHaveBeenCalledWith("__selectTeam", {
        messageId: "team-99",
      });
    });

    expect(mockedInvoke).not.toHaveBeenCalled();
  });

  it("navigates to a dashboard tab and still resolves the action", async function (): Promise<void> {
    const onGameUpdate = vi.fn();
    const onNavigate = vi.fn();
    const resolvedGameState = createGameState([
      createMessage({ id: "m1", read: true }),
    ]);
    const action: MessageAction = {
      id: "action-1",
      label: "Open Squad",
      action_type: { NavigateTo: { route: "/dashboard?tab=Squad" } },
      resolved: false,
    };

    mockedInvoke.mockResolvedValue({ game: resolvedGameState, effect: null });

    renderInboxTab({
      gameState: createGameState([
        createMessage({ id: "m1", read: true, actions: [action] }),
      ]),
      initialMessageId: "m1",
      onGameUpdate,
      onNavigate,
    });

    fireEvent.click(screen.getByRole("button", { name: "Open Squad" }));

    await waitFor(function (): void {
      expect(onNavigate).toHaveBeenCalledWith("Squad", undefined);
      expect(mockedInvoke).toHaveBeenCalledWith("resolve_message_action", {
        messageId: "m1",
        actionId: "action-1",
        optionId: null,
      });
    });

    expect(onGameUpdate).toHaveBeenCalledWith(resolvedGameState);
  });
});
