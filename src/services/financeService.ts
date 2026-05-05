import { invoke } from "@tauri-apps/api/core";

export type FinanceHealthLevelData =
    | "stable"
    | "watch"
    | "warning"
    | "critical";

export interface TeamFinanceSnapshotData {
    annual_wage_bill: number;
    weekly_wage_spend: number;
    weekly_wage_budget: number;
    weekly_recurring_income: number;
    weekly_sponsor_income: number;
    projected_weekly_net: number;
    cash_runway_weeks: number | null;
    wage_budget_usage_percent: number;
    currently_in_debt: boolean;
    currently_over_budget: boolean;
    wage_budget_status: FinanceHealthLevelData;
    runway_status: FinanceHealthLevelData;
    overall_status: FinanceHealthLevelData;
}

export interface FinanceSnapshotResponseData {
    snapshot: TeamFinanceSnapshotData;
}

export async function getFinanceSnapshot(
    teamId?: string,
): Promise<FinanceSnapshotResponseData> {
    return invoke<FinanceSnapshotResponseData>("get_finance_snapshot", {
        teamId: teamId ?? null,
    });
}