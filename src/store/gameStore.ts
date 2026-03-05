import { create } from 'zustand';
import type { GameStateData } from './types';

// Re-export all types so existing imports from gameStore keep working
export type {
  TeamColors,
  TeamSeasonRecord,
  TeamData,
  PlayerSeasonStats,
  CareerEntry,
  PlayerData,
  TransferOfferData,
  StaffData,
  MessageAction,
  MessageContext,
  MessageData,
  ManagerCareerStats,
  ManagerCareerEntry,
  FixtureData,
  StandingData,
  LeagueData,
  NewsMatchScore,
  NewsArticle,
  BoardObjective,
  ScoutingAssignment,
  GameStateData,
} from './types';

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
