// Shared types for match simulation components — mirrors Rust engine types

export interface MatchEvent {
  minute: number;
  event_type: string;
  side: "Home" | "Away";
  zone: string;
  player_id: string | null;
  secondary_player_id: string | null;
}

export interface EnginePlayerData {
  id: string;
  name: string;
  position: string;
  condition: number;
  pace: number;
  stamina: number;
  strength: number;
  agility: number;
  passing: number;
  shooting: number;
  tackling: number;
  dribbling: number;
  defending: number;
  positioning: number;
  vision: number;
  decisions: number;
  composure: number;
  aggression: number;
  teamwork: number;
  leadership: number;
  handling: number;
  reflexes: number;
  aerial: number;
  traits: string[];
}

export interface EngineTeamData {
  id: string;
  name: string;
  formation: string;
  play_style: string;
  players: EnginePlayerData[];
}

export interface SetPieceTakers {
  free_kick_taker: string | null;
  corner_taker: string | null;
  penalty_taker: string | null;
  captain: string | null;
}

export interface SubstitutionRecord {
  minute: number;
  side: "Home" | "Away";
  player_off_id: string;
  player_on_id: string;
}

export interface MatchSnapshot {
  phase: string;
  current_minute: number;
  home_score: number;
  away_score: number;
  possession: "Home" | "Away";
  ball_zone: string;
  home_team: EngineTeamData;
  away_team: EngineTeamData;
  home_bench: EnginePlayerData[];
  away_bench: EnginePlayerData[];
  home_possession_pct: number;
  away_possession_pct: number;
  events: MatchEvent[];
  home_subs_made: number;
  away_subs_made: number;
  max_subs: number;
  home_set_pieces: SetPieceTakers;
  away_set_pieces: SetPieceTakers;
  substitutions: SubstitutionRecord[];
  allows_extra_time: boolean;
  home_yellows: Record<string, number>;
  away_yellows: Record<string, number>;
  sent_off: string[];
}

export interface MinuteResult {
  minute: number;
  phase: string;
  events: MatchEvent[];
  home_score: number;
  away_score: number;
  possession: "Home" | "Away";
  ball_zone: string;
  is_finished: boolean;
}

export type SimSpeed = "paused" | "slow" | "normal" | "fast" | "instant";

export type MatchDayStage =
  | "prematch"
  | "first_half"
  | "halftime"
  | "second_half"
  | "postmatch"
  | "press";

export type TeamTalkTone =
  | "calm"
  | "motivational"
  | "assertive"
  | "aggressive"
  | "praise"
  | "disappointed";

export interface TeamTalkOption {
  id: TeamTalkTone;
  label: string;
  description: string;
  icon: string;
}

export const TEAM_TALK_OPTIONS: TeamTalkOption[] = [
  { id: "calm", label: "Stay Calm", description: "Keep composure and focus on the game plan.", icon: "calm" },
  { id: "motivational", label: "Motivate", description: "Inspire the players to give their best.", icon: "motivational" },
  { id: "assertive", label: "Demand More", description: "Tell them this isn't good enough.", icon: "assertive" },
  { id: "aggressive", label: "Get Fired Up", description: "An aggressive, fiery team talk.", icon: "aggressive" },
  { id: "praise", label: "Praise", description: "Tell them they've been excellent.", icon: "praise" },
  { id: "disappointed", label: "Show Disappointment", description: "Express disappointment in their effort.", icon: "disappointed" },
];

export const SPEED_MS: Record<SimSpeed, number> = {
  paused: 0,
  slow: 2000,
  normal: 800,
  fast: 200,
  instant: 10,
};

export const FORMATIONS = ["4-4-2", "4-3-3", "3-5-2", "4-5-1", "4-2-3-1", "3-4-3"];

export const PLAY_STYLES = [
  { id: "Balanced", label: "Balanced" },
  { id: "Attacking", label: "Attacking" },
  { id: "Defensive", label: "Defensive" },
  { id: "Possession", label: "Possession" },
  { id: "Counter", label: "Counter" },
  { id: "HighPress", label: "High Press" },
];
