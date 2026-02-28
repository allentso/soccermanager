import { create } from 'zustand';

export interface TeamColors {
  primary: string;
  secondary: string;
}

export interface TeamSeasonRecord {
  season: number;
  league_position: number;
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goals_for: number;
  goals_against: number;
}

export interface TeamData {
  id: string;
  name: string;
  short_name: string;
  country: string;
  city: string;
  stadium_name: string;
  stadium_capacity: number;
  finance: number;
  manager_id: string | null;
  reputation: number;
  wage_budget: number;
  transfer_budget: number;
  season_income: number;
  season_expenses: number;
  formation: string;
  play_style: string;
  founded_year: number;
  colors: TeamColors;
  history: TeamSeasonRecord[];
}

export interface PlayerSeasonStats {
  appearances: number;
  goals: number;
  assists: number;
  clean_sheets: number;
  yellow_cards: number;
  red_cards: number;
  avg_rating: number;
  minutes_played: number;
}

export interface CareerEntry {
  season: number;
  team_id: string;
  team_name: string;
  appearances: number;
  goals: number;
  assists: number;
}

export interface PlayerData {
  id: string;
  match_name: string;
  full_name: string;
  date_of_birth: string;
  nationality: string;
  position: string;
  attributes: {
    pace: number;
    stamina: number;
    strength: number;
    passing: number;
    shooting: number;
    tackling: number;
    dribbling: number;
    defending: number;
    positioning: number;
    vision: number;
    decisions: number;
  };
  condition: number;
  morale: number;
  injury: null | { name: string; days_remaining: number };
  team_id: string | null;
  contract_end: string | null;
  wage: number;
  market_value: number;
  stats: PlayerSeasonStats;
  career: CareerEntry[];
  transfer_listed: boolean;
  loan_listed: boolean;
  transfer_offers: TransferOfferData[];
}

export interface TransferOfferData {
  id: string;
  from_team_id: string;
  fee: number;
  wage_offered: number;
  status: "Pending" | "Accepted" | "Rejected" | "Withdrawn";
  date: string;
}

export interface StaffData {
  id: string;
  first_name: string;
  last_name: string;
  date_of_birth: string;
  role: "AssistantManager" | "Coach" | "Scout" | "Physio";
  attributes: {
    coaching: number;
    judging_ability: number;
    judging_potential: number;
    physiotherapy: number;
  };
  team_id: string | null;
}

export interface MessageAction {
  id: string;
  label: string;
  action_type: 
    | "Acknowledge"
    | "Dismiss"
    | { NavigateTo: { route: string } }
    | { ChooseOption: { options: { id: string; label: string; description: string }[] } };
  resolved: boolean;
}

export interface MessageContext {
  team_id: string | null;
  player_id: string | null;
  fixture_id: string | null;
  match_result: null | {
    home_team_id: string;
    away_team_id: string;
    home_goals: number;
    away_goals: number;
  };
}

export interface MessageData {
  id: string;
  subject: string;
  body: string;
  sender: string;
  sender_role: string;
  date: string;
  read: boolean;
  category: string;
  priority: string;
  actions: MessageAction[];
  context: MessageContext;
}

export interface ManagerCareerStats {
  matches_managed: number;
  wins: number;
  draws: number;
  losses: number;
  trophies: number;
  best_finish: number | null;
}

export interface ManagerCareerEntry {
  team_id: string;
  team_name: string;
  start_date: string;
  end_date: string | null;
  matches: number;
  wins: number;
  draws: number;
  losses: number;
  best_league_position: number | null;
}

export interface FixtureData {
  id: string;
  matchday: number;
  date: string;
  home_team_id: string;
  away_team_id: string;
  status: "Scheduled" | "InProgress" | "Completed";
  result: null | {
    home_goals: number;
    away_goals: number;
    home_scorers: { player_id: string; minute: number }[];
    away_scorers: { player_id: string; minute: number }[];
  };
}

export interface StandingData {
  team_id: string;
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goals_for: number;
  goals_against: number;
  points: number;
}

export interface LeagueData {
  id: string;
  name: string;
  season: number;
  fixtures: FixtureData[];
  standings: StandingData[];
}

export interface GameStateData {
  clock: {
    current_date: string;
    start_date: string;
  };
  manager: {
    id: string;
    first_name: string;
    last_name: string;
    date_of_birth: string;
    nationality: string;
    reputation: number;
    satisfaction: number;
    team_id: string | null;
    career_stats: ManagerCareerStats;
    career_history: ManagerCareerEntry[];
  };
  teams: TeamData[];
  players: PlayerData[];
  staff: StaffData[];
  messages: MessageData[];
  league: LeagueData | null;
}

interface GameStore {
  hasActiveGame: boolean;
  managerName: string | null;
  gameState: GameStateData | null;
  setGameActive: (active: boolean, managerName?: string) => void;
  setGameState: (state: GameStateData) => void;
  clearGame: () => void;
}

export const useGameStore = create<GameStore>((set) => ({
  hasActiveGame: false,
  managerName: null,
  gameState: null,
  setGameActive: (active, managerName) => set({ 
    hasActiveGame: active, 
    managerName: managerName || null 
  }),
  setGameState: (state) => set({
    gameState: state
  }),
  clearGame: () => set({
    hasActiveGame: false,
    managerName: null,
    gameState: null,
  }),
}));
