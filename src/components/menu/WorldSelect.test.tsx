import { render, screen } from "@testing-library/react";
import type { ComponentPropsWithoutRef } from "react";
import { describe, expect, it, vi } from "vitest";

import WorldSelect from "./WorldSelect";

vi.mock("react-i18next", () => ({
  useTranslation: () => ({
    t: (key: string, options?: { year?: number }) => {
      if (key === "worldSelect.summary.midSeason.generated") {
        return `worldSelect.summary.midSeason.generated:${options?.year ?? "missing"}`;
      }

      return key;
    },
  }),
}));

vi.mock("../ui", () => ({
  Button: ({ children, iconRight: _iconRight, ...props }: ComponentPropsWithoutRef<"button"> & { iconRight?: unknown }) => (
    <button {...props}>{children}</button>
  ),
}));

vi.mock("../../utils/backendI18n", () => ({
  resolveBackendText: (value: string) => value,
}));

describe("WorldSelect", () => {
  it("shows the selected world history mode and mid-season inheritance summary", () => {
    render(
      <WorldSelect
        worldDatabases={[
          {
            id: "random",
            name: "Random World",
            description: "Fresh roster baseline",
            team_count: 16,
            player_count: 352,
            source: "builtin",
            path: "",
            history_mode: "generated",
          },
        ]}
        selectedWorldId="random"
        isLoadingWorlds={false}
        isStarting={false}
        startYear={2032}
        startPhase="midSeason"
        onSelectWorld={vi.fn()}
        onImportFile={vi.fn()}
        onStart={vi.fn()}
        onBack={vi.fn()}
        onClose={vi.fn()}
      />,
    );

    expect(
      screen.getAllByText("worldSelect.historyMode.generated"),
    ).toHaveLength(2);
    expect(
      screen.getByText("worldSelect.summary.midSeason.generated:2032"),
    ).toBeInTheDocument();
    expect(screen.getByText("worldSelect.summary.startYear")).toBeInTheDocument();
  });
});