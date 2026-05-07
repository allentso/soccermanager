import { GraduationCap, ScanSearch, Clock } from "lucide-react";
import { useTranslation } from "react-i18next";

import type { StaffData, YouthScoutingAssignment } from "../../store/gameStore";
import { Badge, Button, Card, CardBody, CardHeader } from "../ui";

interface ScoutingYouthRecruitmentCardProps {
    youthAssignments: YouthScoutingAssignment[];
    scouts: StaffData[];
    availableScoutCount: number;
    isStarting: boolean;
    onStartSearch: () => void;
}

export default function ScoutingYouthRecruitmentCard({
    youthAssignments,
    scouts,
    availableScoutCount,
    isStarting,
    onStartSearch,
}: ScoutingYouthRecruitmentCardProps) {
    const { t } = useTranslation();

    return (
        <Card accent="primary">
            <CardHeader
                action={
                    <Button
                        size="sm"
                        icon={<ScanSearch />}
                        disabled={availableScoutCount === 0 || isStarting}
                        onClick={onStartSearch}
                    >
                        {t("scouting.startYouthSearch")}
                    </Button>
                }
            >
                {t("scouting.youthRecruitment")}
            </CardHeader>
            <CardBody className="flex flex-col gap-4">
                <p className="text-sm text-gray-500 dark:text-gray-400">
                    {t("scouting.youthRecruitmentHint")}
                </p>

                <div className="flex flex-wrap items-center gap-2">
                    <Badge variant="primary" size="sm">
                        {t("scouting.activeYouthSearches", { count: youthAssignments.length })}
                    </Badge>
                    {availableScoutCount === 0 ? (
                        <span className="text-xs text-gray-500 dark:text-gray-400">
                            {t("scouting.noScoutsFree")}
                        </span>
                    ) : null}
                </div>

                {youthAssignments.length === 0 ? (
                    <div className="flex items-center gap-3 rounded-xl border border-dashed border-gray-200 dark:border-navy-600 bg-gray-50 dark:bg-navy-800/40 px-4 py-4">
                        <GraduationCap className="w-5 h-5 text-primary-500 shrink-0" />
                        <p className="text-sm text-gray-500 dark:text-gray-400">
                            {t("scouting.noYouthSearches")}
                        </p>
                    </div>
                ) : (
                    <div className="flex flex-col gap-3">
                        {youthAssignments.map((assignment) => {
                            const scout = scouts.find((staffMember) => staffMember.id === assignment.scout_id);
                            if (!scout) {
                                return null;
                            }

                            return (
                                <div
                                    key={assignment.id}
                                    className="flex items-center justify-between gap-4 rounded-xl border border-gray-200 dark:border-navy-600 bg-gray-50 dark:bg-navy-800/60 px-4 py-3"
                                >
                                    <div className="min-w-0">
                                        <p className="font-heading font-bold text-sm text-gray-800 dark:text-gray-100">
                                            {t("scouting.youthProspectSearch")}
                                        </p>
                                        <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                                            {t("scouting.scoutLabel", {
                                                name: `${scout.first_name} ${scout.last_name}`,
                                            })}
                                        </p>
                                    </div>

                                    <div className="flex items-center gap-1.5 text-accent-500 shrink-0">
                                        <Clock className="w-3.5 h-3.5" />
                                        <span className="text-xs font-heading font-bold">
                                            {t("scouting.daysLeft", { days: assignment.days_remaining })}
                                        </span>
                                    </div>
                                </div>
                            );
                        })}
                    </div>
                )}
            </CardBody>
        </Card>
    );
}