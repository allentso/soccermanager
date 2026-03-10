import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { ComponentPropsWithoutRef } from "react";

import { countryName } from "../lib/countries";
import MainMenu from "./MainMenu";

const navigateMock = vi.fn();
const setGameActiveMock = vi.fn();
const setGameStateMock = vi.fn();
const translationState = {
  language: "en",
};

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
}));

vi.mock("react-router-dom", () => ({
  useNavigate: () => navigateMock,
}));

vi.mock("react-i18next", () => ({
  useTranslation: () => ({
    t: (key: string, fallback?: string | Record<string, unknown>) =>
      typeof fallback === "string" ? fallback : key,
    i18n: { language: translationState.language },
  }),
}));

vi.mock("../store/gameStore", () => ({
  useGameStore: (
    selector: (state: {
      setGameActive: typeof setGameActiveMock;
      setGameState: typeof setGameStateMock;
    }) => unknown,
  ) =>
    selector({
      setGameActive: setGameActiveMock,
      setGameState: setGameStateMock,
    }),
}));

vi.mock("../components/ui", () => ({
  Button: ({
    children,
    iconRight: _iconRight,
    iconLeft: _iconLeft,
    ...props
  }: ComponentPropsWithoutRef<"button"> & {
    iconRight?: unknown;
    iconLeft?: unknown;
  }) => <button {...props}>{children}</button>,
  ThemeToggle: () => <div data-testid="theme-toggle" />,
  DatePicker: ({
    value,
    onChange,
  }: {
    value: string;
    onChange: (date: string) => void;
    error?: boolean;
  }) => (
    <input
      aria-label="manager-date-of-birth"
      value={value}
      onChange={(event) => onChange(event.target.value)}
    />
  ),
}));

vi.mock("../components/menu/SavesList", () => ({
  default: () => <div data-testid="saves-list" />,
}));

vi.mock("../components/menu/WorldSelect", () => ({
  default: ({ onStart }: { onStart: () => void }) => (
    <div data-testid="world-select">
      <button type="button" onClick={onStart}>
        start-world
      </button>
    </div>
  ),
}));

const mockedInvoke = vi.mocked(invoke);

function openCreateManagerForm(): void {
  fireEvent.click(screen.getByText("menu.newGame"));
}

function fillManagerDetails(): void {
  fireEvent.change(
    screen.getByPlaceholderText("createManager.placeholderFirst"),
    {
      target: { value: "Ada" },
    },
  );
  fireEvent.change(
    screen.getByPlaceholderText("createManager.placeholderLast"),
    {
      target: { value: "Lovelace" },
    },
  );
  fireEvent.change(screen.getByLabelText("manager-date-of-birth"), {
    target: { value: "1980-01-01" },
  });
}

function selectNationality(language: string, nationalityCode: string): void {
  const countryLabel = countryName(nationalityCode, language);

  fireEvent.click(
    screen.getByRole("button", { name: /select country\/region/i }),
  );
  fireEvent.click(screen.getByText(countryLabel));
}

function searchAndSelectNationality(
  language: string,
  nationalityCode: string,
  searchText: string,
): void {
  const countryLabel = countryName(nationalityCode, language);

  fireEvent.click(
    screen.getByRole("button", { name: /select country\/region/i }),
  );
  fireEvent.change(
    screen.getByPlaceholderText("createManager.searchNationalities"),
    {
      target: { value: searchText },
    },
  );
  fireEvent.click(screen.getByText(countryLabel));
}

describe("MainMenu", () => {
  beforeEach(() => {
    navigateMock.mockReset();
    setGameActiveMock.mockReset();
    setGameStateMock.mockReset();
    translationState.language = "en";
    mockedInvoke.mockReset();
    mockedInvoke.mockImplementation(async (command) => {
      if (command === "list_world_databases") {
        return [];
      }

      if (command === "start_new_game") {
        return { id: "game-1" };
      }

      return null;
    });
  });

  it.each(["es", "de", "fr", "it", "pt", "pt-BR"])(
    "stores the nationality as an ISO code and continues the flow in %s",
    async (language) => {
      translationState.language = language;

      render(<MainMenu />);

      openCreateManagerForm();
      fillManagerDetails();
      selectNationality(language, "ES");

      const localizedCountryName = countryName("ES", language);
      expect(
        screen.getByRole("button", {
          name: new RegExp(localizedCountryName, "i"),
        }),
      ).toBeInTheDocument();

      fireEvent.click(screen.getByText("createManager.chooseWorld"));

      await waitFor(() => {
        expect(mockedInvoke).toHaveBeenCalledWith("list_world_databases");
      });
      expect(screen.getByTestId("world-select")).toBeInTheDocument();

      fireEvent.click(screen.getByText("start-world"));

      await waitFor(() => {
        expect(mockedInvoke).toHaveBeenCalledWith(
          "start_new_game",
          expect.objectContaining({
            firstName: "Ada",
            lastName: "Lovelace",
            dob: "1980-01-01",
            nationality: "ES",
          }),
        );
      });
      expect(setGameStateMock).toHaveBeenCalledWith({ id: "game-1" });
      expect(navigateMock).toHaveBeenCalledWith("/select-team");
    },
  );

  it("allows searching localized countries without accents before selecting them", async () => {
    translationState.language = "pt";

    render(<MainMenu />);

    openCreateManagerForm();
    fillManagerDetails();
    searchAndSelectNationality("pt", "AT", "austria");

    expect(
      screen.getByRole("button", {
        name: /áustria/i,
      }),
    ).toBeInTheDocument();

    fireEvent.click(screen.getByText("createManager.chooseWorld"));

    await waitFor(() => {
      expect(mockedInvoke).toHaveBeenCalledWith("list_world_databases");
    });

    fireEvent.click(screen.getByText("start-world"));

    await waitFor(() => {
      expect(mockedInvoke).toHaveBeenCalledWith(
        "start_new_game",
        expect.objectContaining({
          nationality: "AT",
        }),
      );
    });
  });
});
