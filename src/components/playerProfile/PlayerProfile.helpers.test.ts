import { describe, expect, it } from "vitest";

import type { TeamData } from "../../store/gameStore";
import {
    formatPlayerMarketValue,
    formatPlayerWage,
    getAttributeColorClass,
    getPlayerAge,
    getPlayerTeamName,
    resolvePlayerInjuryName,
} from "./PlayerProfile.helpers";

function createTeam(overrides: Partial<TeamData> = {}): TeamData {
    return {
        id: "team-1",
        name: "Alpha FC",
        short_name: "ALP",
        country: "GB",
        city: "London",
        stadium_name: "Alpha Ground",
        stadium_capacity: 30000,
        finance: 500000,
        manager_id: "manager-1",
        reputation: 50,
        wage_budget: 50000,
        transfer_budget: 250000,
        season_income: 0,
        season_expenses: 0,
        formation: "4-4-2",
        play_style: "Balanced",
        training_focus: "General",
        training_intensity: "Balanced",
        training_schedule: "Balanced",
        founded_year: 1900,
        colors: { primary: "#000000", secondary: "#ffffff" },
        starting_xi_ids: [],
        form: [],
        history: [],
        ...overrides,
    };
}

describe("PlayerProfile.helpers", function (): void {
    it("resolves the player team name with free-agent and unknown fallbacks", function (): void {
        const teams = [createTeam()];

        expect(
            getPlayerTeamName(teams, "team-1", {
                freeAgent: "Free Agent",
                unknown: "Unknown",
            }),
        ).toBe("Alpha FC");
        expect(
            getPlayerTeamName(teams, null, {
                freeAgent: "Free Agent",
                unknown: "Unknown",
            }),
        ).toBe("Free Agent");
        expect(
            getPlayerTeamName(teams, "team-2", {
                freeAgent: "Free Agent",
                unknown: "Unknown",
            }),
        ).toBe("Unknown");
    });

    it("calculates age relative to an as-of date instead of just the birth year", function (): void {
        expect(getPlayerAge("2000-07-02", "2026-07-01")).toBe(25);
        expect(getPlayerAge("2000-07-01", "2026-07-01")).toBe(26);
    });

    it("formats market values across value ranges", function (): void {
        expect(formatPlayerMarketValue(999)).toBe("€999");
        expect(formatPlayerMarketValue(125000)).toBe("€125K");
        expect(formatPlayerMarketValue(2500000)).toBe("€2.5M");
    });

    it("formats annual wages as weekly display values", function (): void {
        expect(formatPlayerWage(52000, "/wk")).toMatch(/^€1[.,]000\/wk$/);
    });

    it("maps attribute values to the expected color classes", function (): void {
        expect(getAttributeColorClass(85)).toContain("text-primary-500");
        expect(getAttributeColorClass(65)).toContain("text-accent-600");
        expect(getAttributeColorClass(45)).toContain("text-gray-600");
        expect(getAttributeColorClass(20)).toContain("text-red-500");
    });

    it("resolves injury names for explicit keys and plain injuries", function (): void {
        const translate = (key: string, options?: { defaultValue?: string }): string => {
            return options?.defaultValue ? `${key}:${options.defaultValue}` : key;
        };

        expect(resolvePlayerInjuryName("injuries.hamstring", translate)).toBe(
            "injuries.hamstring:injuries.hamstring",
        );
        expect(resolvePlayerInjuryName("Hamstring", translate)).toBe(
            "common.injuries.Hamstring:Hamstring",
        );
    });
});
