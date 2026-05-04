import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import PlayerProfileScoutAction from "./PlayerProfileScoutAction";

vi.mock("react-i18next", () => ({
    useTranslation: () => ({
        t: (key: string) => {
            if (key === "scouting.noScoutsHint") return "Hire a scout first";
            if (key === "scouting.scoutingInProgress") return "Scouting in progress";
            if (key === "scouting.scoutBtn") return "Scout";
            return key;
        },
    }),
}));

describe("PlayerProfileScoutAction", () => {
    it("renders translated scout actions", () => {
        const onScout = vi.fn();

        render(
            <PlayerProfileScoutAction
                availability={{ scouts: [{ id: "scout-1" }], alreadyScouting: false, canScout: true }}
                scoutStatus="idle"
                scoutError={null}
                onScout={onScout}
            />,
        );

        fireEvent.click(screen.getByRole("button", { name: /Scout/i }));

        expect(onScout).toHaveBeenCalledTimes(1);
        expect(screen.getByRole("button", { name: /Scout/i })).toBeInTheDocument();
    });

    it("renders translated hints and progress states", () => {
        const { rerender } = render(
            <PlayerProfileScoutAction
                availability={{ scouts: [], alreadyScouting: false, canScout: false }}
                scoutStatus="idle"
                scoutError={null}
                onScout={vi.fn()}
            />,
        );

        expect(screen.getByText("Hire a scout first")).toBeInTheDocument();

        rerender(
            <PlayerProfileScoutAction
                availability={{ scouts: [{ id: "scout-1" }], alreadyScouting: true, canScout: false }}
                scoutStatus="sent"
                scoutError={null}
                onScout={vi.fn()}
            />,
        );

        expect(screen.getByText("Scouting in progress")).toBeInTheDocument();
    });
});