import { invoke } from "@tauri-apps/api/core";
import { GameStateData } from "../store/gameStore";
import { Card, CardHeader, CardBody, ProgressBar } from "./ui";
import { calcOvr } from "../lib/helpers";

const FORMATIONS = ["4-4-2", "4-3-3", "4-2-3-1", "3-5-2", "3-4-3", "5-3-2", "4-5-1", "4-1-4-1"];
const PLAY_STYLE_OPTIONS = ["Balanced", "Attacking", "Defensive", "Possession", "Counter", "HighPress"];

interface TacticsTabProps {
  gameState: GameStateData;
  onSelectPlayer: (id: string) => void;
  onGameUpdate: (g: GameStateData) => void;
}

export default function TacticsTab({ gameState, onSelectPlayer, onGameUpdate }: TacticsTabProps) {
  const myTeam = gameState.teams.find(t => t.id === gameState.manager.team_id);
  if (!myTeam) return <p className="text-gray-500 dark:text-gray-400">No team assigned.</p>;

  const roster = gameState.players.filter(p => p.team_id === myTeam.id);
  const posOrder: Record<string, number> = { Goalkeeper: 1, Defender: 2, Midfielder: 3, Forward: 4 };
  const sorted = [...roster].sort((a, b) => (posOrder[a.position] || 99) - (posOrder[b.position] || 99));

  return (
    <div className="max-w-6xl mx-auto grid grid-cols-1 lg:grid-cols-3 gap-5">
      {/* Formation & Style */}
      <Card accent="primary">
        <CardHeader>Formation & Style</CardHeader>
        <CardBody>
          <div className="mb-4">
            <label className="text-xs font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-2 block">Formation</label>
            <div className="grid grid-cols-4 gap-2">
              {FORMATIONS.map(f => (
                <button key={f} onClick={async () => {
                  try { const g = await invoke<GameStateData>("set_formation", { formation: f }); onGameUpdate(g); } catch {}
                }} className={`px-3 py-2 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
                  myTeam.formation === f
                    ? "bg-primary-500 text-white shadow-sm"
                    : "bg-gray-100 dark:bg-navy-700 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-navy-600"
                }`}>
                  {f}
                </button>
              ))}
            </div>
          </div>
          <div>
            <label className="text-xs font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-2 block">Play Style</label>
            <div className="grid grid-cols-3 gap-2">
              {PLAY_STYLE_OPTIONS.map(s => (
                <button key={s} onClick={async () => {
                  try { const g = await invoke<GameStateData>("set_play_style", { playStyle: s }); onGameUpdate(g); } catch {}
                }} className={`px-3 py-2 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${
                  myTeam.play_style === s
                    ? "bg-accent-500 text-white shadow-sm"
                    : "bg-gray-100 dark:bg-navy-700 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-navy-600"
                }`}>
                  {s}
                </button>
              ))}
            </div>
          </div>
        </CardBody>
      </Card>

      {/* Formation Visual */}
      <Card className="lg:col-span-2">
        <CardHeader>Starting XI — {myTeam.formation}</CardHeader>
        <CardBody>
          <div className="bg-gradient-to-b from-primary-700/20 to-primary-900/30 dark:from-primary-900/40 dark:to-navy-900/60 rounded-xl p-6 min-h-[320px] relative border border-primary-500/20">
            {/* Pitch lines */}
            <div className="absolute inset-x-6 top-1/2 border-t border-white/10" />
            <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-20 h-20 border border-white/10 rounded-full" />

            {/* Position groups — parsed from formation */}
            {(() => {
              const groups: Record<string, typeof roster> = { Goalkeeper: [], Defender: [], Midfielder: [], Forward: [] };
              sorted.forEach(p => { if (groups[p.position]) groups[p.position].push(p); });

              // Parse formation string (e.g. "4-3-3", "4-2-3-1", "3-5-2")
              const parts = myTeam.formation.split("-").map(Number).filter(n => !isNaN(n));
              let defCount = 4, midCount = 4, fwdCount = 2;
              if (parts.length === 3) {
                defCount = parts[0]; midCount = parts[1]; fwdCount = parts[2];
              } else if (parts.length === 4) {
                defCount = parts[0]; midCount = parts[1] + parts[2]; fwdCount = parts[3];
              }

              // Build rows with y-positions spaced evenly
              // For 3-part formations: GK, DEF, MID, FWD
              // For 4-part formations: GK, DEF, DM, AM, FWD
              type PitchRow = { label: string; y: string; players: typeof roster };
              let rows: PitchRow[];

              if (parts.length === 4) {
                // Split midfield into two rows (e.g. 4-2-3-1 → DEF(4), DM(2), AM(3), FWD(1))
                const dmCount = parts[1];
                const amCount = parts[2];
                const dms = groups.Midfielder.slice(0, dmCount);
                const ams = groups.Midfielder.slice(dmCount, dmCount + amCount);
                rows = [
                  { label: "GK", y: "88%", players: groups.Goalkeeper.slice(0, 1) },
                  { label: "DEF", y: "70%", players: groups.Defender.slice(0, defCount) },
                  { label: "DM", y: "50%", players: dms },
                  { label: "AM", y: "30%", players: ams },
                  { label: "FWD", y: "12%", players: groups.Forward.slice(0, fwdCount) },
                ];
              } else {
                rows = [
                  { label: "GK", y: "85%", players: groups.Goalkeeper.slice(0, 1) },
                  { label: "DEF", y: "62%", players: groups.Defender.slice(0, defCount) },
                  { label: "MID", y: "38%", players: groups.Midfielder.slice(0, midCount) },
                  { label: "FWD", y: "14%", players: groups.Forward.slice(0, fwdCount) },
                ];
              }

              return rows.map(row => (
                <div key={row.label} className="absolute left-0 right-0 flex justify-center gap-6" style={{ top: row.y, transform: "translateY(-50%)" }}>
                  {row.players.map(p => (
                    <button key={p.id} onClick={() => onSelectPlayer(p.id)} className="flex flex-col items-center gap-1 group cursor-pointer">
                      <div className={`w-10 h-10 rounded-full flex items-center justify-center font-heading font-bold text-sm border-2 transition-all group-hover:scale-110 ${
                        p.condition >= 70
                          ? "bg-primary-500/80 border-primary-300 text-white"
                          : "bg-red-500/80 border-red-300 text-white"
                      }`}>
                        {calcOvr(p)}
                      </div>
                      <span className="text-xs text-white/80 font-medium truncate max-w-[70px]">{p.match_name}</span>
                    </button>
                  ))}
                </div>
              ));
            })()}
          </div>
        </CardBody>
      </Card>

      {/* Full squad list for selection */}
      <Card className="lg:col-span-3">
        <CardHeader>Full Squad</CardHeader>
        <CardBody className="p-0">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-px bg-gray-200 dark:bg-navy-600">
            {sorted.map(p => (
              <button key={p.id} onClick={() => onSelectPlayer(p.id)} className="bg-white dark:bg-navy-700 p-3 flex items-center gap-3 hover:bg-gray-50 dark:hover:bg-navy-600/50 transition-colors text-left">
                <div className={`w-8 h-8 rounded-full flex items-center justify-center font-heading font-bold text-xs ${
                  calcOvr(p) >= 75 ? "bg-primary-500/20 text-primary-500" :
                  calcOvr(p) >= 55 ? "bg-accent-500/20 text-accent-500" :
                  "bg-gray-200 dark:bg-navy-600 text-gray-500"
                }`}>
                  {calcOvr(p)}
                </div>
                <div className="min-w-0">
                  <p className="text-sm font-semibold text-gray-800 dark:text-gray-200 truncate">{p.match_name}</p>
                  <p className="text-xs text-gray-400 dark:text-gray-500">{p.position}</p>
                </div>
                <ProgressBar value={p.condition} variant="auto" size="sm" className="ml-auto w-16" />
              </button>
            ))}
          </div>
        </CardBody>
      </Card>
    </div>
  );
}
