import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { GameStateData, StaffData } from "../store/gameStore";
import { Card, CardBody, Badge, ProgressBar } from "./ui";
import { UserCog, Search, UserPlus, UserMinus, Briefcase, Eye, Stethoscope, GraduationCap, Star } from "lucide-react";
import { getTeamName, calcAge, formatVal } from "../lib/helpers";

interface StaffTabProps {
  gameState: GameStateData;
  onGameUpdate?: (state: GameStateData) => void;
}

const ROLE_META: Record<string, { label: string; icon: React.ReactNode; color: string }> = {
  AssistantManager: { label: "Assistant Manager", icon: <Briefcase className="w-4 h-4" />, color: "text-blue-500" },
  Coach:            { label: "Coach",             icon: <GraduationCap className="w-4 h-4" />, color: "text-primary-500" },
  Scout:            { label: "Scout",             icon: <Eye className="w-4 h-4" />, color: "text-accent-500" },
  Physio:           { label: "Physio",            icon: <Stethoscope className="w-4 h-4" />, color: "text-red-400" },
};

function bestAttr(s: StaffData): { label: string; value: number } {
  const attrs = [
    { label: "Coaching", value: s.attributes.coaching },
    { label: "Judging Ability", value: s.attributes.judging_ability },
    { label: "Judging Potential", value: s.attributes.judging_potential },
    { label: "Physiotherapy", value: s.attributes.physiotherapy },
  ];
  return attrs.reduce((a, b) => (b.value > a.value ? b : a));
}

function ovrRating(s: StaffData): number {
  return Math.round(
    (s.attributes.coaching + s.attributes.judging_ability + s.attributes.judging_potential + s.attributes.physiotherapy) / 4
  );
}

const SPEC_LABELS: Record<string, string> = {
  Fitness: "Fitness",
  Technique: "Technique",
  Tactics: "Tactics",
  Defending: "Defending",
  Attacking: "Attacking",
  GoalKeeping: "Goalkeeping",
  Youth: "Youth Dev",
};

export default function StaffTab({ gameState, onGameUpdate }: StaffTabProps) {
  const userTeamId = gameState.manager.team_id;
  const [view, setView] = useState<"mystaff" | "available">("mystaff");
  const [search, setSearch] = useState("");
  const [roleFilter, setRoleFilter] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const myStaff = gameState.staff.filter(s => s.team_id === userTeamId);
  const availableStaff = gameState.staff.filter(s => !s.team_id);

  const handleHire = async (staffId: string) => {
    setActionLoading(staffId);
    try {
      const updated = await invoke<GameStateData>("hire_staff", { staffId });
      onGameUpdate?.(updated);
    } catch (err) {
      console.error("Failed to hire staff:", err);
    } finally {
      setActionLoading(null);
    }
  };

  const handleRelease = async (staffId: string) => {
    setActionLoading(staffId);
    try {
      const updated = await invoke<GameStateData>("release_staff", { staffId });
      onGameUpdate?.(updated);
    } catch (err) {
      console.error("Failed to release staff:", err);
    } finally {
      setActionLoading(null);
    }
  };

  const displayStaff = view === "mystaff" ? myStaff : availableStaff;

  const filtered = displayStaff.filter(s => {
    if (roleFilter && s.role !== roleFilter) return false;
    if (search.length >= 2) {
      const q = search.toLowerCase();
      const fullName = `${s.first_name} ${s.last_name}`.toLowerCase();
      if (!fullName.includes(q)) return false;
    }
    return true;
  });

  const roles = ["AssistantManager", "Coach", "Scout", "Physio"];

  return (
    <div className="max-w-5xl mx-auto">
      {/* View toggle */}
      <div className="flex flex-wrap gap-3 mb-4 items-center">
        <div className="flex gap-2">
          <button
            onClick={() => setView("mystaff")}
            className={`px-4 py-2 rounded-lg font-heading font-bold text-sm uppercase tracking-wider transition-all flex items-center gap-1.5 ${
              view === "mystaff"
                ? "bg-primary-500 text-white shadow-md shadow-primary-500/20"
                : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600"
            }`}
          >
            <UserCog className="w-4 h-4" /> My Staff ({myStaff.length})
          </button>
          <button
            onClick={() => setView("available")}
            className={`px-4 py-2 rounded-lg font-heading font-bold text-sm uppercase tracking-wider transition-all flex items-center gap-1.5 ${
              view === "available"
                ? "bg-primary-500 text-white shadow-md shadow-primary-500/20"
                : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600"
            }`}
          >
            <UserPlus className="w-4 h-4" /> Available ({availableStaff.length})
          </button>
        </div>

        <div className="relative flex-1 min-w-[180px] max-w-xs">
          <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 dark:text-gray-500" />
          <input
            type="text"
            placeholder="Search staff..."
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2 rounded-lg bg-white dark:bg-navy-800 border border-gray-200 dark:border-navy-600 text-sm text-gray-800 dark:text-gray-200 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-500/50"
          />
        </div>

        <div className="flex gap-1.5">
          <button
            onClick={() => setRoleFilter(null)}
            className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
              !roleFilter ? "bg-primary-500 text-white shadow-sm" : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600"
            }`}
          >
            All
          </button>
          {roles.map(r => (
            <button
              key={r}
              onClick={() => setRoleFilter(roleFilter === r ? null : r)}
              className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all flex items-center gap-1 ${
                roleFilter === r ? "bg-primary-500 text-white shadow-sm" : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600"
              }`}
            >
              {ROLE_META[r]?.icon} {ROLE_META[r]?.label}
            </button>
          ))}
        </div>
      </div>

      {/* Staff grid */}
      {filtered.length === 0 ? (
        <div className="py-12 text-center">
          <UserCog className="w-12 h-12 text-gray-300 dark:text-navy-600 mx-auto mb-3" />
          <p className="text-sm text-gray-400 dark:text-gray-500">
            {view === "mystaff" ? "No staff members match your filters." : "No available staff found."}
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {filtered.map(staff => {
            const meta = ROLE_META[staff.role] || ROLE_META.Coach;
            const age = calcAge(staff.date_of_birth);
            const ovr = ovrRating(staff);
            const best = bestAttr(staff);

            return (
              <Card key={staff.id}>
                <CardBody>
                  <div className="flex items-start gap-4">
                    {/* Avatar */}
                    <div className={`w-12 h-12 rounded-xl flex items-center justify-center ${meta.color} bg-gray-100 dark:bg-navy-700`}>
                      {meta.icon}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <h3 className="font-heading font-bold text-sm text-gray-800 dark:text-gray-100 uppercase tracking-wide truncate">
                          {staff.first_name} {staff.last_name}
                        </h3>
                        <Badge variant={ovr >= 65 ? "success" : ovr >= 45 ? "primary" : "neutral"} size="sm">{ovr} OVR</Badge>
                      </div>
                      <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                        {meta.label} — Age {age}
                        {staff.team_id && view === "available" && <span className="ml-1.5">at {getTeamName(gameState.teams, staff.team_id)}</span>}
                      </p>

                      {/* Specialization + Wage */}
                      <div className="flex flex-wrap gap-1.5 mt-1.5">
                        {staff.specialization && (
                          <span className="inline-flex items-center gap-1 text-[10px] bg-accent-50 dark:bg-accent-500/10 text-accent-600 dark:text-accent-400 px-1.5 py-0.5 rounded font-heading uppercase tracking-wider">
                            <Star className="w-3 h-3" /> {SPEC_LABELS[staff.specialization] || staff.specialization}
                          </span>
                        )}
                        {staff.wage > 0 && (
                          <span className="text-[10px] bg-gray-100 dark:bg-navy-700 text-gray-500 dark:text-gray-400 px-1.5 py-0.5 rounded font-heading uppercase tracking-wider">
                            {formatVal(staff.wage)}/wk
                          </span>
                        )}
                      </div>

                      {/* Attributes */}
                      <div className="grid grid-cols-2 gap-x-4 gap-y-1.5 mt-3">
                        <AttrBar label="Coaching" value={staff.attributes.coaching} />
                        <AttrBar label="Judging Ability" value={staff.attributes.judging_ability} />
                        <AttrBar label="Judging Potential" value={staff.attributes.judging_potential} />
                        <AttrBar label="Physiotherapy" value={staff.attributes.physiotherapy} />
                      </div>

                      <p className="text-xs text-gray-400 dark:text-gray-500 mt-2">
                        Best: <span className="font-medium text-gray-600 dark:text-gray-300">{best.label} ({best.value})</span>
                      </p>
                    </div>

                    {/* Action button */}
                    {view === "mystaff" && (
                      <button
                        disabled={actionLoading === staff.id}
                        onClick={() => handleRelease(staff.id)}
                        className={`p-2 rounded-lg bg-red-50 dark:bg-red-500/10 text-red-500 hover:bg-red-100 dark:hover:bg-red-500/20 transition-colors ${actionLoading === staff.id ? "opacity-50 pointer-events-none" : ""}`}
                        title="Release staff member"
                      >
                        <UserMinus className="w-4 h-4" />
                      </button>
                    )}
                    {view === "available" && (
                      <button
                        disabled={actionLoading === staff.id}
                        onClick={() => handleHire(staff.id)}
                        className={`p-2 rounded-lg bg-primary-50 dark:bg-primary-500/10 text-primary-500 hover:bg-primary-100 dark:hover:bg-primary-500/20 transition-colors ${actionLoading === staff.id ? "opacity-50 pointer-events-none" : ""}`}
                        title="Hire staff member"
                      >
                        <UserPlus className="w-4 h-4" />
                      </button>
                    )}
                  </div>
                </CardBody>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}

function AttrBar({ label, value }: { label: string; value: number }) {
  return (
    <div>
      <div className="flex justify-between text-xs mb-0.5">
        <span className="text-gray-500 dark:text-gray-400">{label}</span>
        <span className={`font-heading font-bold tabular-nums ${value >= 70 ? "text-primary-500" : value >= 50 ? "text-accent-500" : "text-gray-400"}`}>{value}</span>
      </div>
      <ProgressBar value={value} variant={value >= 70 ? "success" : value >= 50 ? "primary" : "accent"} size="sm" />
    </div>
  );
}
