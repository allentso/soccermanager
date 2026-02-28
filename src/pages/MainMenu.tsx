import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useNavigate } from "react-router-dom";
import { useGameStore, GameStateData } from "../store/gameStore";
import { useTheme } from "../context/ThemeContext";
import { Button, ThemeToggle } from "../components/ui";
import { Play, FolderOpen, Settings, X, PlusCircle, Clock, ChevronRight } from "lucide-react";

interface SaveMetadata {
  id: number;
  name: string;
  manager_name: string;
  created_at: string;
  last_played_at: string;
}

export default function MainMenu() {
  const navigate = useNavigate();
  const setGameActive = useGameStore((state) => state.setGameActive);
  const setGameState = useGameStore((state) => state.setGameState);
  const { isDark } = useTheme();
  
  const [menuState, setMenuState] = useState<"main" | "create" | "load">("main");
  const [saves, setSaves] = useState<SaveMetadata[]>([]);
  const [isLoadingSaves, setIsLoadingSaves] = useState(false);
  
  const [formData, setFormData] = useState({
    firstName: "John",
    lastName: "Doe",
    dob: "1980-01-01",
    nationality: "English",
  });

  const handleStartGame = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const game = await invoke<GameStateData>("start_new_game", {
        firstName: formData.firstName,
        lastName: formData.lastName,
        dob: formData.dob,
        nationality: formData.nationality
      });
      setGameState(game);
      navigate("/select-team");
    } catch (error) {
      console.error("Failed to start game:", error);
      alert("Failed to start game: " + String(error));
    }
  };

  const handleOpenLoadMenu = async () => {
    setMenuState("load");
    setIsLoadingSaves(true);
    try {
      const dbSaves = await invoke<SaveMetadata[]>("get_saves");
      setSaves(dbSaves);
    } catch (error) {
      console.error("Failed to load saves:", error);
    } finally {
      setIsLoadingSaves(false);
    }
  };

  const handleLoadGame = async (saveId: number) => {
    try {
      const managerName = await invoke<string>("load_game", { saveId });
      setGameActive(true, managerName);
      navigate("/dashboard");
    } catch (error) {
      console.error("Failed to load game:", error);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-100 dark:bg-navy-900 transition-colors duration-500 relative overflow-hidden">
      {/* Background gradient accents */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-40 -right-40 w-96 h-96 bg-primary-500/10 dark:bg-primary-500/5 rounded-full blur-3xl" />
        <div className="absolute -bottom-40 -left-40 w-96 h-96 bg-accent-400/10 dark:bg-accent-400/5 rounded-full blur-3xl" />
      </div>

      {/* Theme Toggle */}
      <ThemeToggle className="absolute top-6 right-6 z-20" />

      {/* Main Card */}
      <div className="relative z-10 w-full max-w-md">
        {/* Top accent bar */}
        <div className="h-1.5 bg-gradient-to-r from-primary-500 via-accent-400 to-primary-500 rounded-t-2xl" />
        
        <div className="bg-white dark:bg-navy-800 p-8 rounded-b-2xl shadow-xl dark:shadow-2xl border border-gray-200 dark:border-navy-600 border-t-0 transition-all duration-500">
          {/* Logo */}
          <img src="/openfootlogo.svg" alt="OpenFootball" className="text-center w-full h-full object-cover" />

          <div className="border-t border-gray-200 dark:border-navy-600 my-8 transition-colors duration-500" />

          {/* Main Menu */}
          {menuState === "main" && (
            <div className="flex flex-col gap-3">
              <button 
                onClick={() => setMenuState("create")}
                className="group flex items-center justify-between w-full p-4 bg-gradient-to-r from-primary-500 to-primary-600 hover:from-primary-600 hover:to-primary-700 text-white rounded-xl transition-all duration-300 shadow-md hover:shadow-lg hover:shadow-primary-500/20"
              >
                <div className="flex items-center gap-3">
                  <PlusCircle className="w-6 h-6" />
                  <span className="font-heading font-bold text-lg uppercase tracking-wide">New Game</span>
                </div>
                <ChevronRight className="w-5 h-5 opacity-70 group-hover:opacity-100 group-hover:translate-x-0.5 transition-all" />
              </button>
              
              <button 
                onClick={handleOpenLoadMenu}
                className="group flex items-center justify-between w-full p-4 bg-white dark:bg-navy-700 hover:bg-gray-50 dark:hover:bg-navy-600 text-gray-800 dark:text-gray-200 rounded-xl transition-all duration-300 border border-gray-200 dark:border-navy-600 hover:border-accent-400 dark:hover:border-accent-400 shadow-sm"
              >
                <div className="flex items-center gap-3">
                  <FolderOpen className="w-6 h-6 text-accent-500 dark:text-accent-400" />
                  <span className="font-heading font-bold text-lg uppercase tracking-wide">Load Game</span>
                </div>
                <ChevronRight className="w-5 h-5 opacity-0 group-hover:opacity-70 group-hover:translate-x-0.5 transition-all text-accent-500" />
              </button>
              
              <button className="group flex items-center justify-between w-full p-4 bg-white dark:bg-navy-700 hover:bg-gray-50 dark:hover:bg-navy-600 text-gray-800 dark:text-gray-200 rounded-xl transition-all duration-300 border border-gray-200 dark:border-navy-600 hover:border-gray-300 dark:hover:border-navy-600 shadow-sm">
                <div className="flex items-center gap-3">
                  <Settings className="w-6 h-6 text-gray-400 dark:text-gray-500" />
                  <span className="font-heading font-bold text-lg uppercase tracking-wide">Settings</span>
                </div>
              </button>
            </div>
          )}

          {/* Create Manager Form */}
          {menuState === "create" && (
            <form onSubmit={handleStartGame} className="flex flex-col gap-4">
              <div className="flex justify-between items-center mb-2">
                <h2 className="text-xl font-heading font-bold uppercase tracking-wide text-gray-900 dark:text-white transition-colors">
                  Create Manager
                </h2>
                <button 
                  type="button" 
                  onClick={() => setMenuState("main")}
                  className="text-gray-400 hover:text-gray-700 dark:hover:text-white transition-colors p-1 rounded-lg hover:bg-gray-100 dark:hover:bg-navy-600"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>
              
              <div className="flex gap-3">
                <input
                  className="w-full bg-gray-50 dark:bg-navy-900 border border-gray-300 dark:border-navy-600 text-gray-900 dark:text-white rounded-lg p-3 outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 transition-all placeholder:text-gray-400 dark:placeholder:text-gray-500"
                  placeholder="First Name"
                  value={formData.firstName}
                  onChange={e => setFormData({...formData, firstName: e.target.value})}
                  required
                />
                <input
                  className="w-full bg-gray-50 dark:bg-navy-900 border border-gray-300 dark:border-navy-600 text-gray-900 dark:text-white rounded-lg p-3 outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 transition-all placeholder:text-gray-400 dark:placeholder:text-gray-500"
                  placeholder="Last Name"
                  value={formData.lastName}
                  onChange={e => setFormData({...formData, lastName: e.target.value})}
                  required
                />
              </div>
              
              <input
                type="date"
                className="w-full bg-gray-50 dark:bg-navy-900 border border-gray-300 dark:border-navy-600 text-gray-900 dark:text-white rounded-lg p-3 outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 transition-all"
                style={{ colorScheme: isDark ? 'dark' : 'light' }}
                value={formData.dob}
                onChange={e => setFormData({...formData, dob: e.target.value})}
                required
              />
              
              <input
                className="w-full bg-gray-50 dark:bg-navy-900 border border-gray-300 dark:border-navy-600 text-gray-900 dark:text-white rounded-lg p-3 outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 transition-all placeholder:text-gray-400 dark:placeholder:text-gray-500"
                placeholder="Nationality"
                value={formData.nationality}
                onChange={e => setFormData({...formData, nationality: e.target.value})}
                required
              />
              
              <Button type="submit" variant="primary" size="lg" className="mt-2 w-full" iconRight={<ChevronRight />}>
                Start Career
              </Button>
            </form>
          )}

          {/* Load Game List */}
          {menuState === "load" && (
            <div className="flex flex-col gap-4">
              <div className="flex justify-between items-center mb-2">
                <h2 className="text-xl font-heading font-bold uppercase tracking-wide text-gray-900 dark:text-white transition-colors">
                  Load Game
                </h2>
                <button 
                  type="button" 
                  onClick={() => setMenuState("main")}
                  className="text-gray-400 hover:text-gray-700 dark:hover:text-white transition-colors p-1 rounded-lg hover:bg-gray-100 dark:hover:bg-navy-600"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>
              
              <div className="flex flex-col gap-3 max-h-[60vh] overflow-y-auto pr-1">
                {isLoadingSaves ? (
                  <div className="text-gray-500 dark:text-gray-400 text-center py-4">Loading saves...</div>
                ) : saves.length === 0 ? (
                  <div className="text-gray-500 dark:text-gray-400 text-center py-8">No saved games found.</div>
                ) : (
                  saves.map(save => (
                    <button
                      key={save.id}
                      onClick={() => handleLoadGame(save.id)}
                      className="group flex flex-col gap-2 w-full p-4 bg-white dark:bg-navy-700 hover:bg-primary-50 dark:hover:bg-navy-600 text-left rounded-xl transition-all duration-200 border border-gray-200 dark:border-navy-600 hover:border-primary-400 dark:hover:border-primary-500 shadow-sm"
                    >
                      <div className="flex justify-between items-center w-full">
                        <span className="font-heading font-bold text-gray-900 dark:text-white text-lg uppercase tracking-wide">{save.name}</span>
                        <Play className="w-4 h-4 text-primary-500 opacity-0 group-hover:opacity-100 transition-all" />
                      </div>
                      <div className="flex justify-between items-center w-full text-sm text-gray-500 dark:text-gray-400">
                        <span>Manager: {save.manager_name}</span>
                        <div className="flex items-center gap-1">
                          <Clock className="w-3 h-3" />
                          <span>{new Date(save.last_played_at).toLocaleDateString()}</span>
                        </div>
                      </div>
                    </button>
                  ))
                )}
              </div>
            </div>
          )}
        </div>
      </div>
      
      {/* Version */}
      <div className="absolute bottom-4 right-4 text-gray-400 dark:text-gray-600 text-xs font-heading uppercase tracking-widest transition-colors">
        v0.1.0 Alpha
      </div>
    </div>
  );
}
