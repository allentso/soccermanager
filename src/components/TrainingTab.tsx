import { useState } from "react";
import { GameStateData } from "../store/gameStore";
import { Card, CardHeader, CardBody, ProgressBar } from "./ui";
import { HeartPulse, Crosshair, Brain, Shield, Zap, BedDouble } from "lucide-react";

interface TrainingTabProps {
  gameState: GameStateData;
}

const TRAINING_FOCUSES: { id: string; label: string; icon: React.ReactNode; desc: string }[] = [
  { id: "physical", label: "Physical", icon: <HeartPulse className="w-6 h-6" />, desc: "Pace, Stamina, Strength" },
  { id: "technical", label: "Technical", icon: <Crosshair className="w-6 h-6" />, desc: "Passing, Shooting, Dribbling" },
  { id: "tactical", label: "Tactical", icon: <Brain className="w-6 h-6" />, desc: "Positioning, Vision, Decisions" },
  { id: "defending", label: "Defending", icon: <Shield className="w-6 h-6" />, desc: "Tackling, Defending, Strength" },
  { id: "attacking", label: "Attacking", icon: <Zap className="w-6 h-6" />, desc: "Shooting, Dribbling, Pace" },
  { id: "recovery", label: "Recovery", icon: <BedDouble className="w-6 h-6" />, desc: "Rest day — recover condition" },
];

export default function TrainingTab({ gameState }: TrainingTabProps) {
  const myTeam = gameState.teams.find(t => t.id === gameState.manager.team_id);
  if (!myTeam) return <p className="text-gray-500 dark:text-gray-400">No team assigned.</p>;

  const [selectedFocus, setSelectedFocus] = useState("physical");
  const roster = gameState.players.filter(p => p.team_id === myTeam.id);
  const avgCondition = roster.length > 0 ? Math.round(roster.reduce((s, p) => s + p.condition, 0) / roster.length) : 0;
  const avgMorale = roster.length > 0 ? Math.round(roster.reduce((s, p) => s + p.morale, 0) / roster.length) : 0;

  return (
    <div className="max-w-6xl mx-auto grid grid-cols-1 lg:grid-cols-3 gap-5">
      {/* Training focus selection */}
      <Card accent="primary" className="lg:col-span-2">
        <CardHeader>Training Focus</CardHeader>
        <CardBody>
          <div className="grid grid-cols-3 gap-3">
            {TRAINING_FOCUSES.map(tf => (
              <button
                key={tf.id}
                onClick={() => setSelectedFocus(tf.id)}
                className={`p-4 rounded-xl text-left transition-all border-2 ${
                  selectedFocus === tf.id
                    ? "border-primary-500 bg-primary-50 dark:bg-primary-500/10 shadow-md shadow-primary-500/10"
                    : "border-gray-200 dark:border-navy-600 hover:border-gray-300 dark:hover:border-navy-500"
                }`}
              >
                <div className="mb-2 text-gray-600 dark:text-gray-300">{tf.icon}</div>
                <p className="font-heading font-bold text-sm uppercase tracking-wider text-gray-800 dark:text-gray-200">{tf.label}</p>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">{tf.desc}</p>
              </button>
            ))}
          </div>
          <p className="text-xs text-gray-400 dark:text-gray-500 mt-4">
            Training focus is applied during daily processing. Click Continue to advance to the next day.
          </p>
        </CardBody>
      </Card>

      {/* Squad fitness overview */}
      <div className="flex flex-col gap-5">
        <Card accent="accent">
          <CardHeader>Squad Fitness</CardHeader>
          <CardBody>
            <div className="flex flex-col gap-3">
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-gray-600 dark:text-gray-400">Avg Condition</span>
                  <span className="font-heading font-bold text-gray-800 dark:text-gray-100">{avgCondition}%</span>
                </div>
                <ProgressBar value={avgCondition} variant="auto" size="md" />
              </div>
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-gray-600 dark:text-gray-400">Avg Morale</span>
                  <span className="font-heading font-bold text-gray-800 dark:text-gray-100">{avgMorale}%</span>
                </div>
                <ProgressBar value={avgMorale} variant="auto" size="md" />
              </div>
            </div>
          </CardBody>
        </Card>

        <Card>
          <CardHeader>Player Fitness</CardHeader>
          <CardBody className="p-0 max-h-64 overflow-y-auto">
            <div className="divide-y divide-gray-100 dark:divide-navy-600">
              {roster.sort((a, b) => a.condition - b.condition).map(p => (
                <div key={p.id} className="flex items-center px-4 py-2 gap-3">
                  <span className="text-sm font-medium text-gray-800 dark:text-gray-200 flex-1 truncate">{p.match_name}</span>
                  <ProgressBar value={p.condition} variant="auto" size="sm" showLabel className="w-24" />
                </div>
              ))}
            </div>
          </CardBody>
        </Card>
      </div>
    </div>
  );
}
