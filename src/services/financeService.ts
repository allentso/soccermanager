import { invoke } from "@tauri-apps/api/core";

export type FinanceHealthLevelData =
    | "stable"
    | "watch"
    | "warning"
    | "critical";

interface BackendTeamFinanceSnapshotData {
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
    marketing_campaign_cooldown_days_remaining: number;
}

interface BackendFinanceSnapshotResponseData {
    snapshot: BackendTeamFinanceSnapshotData;
}

export interface TeamFinanceSnapshotData {
    annualWageBill: number;
    weeklyWageSpend: number;
    weeklyWageBudget: number;
    weeklyRecurringIncome: number;
    weeklySponsorIncome: number;
    projectedWeeklyNet: number;
    cashRunwayWeeks: number | null;
    wageBudgetUsagePercent: number;
    currentlyInDebt: boolean;
    currentlyOverBudget: boolean;
    wageBudgetStatus: FinanceHealthLevelData;
    runwayStatus: FinanceHealthLevelData;
    overallStatus: FinanceHealthLevelData;
    marketingCampaignCooldownDaysRemaining: number;
}

function mapSnapshot(
    snapshot: BackendTeamFinanceSnapshotData,
): TeamFinanceSnapshotData {
    return {
        annualWageBill: snapshot.annual_wage_bill,
        weeklyWageSpend: snapshot.weekly_wage_spend,
        weeklyWageBudget: snapshot.weekly_wage_budget,
        weeklyRecurringIncome: snapshot.weekly_recurring_income,
        weeklySponsorIncome: snapshot.weekly_sponsor_income,
        projectedWeeklyNet: snapshot.projected_weekly_net,
        cashRunwayWeeks: snapshot.cash_runway_weeks,
        wageBudgetUsagePercent: snapshot.wage_budget_usage_percent,
        currentlyInDebt: snapshot.currently_in_debt,
        currentlyOverBudget: snapshot.currently_over_budget,
        wageBudgetStatus: snapshot.wage_budget_status,
        runwayStatus: snapshot.runway_status,
        overallStatus: snapshot.overall_status,
        marketingCampaignCooldownDaysRemaining:
            snapshot.marketing_campaign_cooldown_days_remaining,
    };
}

export async function getFinanceSnapshot(
    teamId?: string,
): Promise<TeamFinanceSnapshotData> {
    const response = await invoke<BackendFinanceSnapshotResponseData>(
        "get_finance_snapshot",
        {
            teamId: teamId ?? null,
        },
    );

    return mapSnapshot(response.snapshot);
}