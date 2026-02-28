import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";

export interface AppSettings {
  theme: "dark" | "light" | "system";
  currency: "EUR" | "GBP" | "USD";
  default_match_mode: "live" | "spectator" | "delegate";
  auto_save: boolean;
  match_speed: "slow" | "normal" | "fast";
  show_match_commentary: boolean;
  confirm_advance: boolean;
}

const DEFAULT_SETTINGS: AppSettings = {
  theme: "dark",
  currency: "EUR",
  default_match_mode: "live",
  auto_save: true,
  match_speed: "normal",
  show_match_commentary: true,
  confirm_advance: false,
};

interface SettingsStore {
  settings: AppSettings;
  loaded: boolean;
  loadSettings: () => Promise<void>;
  updateSettings: (partial: Partial<AppSettings>) => Promise<void>;
}

export const useSettingsStore = create<SettingsStore>((set, get) => ({
  settings: DEFAULT_SETTINGS,
  loaded: false,

  loadSettings: async () => {
    try {
      const s = await invoke<AppSettings>("get_settings");
      set({ settings: { ...DEFAULT_SETTINGS, ...s }, loaded: true });
    } catch {
      set({ settings: DEFAULT_SETTINGS, loaded: true });
    }
  },

  updateSettings: async (partial) => {
    const merged = { ...get().settings, ...partial };
    set({ settings: merged });
    try {
      await invoke("save_settings", { settings: merged });
    } catch (err) {
      console.error("Failed to save settings:", err);
    }
  },
}));
