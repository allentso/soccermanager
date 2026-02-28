import {
  Zap, Shield, Wind, Dumbbell, Brain, Eye, Target, Crosshair,
  Flame, Heart, Crown, Sparkles, Users,
  Hand, Cat, Mountain, Star, Cog, CircleDot
} from "lucide-react";
import type { ReactNode } from "react";

interface TraitMeta {
  label: string;
  icon: ReactNode;
  color: string;
  category: "physical" | "technical" | "mental" | "goalkeeper" | "special";
  description: string;
}

const TRAIT_META: Record<string, TraitMeta> = {
  Speedster:          { label: "Speedster",           icon: <Zap className="w-3 h-3" />,            color: "text-cyan-400 bg-cyan-500/10 ring-cyan-500/30",       category: "physical",   description: "Exceptional pace" },
  Tank:               { label: "Tank",                icon: <Dumbbell className="w-3 h-3" />,       color: "text-orange-400 bg-orange-500/10 ring-orange-500/30",  category: "physical",   description: "Powerful and tireless" },
  Agile:              { label: "Agile",               icon: <Wind className="w-3 h-3" />,           color: "text-teal-400 bg-teal-500/10 ring-teal-500/30",        category: "physical",   description: "Quick and nimble" },
  Tireless:           { label: "Tireless",            icon: <Heart className="w-3 h-3" />,          color: "text-green-400 bg-green-500/10 ring-green-500/30",     category: "physical",   description: "Never runs out of energy" },
  Playmaker:          { label: "Playmaker",           icon: <Eye className="w-3 h-3" />,            color: "text-purple-400 bg-purple-500/10 ring-purple-500/30",  category: "technical",  description: "Creative passer with vision" },
  Sharpshooter:       { label: "Sharpshooter",        icon: <Target className="w-3 h-3" />,         color: "text-red-400 bg-red-500/10 ring-red-500/30",           category: "technical",  description: "Clinical finisher" },
  Dribbler:           { label: "Dribbler",            icon: <Sparkles className="w-3 h-3" />,       color: "text-yellow-400 bg-yellow-500/10 ring-yellow-500/30",  category: "technical",  description: "Skillful on the ball" },
  BallWinner:         { label: "Ball Winner",         icon: <Crosshair className="w-3 h-3" />,      color: "text-amber-400 bg-amber-500/10 ring-amber-500/30",     category: "technical",  description: "Wins the ball back relentlessly" },
  Rock:               { label: "Rock",                icon: <Shield className="w-3 h-3" />,         color: "text-slate-400 bg-slate-500/10 ring-slate-500/30",     category: "technical",  description: "Immovable defensive wall" },
  Leader:             { label: "Leader",              icon: <Crown className="w-3 h-3" />,          color: "text-accent-400 bg-accent-500/10 ring-accent-500/30",  category: "mental",     description: "Inspires teammates" },
  CoolHead:           { label: "Cool Head",           icon: <Brain className="w-3 h-3" />,          color: "text-blue-400 bg-blue-500/10 ring-blue-500/30",        category: "mental",     description: "Calm under pressure" },
  Visionary:          { label: "Visionary",           icon: <Eye className="w-3 h-3" />,            color: "text-indigo-400 bg-indigo-500/10 ring-indigo-500/30",  category: "mental",     description: "Sees passes others can't" },
  HotHead:            { label: "Hot Head",            icon: <Flame className="w-3 h-3" />,          color: "text-red-500 bg-red-500/10 ring-red-500/30",           category: "mental",     description: "Prone to losing temper" },
  TeamPlayer:         { label: "Team Player",         icon: <Users className="w-3 h-3" />,          color: "text-emerald-400 bg-emerald-500/10 ring-emerald-500/30", category: "mental",   description: "Always puts the team first" },
  SafeHands:          { label: "Safe Hands",          icon: <Hand className="w-3 h-3" />,           color: "text-sky-400 bg-sky-500/10 ring-sky-500/30",           category: "goalkeeper", description: "Reliable shot stopper" },
  CatReflexes:        { label: "Cat Reflexes",        icon: <Cat className="w-3 h-3" />,            color: "text-violet-400 bg-violet-500/10 ring-violet-500/30",  category: "goalkeeper", description: "Lightning-fast reflexes" },
  AerialDominance:    { label: "Aerial Dom.",         icon: <Mountain className="w-3 h-3" />,       color: "text-sky-400 bg-sky-500/10 ring-sky-500/30",           category: "goalkeeper", description: "Commands the box in the air" },
  CompleteForward:    { label: "Complete Forward",    icon: <Star className="w-3 h-3" />,           color: "text-accent-400 bg-accent-500/10 ring-accent-500/30",  category: "special",    description: "Dangerous in every way" },
  Engine:             { label: "Engine",              icon: <Cog className="w-3 h-3" />,            color: "text-primary-400 bg-primary-500/10 ring-primary-500/30", category: "special",  description: "Box-to-box powerhouse" },
  SetPieceSpecialist: { label: "Set Piece Spec.",     icon: <CircleDot className="w-3 h-3" />,      color: "text-lime-400 bg-lime-500/10 ring-lime-500/30",        category: "special",    description: "Deadly from dead balls" },
};

export function getTraitMeta(trait: string): TraitMeta | null {
  return TRAIT_META[trait] || null;
}

export function TraitBadge({ trait: traitName, size = "sm" }: { trait: string; size?: "sm" | "xs" }) {
  const meta = TRAIT_META[traitName];
  if (!meta) return null;

  const sizeClasses = size === "xs"
    ? "text-[9px] px-1.5 py-0.5 gap-0.5"
    : "text-[10px] px-2 py-0.5 gap-1";

  return (
    <span
      className={`inline-flex items-center font-heading font-bold uppercase tracking-wider rounded-full ring-1 ${meta.color} ${sizeClasses}`}
      title={meta.description}
    >
      {meta.icon}
      {meta.label}
    </span>
  );
}

export function TraitList({ traits, size = "sm", max }: { traits: string[]; size?: "sm" | "xs"; max?: number }) {
  if (!traits || traits.length === 0) return null;
  const displayed = max ? traits.slice(0, max) : traits;
  const remaining = max && traits.length > max ? traits.length - max : 0;

  return (
    <div className="flex flex-wrap gap-1">
      {displayed.map(t => <TraitBadge key={t} trait={t} size={size} />)}
      {remaining > 0 && (
        <span className="text-[10px] text-gray-500 font-heading self-center">+{remaining}</span>
      )}
    </div>
  );
}

export default TraitBadge;
