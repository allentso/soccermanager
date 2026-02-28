import { TeamData, GameStateData, PlayerData } from "../store/gameStore";
import { Card, CardHeader, CardBody, Badge, ProgressBar } from "./ui";
import { ArrowLeft, Shield, MapPin, Calendar, DollarSign, Users, Trophy, Crosshair } from "lucide-react";

interface TeamProfileProps {
  team: TeamData;
  gameState: GameStateData;
  isOwnTeam: boolean;
  onClose: () => void;
  onSelectPlayer?: (id: string) => void;
}

function formatMoney(val: number): string {
  if (val >= 1_000_000) return `€${(val / 1_000_000).toFixed(1)}M`;
  if (val >= 1_000) return `€${(val / 1_000).toFixed(0)}K`;
  return `€${val}`;
}

function calcPlayerOvr(p: PlayerData): number {
  const a = p.attributes;
  return Math.round(
    (a.pace + a.stamina + a.strength + a.passing + a.shooting +
      a.tackling + a.dribbling + a.defending + a.positioning +
      a.vision + a.decisions) / 11
  );
}

function calcAge(dob: string): number {
  const birth = new Date(dob);
  return 2026 - birth.getFullYear();
}

function formatVal(v: number): string {
  if (v >= 1_000_000) return `€${(v / 1_000_000).toFixed(1)}M`;
  if (v >= 1_000) return `€${(v / 1_000).toFixed(0)}K`;
  return `€${v}`;
}

const positionBadgeVariant = (pos: string): "accent" | "primary" | "success" | "danger" => {
  switch (pos) {
    case "Goalkeeper": return "accent";
    case "Defender": return "primary";
    case "Midfielder": return "success";
    case "Forward": return "danger";
    default: return "primary";
  }
};

export default function TeamProfile({ team, gameState, isOwnTeam, onClose, onSelectPlayer }: TeamProfileProps) {
  const roster = gameState.players
    .filter(p => p.team_id === team.id)
    .sort((a, b) => {
      const posOrder: Record<string, number> = { Goalkeeper: 1, Defender: 2, Midfielder: 3, Forward: 4 };
      return (posOrder[a.position] || 99) - (posOrder[b.position] || 99);
    });

  const avgOvr = roster.length > 0
    ? Math.round(roster.reduce((sum, p) => sum + calcPlayerOvr(p), 0) / roster.length)
    : 0;

  const totalWages = roster.reduce((sum, p) => sum + p.wage, 0);
  const totalValue = roster.reduce((sum, p) => sum + p.market_value, 0);

  const manager = gameState.manager.team_id === team.id ? gameState.manager : null;

  const allStandings = gameState.league?.standings
    ? [...gameState.league.standings].sort((a, b) =>
        b.points - a.points || (b.goals_for - b.goals_against) - (a.goals_for - a.goals_against) || b.goals_for - a.goals_for
      )
    : [];
  const leaguePos = allStandings.findIndex(s => s.team_id === team.id) + 1;
  const standings = gameState.league?.standings.find(s => s.team_id === team.id);

  return (
    <div className="max-w-6xl mx-auto">
      {/* Back button */}
      <button onClick={onClose} className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-800 dark:hover:text-gray-200 transition-colors mb-4">
        <ArrowLeft className="w-4 h-4" />
        <span className="font-heading font-bold uppercase tracking-wider">Back</span>
      </button>

      {/* Hero header with team colors */}
      <Card className="mb-5 overflow-hidden">
        <div
          className="p-8 relative"
          style={{
            background: `linear-gradient(135deg, ${team.colors.primary}, ${team.colors.secondary}40)`,
          }}
        >
          <div className="flex items-start gap-6">
            <div
              className="w-24 h-24 rounded-2xl flex items-center justify-center font-heading font-bold text-3xl text-white border-2 border-white/30"
              style={{ backgroundColor: team.colors.primary }}
            >
              {team.short_name}
            </div>
            <div className="flex-1">
              <h2 className="text-3xl font-heading font-bold text-white uppercase tracking-wide drop-shadow">{team.name}</h2>
              <div className="flex items-center gap-4 mt-2 text-white/80 text-sm">
                <span className="flex items-center gap-1.5"><MapPin className="w-4 h-4" /> {team.city}, {team.country}</span>
                <span className="flex items-center gap-1.5"><Calendar className="w-4 h-4" /> Est. {team.founded_year}</span>
              </div>
              {manager && (
                <p className="text-white/70 text-sm mt-1 flex items-center gap-1.5">
                  <Users className="w-4 h-4" /> Manager: {manager.first_name} {manager.last_name}
                </p>
              )}
            </div>

            {/* Quick stats in header */}
            <div className="hidden md:grid grid-cols-2 gap-3">
              <div className="bg-black/20 backdrop-blur rounded-xl px-5 py-3 text-center min-w-[100px]">
                <p className="text-xs text-white/60 font-heading uppercase tracking-wider">Avg OVR</p>
                <p className="font-heading font-bold text-2xl text-white mt-0.5">{avgOvr}</p>
              </div>
              <div className="bg-black/20 backdrop-blur rounded-xl px-5 py-3 text-center min-w-[100px]">
                <p className="text-xs text-white/60 font-heading uppercase tracking-wider">Reputation</p>
                <p className="font-heading font-bold text-2xl text-accent-300 mt-0.5">{team.reputation}</p>
              </div>
              <div className="bg-black/20 backdrop-blur rounded-xl px-5 py-3 text-center min-w-[100px]">
                <p className="text-xs text-white/60 font-heading uppercase tracking-wider">League Pos</p>
                <p className="font-heading font-bold text-2xl text-white mt-0.5">{leaguePos > 0 ? `#${leaguePos}` : "—"}</p>
              </div>
              <div className="bg-black/20 backdrop-blur rounded-xl px-5 py-3 text-center min-w-[100px]">
                <p className="text-xs text-white/60 font-heading uppercase tracking-wider">Squad</p>
                <p className="font-heading font-bold text-2xl text-white mt-0.5">{roster.length}</p>
              </div>
            </div>
          </div>
        </div>

        {/* Mobile-only quick stats */}
        <div className="grid grid-cols-4 gap-px bg-gray-200 dark:bg-navy-600 md:hidden">
          <QuickStat label="Avg OVR" value={String(avgOvr)} color="text-primary-500" />
          <QuickStat label="Rep" value={String(team.reputation)} color="text-accent-500" />
          <QuickStat label="Position" value={leaguePos > 0 ? `#${leaguePos}` : "—"} color="text-gray-700 dark:text-gray-200" />
          <QuickStat label="Squad" value={String(roster.length)} color="text-gray-700 dark:text-gray-200" />
        </div>
      </Card>

      {/* Main content grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
        {/* Club info */}
        <Card>
          <CardHeader>Club Information</CardHeader>
          <CardBody>
            <div className="flex flex-col gap-3">
              <InfoRow icon={<Shield className="w-4 h-4" />} label="Stadium" value={team.stadium_name} />
              <InfoRow icon={<Users className="w-4 h-4" />} label="Capacity" value={team.stadium_capacity.toLocaleString()} />
              <InfoRow icon={<Crosshair className="w-4 h-4" />} label="Formation" value={team.formation} />
              <InfoRow icon={<Trophy className="w-4 h-4" />} label="Play Style" value={team.play_style} />
            </div>
          </CardBody>
        </Card>

        {/* Finances — only visible if own team */}
        {isOwnTeam ? (
          <Card accent="accent">
            <CardHeader>Finances</CardHeader>
            <CardBody>
              <div className="flex flex-col gap-3">
                <InfoRow icon={<DollarSign className="w-4 h-4" />} label="Balance" value={formatMoney(team.finance)} />
                <InfoRow icon={<DollarSign className="w-4 h-4" />} label="Wage Budget" value={`${formatMoney(team.wage_budget)}/wk`} />
                <InfoRow icon={<DollarSign className="w-4 h-4" />} label="Transfer Budget" value={formatMoney(team.transfer_budget)} />
                <InfoRow icon={<DollarSign className="w-4 h-4" />} label="Total Wages" value={`${formatMoney(totalWages)}/wk`} />
                <InfoRow icon={<DollarSign className="w-4 h-4" />} label="Squad Value" value={formatMoney(totalValue)} />
                <InfoRow icon={<DollarSign className="w-4 h-4" />} label="Season Income" value={formatMoney(team.season_income)} />
              </div>
            </CardBody>
          </Card>
        ) : (
          <Card>
            <CardHeader>Squad Overview</CardHeader>
            <CardBody>
              <div className="flex flex-col gap-3">
                <InfoRow icon={<Users className="w-4 h-4" />} label="Squad Size" value={String(roster.length)} />
                <InfoRow icon={<DollarSign className="w-4 h-4" />} label="Squad Value" value={formatMoney(totalValue)} />
                <InfoRow icon={<Trophy className="w-4 h-4" />} label="Avg OVR" value={String(avgOvr)} />
              </div>
            </CardBody>
          </Card>
        )}

        {/* League position */}
        {standings && (
          <Card>
            <CardHeader>League Standing</CardHeader>
            <CardBody>
              <div className="grid grid-cols-4 gap-2 text-center">
                <StatBox label="P" value={standings.played} />
                <StatBox label="W" value={standings.won} />
                <StatBox label="D" value={standings.drawn} />
                <StatBox label="L" value={standings.lost} />
                <StatBox label="GF" value={standings.goals_for} />
                <StatBox label="GA" value={standings.goals_against} />
                <StatBox label="GD" value={standings.goals_for - standings.goals_against} />
                <StatBox label="Pts" value={standings.points} highlight />
              </div>
            </CardBody>
          </Card>
        )}

        {/* Full Roster Table */}
        <Card className="lg:col-span-3">
          <CardHeader>Squad ({roster.length})</CardHeader>
          <CardBody className="p-0">
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Pos</th>
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Name</th>
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Age</th>
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Nationality</th>
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Value</th>
                    {isOwnTeam && <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Condition</th>}
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">OVR</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                  {roster.map(player => {
                    const ovr = calcPlayerOvr(player);
                    const age = calcAge(player.date_of_birth);
                    return (
                      <tr
                        key={player.id}
                        onClick={() => onSelectPlayer?.(player.id)}
                        className="hover:bg-gray-50 dark:hover:bg-navy-700/50 transition-colors cursor-pointer group"
                      >
                        <td className="py-3 px-5">
                          <Badge variant={positionBadgeVariant(player.position)}>
                            {player.position.substring(0, 3).toUpperCase()}
                          </Badge>
                        </td>
                        <td className="py-3 px-5">
                          <span className="font-semibold text-sm text-gray-800 dark:text-gray-200 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors">{player.full_name}</span>
                        </td>
                        <td className="py-3 px-5 text-sm text-gray-600 dark:text-gray-400 tabular-nums">{age}</td>
                        <td className="py-3 px-5 text-sm text-gray-500 dark:text-gray-400">{player.nationality}</td>
                        <td className="py-3 px-5 text-sm text-gray-600 dark:text-gray-400">{formatVal(player.market_value)}</td>
                        {isOwnTeam && (
                          <td className="py-3 px-5">
                            <ProgressBar value={player.condition} variant="auto" size="sm" showLabel className="max-w-[100px]" />
                          </td>
                        )}
                        <td className="py-3 px-5">
                          <span className={`font-heading font-bold text-lg tabular-nums ${
                            isOwnTeam
                              ? ovr >= 75 ? "text-primary-500" : ovr >= 55 ? "text-accent-500" : "text-gray-400"
                              : "text-gray-400"
                          }`}>
                            {isOwnTeam ? ovr : "??"}
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </CardBody>
        </Card>

        {/* History */}
        {team.history.length > 0 && (
          <Card className="lg:col-span-3">
            <CardHeader>Season History</CardHeader>
            <CardBody className="p-0">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">Season</th>
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">Pos</th>
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">P</th>
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">W</th>
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">D</th>
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">L</th>
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">GF</th>
                    <th className="py-3 px-5 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 text-center">GA</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                  {team.history.map((record, i) => (
                    <tr key={i}>
                      <td className="py-3 px-5 font-semibold text-sm text-gray-800 dark:text-gray-200">{record.season}/{record.season + 1}</td>
                      <td className="py-3 px-5 text-center font-heading font-bold text-sm text-primary-500">#{record.league_position}</td>
                      <td className="py-3 px-5 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{record.played}</td>
                      <td className="py-3 px-5 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{record.won}</td>
                      <td className="py-3 px-5 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{record.drawn}</td>
                      <td className="py-3 px-5 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{record.lost}</td>
                      <td className="py-3 px-5 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{record.goals_for}</td>
                      <td className="py-3 px-5 text-center text-sm text-gray-600 dark:text-gray-400 tabular-nums">{record.goals_against}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </CardBody>
          </Card>
        )}
      </div>
    </div>
  );
}

function QuickStat({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <div className="bg-white dark:bg-navy-800 p-3 text-center">
      <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase tracking-wider">{label}</p>
      <p className={`font-heading font-bold text-lg mt-0.5 ${color}`}>{value}</p>
    </div>
  );
}

function InfoRow({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <div className="flex items-center gap-3 py-2 border-b border-gray-100 dark:border-navy-600 last:border-0">
      <div className="text-gray-400 dark:text-gray-500">{icon}</div>
      <span className="text-sm text-gray-500 dark:text-gray-400 flex-1">{label}</span>
      <span className="text-sm font-semibold text-gray-800 dark:text-gray-200">{value}</span>
    </div>
  );
}

function StatBox({ label, value, highlight }: { label: string; value: number; highlight?: boolean }) {
  return (
    <div className={`p-2.5 rounded-lg ${highlight ? "bg-primary-50 dark:bg-primary-500/10" : "bg-gray-50 dark:bg-navy-700"}`}>
      <p className={`font-heading font-bold text-lg tabular-nums ${highlight ? "text-primary-600 dark:text-primary-400" : "text-gray-800 dark:text-gray-100"}`}>{value}</p>
      <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase tracking-wider">{label}</p>
    </div>
  );
}
