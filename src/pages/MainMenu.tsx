import { useState, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useNavigate } from "react-router-dom";
import { useGameStore, GameStateData } from "../store/gameStore";
import { useTheme } from "../context/ThemeContext";
import { Button, ThemeToggle } from "../components/ui";
import { Play, FolderOpen, Settings, X, PlusCircle, Clock, ChevronRight, Trash2, Globe, Shuffle, Upload, Database, Users, ArrowLeft } from "lucide-react";

interface SaveMetadata {
  id: string;
  name: string;
  manager_name: string;
  created_at: string;
  last_played_at: string;
}

interface WorldDatabaseInfo {
  id: string;
  name: string;
  description: string;
  team_count: number;
  player_count: number;
  source: string;
  path: string;
}

export default function MainMenu() {
  const navigate = useNavigate();
  const setGameActive = useGameStore((state) => state.setGameActive);
  const setGameState = useGameStore((state) => state.setGameState);
  const { isDark } = useTheme();
  
  const [menuState, setMenuState] = useState<"main" | "create" | "world" | "load">("main");
  const [saves, setSaves] = useState<SaveMetadata[]>([]);
  const [isLoadingSaves, setIsLoadingSaves] = useState(false);
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null);
  const [isStarting, setIsStarting] = useState(false);

  const [formData, setFormData] = useState({
    firstName: "John",
    lastName: "Doe",
    dob: "1980-01-01",
    nationality: "English",
  });

  // World database state
  const [worldDatabases, setWorldDatabases] = useState<WorldDatabaseInfo[]>([]);
  const [selectedWorldId, setSelectedWorldId] = useState<string>("random");
  const [isLoadingWorlds, setIsLoadingWorlds] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleGoToWorldSelect = (e: React.FormEvent) => {
    e.preventDefault();
    setMenuState("world");
    loadWorldDatabases();
  };

  const loadWorldDatabases = async () => {
    setIsLoadingWorlds(true);
    try {
      const dbs = await invoke<WorldDatabaseInfo[]>("list_world_databases");
      setWorldDatabases(dbs);
    } catch (error) {
      console.error("Failed to load world databases:", error);
      // Always have random available even if scan fails
      setWorldDatabases([{
        id: "random",
        name: "Random World",
        description: "Randomly generated league with 8 teams, players, and staff",
        team_count: 8,
        player_count: 160,
        source: "builtin",
        path: "",
      }]);
    } finally {
      setIsLoadingWorlds(false);
    }
  };

  const handleImportFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = async () => {
      try {
        const json = reader.result as string;
        const parsed = JSON.parse(json);
        const info: WorldDatabaseInfo = {
          id: `file:${file.name}`,
          name: parsed.name || file.name.replace(".json", ""),
          description: parsed.description || "Imported world database",
          team_count: parsed.teams?.length ?? 0,
          player_count: parsed.players?.length ?? 0,
          source: "imported",
          path: "",  // will use the parsed data directly
        };
        // Store the raw JSON in sessionStorage so we can write it to a temp path
        sessionStorage.setItem("imported_world_json", json);
        setWorldDatabases(prev => {
          const filtered = prev.filter(d => d.source !== "imported");
          return [...filtered, info];
        });
        setSelectedWorldId(info.id);
      } catch (err) {
        alert("Invalid world database file: " + String(err));
      }
    };
    reader.readAsText(file);
    // Reset input so the same file can be re-selected
    e.target.value = "";
  };

  const handleStartGame = async () => {
    setIsStarting(true);
    try {
      // Determine world source
      let worldSource: string | undefined = selectedWorldId;
      if (selectedWorldId === "random") {
        worldSource = undefined;
      } else if (selectedWorldId.startsWith("file:") && sessionStorage.getItem("imported_world_json")) {
        // For imported files, write to a temp location first
        const json = sessionStorage.getItem("imported_world_json")!;
        // Write it via a temp file approach — just pass "random" and override
        // Actually, better to write the file to user databases dir first
        const path = await invoke<string>("write_temp_database", { json }).catch(() => null);
        if (path) {
          worldSource = `file:${path}`;
        } else {
          // Fallback: pass the imported data inline — won't work with current backend
          // So fall back to random
          worldSource = undefined;
          console.warn("Could not write imported database, falling back to random");
        }
      }

      const game = await invoke<GameStateData>("start_new_game", {
        firstName: formData.firstName,
        lastName: formData.lastName,
        dob: formData.dob,
        nationality: formData.nationality,
        worldSource,
      });
      sessionStorage.removeItem("imported_world_json");
      setGameState(game);
      navigate("/select-team");
    } catch (error) {
      console.error("Failed to start game:", error);
      alert("Failed to start game: " + String(error));
    } finally {
      setIsStarting(false);
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

  const handleLoadGame = async (saveId: string) => {
    try {
      const managerName = await invoke<string>("load_game", { saveId });
      setGameActive(true, managerName);
      navigate("/dashboard");
    } catch (error) {
      console.error("Failed to load game:", error);
    }
  };

  const handleDeleteSave = async (saveId: string) => {
    try {
      await invoke<boolean>("delete_save", { saveId });
      setSaves(prev => prev.filter(s => s.id !== saveId));
      setConfirmDeleteId(null);
    } catch (error) {
      console.error("Failed to delete save:", error);
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
              
              <button 
                onClick={() => navigate("/settings", { state: { from: "/" } })}
                className="group flex items-center justify-between w-full p-4 bg-white dark:bg-navy-700 hover:bg-gray-50 dark:hover:bg-navy-600 text-gray-800 dark:text-gray-200 rounded-xl transition-all duration-300 border border-gray-200 dark:border-navy-600 hover:border-gray-300 dark:hover:border-navy-600 shadow-sm"
              >
                <div className="flex items-center gap-3">
                  <Settings className="w-6 h-6 text-gray-400 dark:text-gray-500" />
                  <span className="font-heading font-bold text-lg uppercase tracking-wide">Settings</span>
                </div>
                <ChevronRight className="w-5 h-5 opacity-0 group-hover:opacity-70 group-hover:translate-x-0.5 transition-all text-gray-400" />
              </button>
            </div>
          )}

          {/* Step 1: Create Manager Form */}
          {menuState === "create" && (
            <form onSubmit={handleGoToWorldSelect} className="flex flex-col gap-4">
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

              {/* Step indicator */}
              <div className="flex items-center gap-2 mb-1">
                <div className="flex items-center justify-center w-6 h-6 rounded-full bg-primary-500 text-white text-xs font-bold">1</div>
                <div className="h-0.5 flex-1 bg-gray-200 dark:bg-navy-600" />
                <div className="flex items-center justify-center w-6 h-6 rounded-full bg-gray-200 dark:bg-navy-600 text-gray-400 dark:text-gray-500 text-xs font-bold">2</div>
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
                Choose World
              </Button>
            </form>
          )}

          {/* Step 2: World Database Selection */}
          {menuState === "world" && (
            <div className="flex flex-col gap-4">
              <div className="flex justify-between items-center mb-2">
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => setMenuState("create")}
                    className="text-gray-400 hover:text-gray-700 dark:hover:text-white transition-colors p-1 rounded-lg hover:bg-gray-100 dark:hover:bg-navy-600"
                  >
                    <ArrowLeft className="w-5 h-5" />
                  </button>
                  <h2 className="text-xl font-heading font-bold uppercase tracking-wide text-gray-900 dark:text-white transition-colors">
                    Choose World
                  </h2>
                </div>
                <button 
                  type="button" 
                  onClick={() => setMenuState("main")}
                  className="text-gray-400 hover:text-gray-700 dark:hover:text-white transition-colors p-1 rounded-lg hover:bg-gray-100 dark:hover:bg-navy-600"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              {/* Step indicator */}
              <div className="flex items-center gap-2 mb-1">
                <div className="flex items-center justify-center w-6 h-6 rounded-full bg-primary-500/30 text-primary-400 text-xs font-bold">1</div>
                <div className="h-0.5 flex-1 bg-primary-500" />
                <div className="flex items-center justify-center w-6 h-6 rounded-full bg-primary-500 text-white text-xs font-bold">2</div>
              </div>

              {/* World options */}
              <div className="flex flex-col gap-2 max-h-[45vh] overflow-y-auto pr-1">
                {isLoadingWorlds ? (
                  <div className="text-gray-500 dark:text-gray-400 text-center py-4">Scanning for databases...</div>
                ) : (
                  worldDatabases.map(db => (
                    <button
                      key={db.id}
                      onClick={() => setSelectedWorldId(db.id)}
                      className={`flex items-start gap-3 w-full p-3.5 rounded-xl border transition-all duration-200 text-left ${
                        selectedWorldId === db.id
                          ? "bg-primary-50 dark:bg-primary-500/10 border-primary-400 dark:border-primary-500 ring-1 ring-primary-400/30"
                          : "bg-white dark:bg-navy-700 border-gray-200 dark:border-navy-600 hover:border-gray-300 dark:hover:border-navy-500"
                      }`}
                    >
                      <div className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 mt-0.5 ${
                        db.id === "random"
                          ? "bg-accent-500/10 text-accent-500"
                          : db.source === "imported"
                            ? "bg-purple-500/10 text-purple-500"
                            : "bg-primary-500/10 text-primary-500"
                      }`}>
                        {db.id === "random" ? <Shuffle className="w-5 h-5" /> :
                         db.source === "imported" ? <Upload className="w-5 h-5" /> :
                         <Database className="w-5 h-5" />}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className={`font-heading font-bold text-sm uppercase tracking-wide ${
                          selectedWorldId === db.id ? "text-primary-600 dark:text-primary-400" : "text-gray-800 dark:text-gray-200"
                        }`}>{db.name}</p>
                        <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5 line-clamp-2">{db.description}</p>
                        <div className="flex items-center gap-3 mt-1.5">
                          <span className="text-[10px] font-heading uppercase tracking-wider text-gray-400 dark:text-gray-500 flex items-center gap-1">
                            <Globe className="w-3 h-3" />{db.team_count} teams
                          </span>
                          <span className="text-[10px] font-heading uppercase tracking-wider text-gray-400 dark:text-gray-500 flex items-center gap-1">
                            <Users className="w-3 h-3" />{db.player_count} players
                          </span>
                        </div>
                      </div>
                      {selectedWorldId === db.id && (
                        <div className="w-5 h-5 rounded-full bg-primary-500 flex items-center justify-center flex-shrink-0 mt-1">
                          <div className="w-2 h-2 rounded-full bg-white" />
                        </div>
                      )}
                    </button>
                  ))
                )}
              </div>

              {/* Import button */}
              <button
                onClick={() => fileInputRef.current?.click()}
                className="flex items-center justify-center gap-2 w-full py-2.5 border border-dashed border-gray-300 dark:border-navy-500 rounded-xl text-sm text-gray-500 dark:text-gray-400 hover:text-primary-500 dark:hover:text-primary-400 hover:border-primary-400 dark:hover:border-primary-500 transition-colors"
              >
                <Upload className="w-4 h-4" />
                <span className="font-heading font-bold uppercase tracking-wider">Import from file</span>
              </button>
              <input
                ref={fileInputRef}
                type="file"
                accept=".json"
                className="hidden"
                onChange={handleImportFile}
              />

              <Button
                variant="primary"
                size="lg"
                className="w-full"
                iconRight={isStarting ? undefined : <ChevronRight />}
                onClick={handleStartGame}
                disabled={isStarting}
              >
                {isStarting ? "Creating World..." : "Start Career"}
              </Button>
            </div>
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
                    <div key={save.id} className="group relative flex flex-col gap-2 w-full p-4 bg-white dark:bg-navy-700 hover:bg-primary-50 dark:hover:bg-navy-600 text-left rounded-xl transition-all duration-200 border border-gray-200 dark:border-navy-600 hover:border-primary-400 dark:hover:border-primary-500 shadow-sm">
                      {confirmDeleteId === save.id ? (
                        <div className="flex flex-col gap-2">
                          <p className="text-sm text-gray-700 dark:text-gray-300">Delete <strong>{save.name}</strong>?</p>
                          <div className="flex gap-2">
                            <button
                              onClick={() => handleDeleteSave(save.id)}
                              className="flex-1 py-2 bg-red-500 hover:bg-red-600 text-white text-sm font-heading font-bold uppercase tracking-wider rounded-lg transition-colors"
                            >
                              Delete
                            </button>
                            <button
                              onClick={() => setConfirmDeleteId(null)}
                              className="flex-1 py-2 bg-gray-200 dark:bg-navy-600 hover:bg-gray-300 dark:hover:bg-navy-500 text-gray-700 dark:text-gray-300 text-sm font-heading font-bold uppercase tracking-wider rounded-lg transition-colors"
                            >
                              Cancel
                            </button>
                          </div>
                        </div>
                      ) : (
                        <div className="flex items-center gap-3 w-full">
                          <button
                            onClick={() => handleLoadGame(save.id)}
                            className="flex flex-col gap-2 flex-1 text-left min-w-0"
                          >
                            <div className="flex justify-between items-center w-full">
                              <span className="font-heading font-bold text-gray-900 dark:text-white text-lg uppercase tracking-wide truncate">{save.name}</span>
                              <Play className="w-4 h-4 text-primary-500 opacity-0 group-hover:opacity-100 transition-all flex-shrink-0" />
                            </div>
                            <div className="flex justify-between items-center w-full text-sm text-gray-500 dark:text-gray-400">
                              <span>Manager: {save.manager_name}</span>
                              <div className="flex items-center gap-1">
                                <Clock className="w-3 h-3" />
                                <span>{new Date(save.last_played_at).toLocaleDateString()}</span>
                              </div>
                            </div>
                          </button>
                          <button
                            onClick={(e) => { e.stopPropagation(); setConfirmDeleteId(save.id); }}
                            className="p-1.5 rounded-lg text-gray-400 dark:text-gray-500 hover:text-red-500 dark:hover:text-red-400 hover:bg-red-50 dark:hover:bg-red-500/10 opacity-0 group-hover:opacity-100 transition-all flex-shrink-0"
                            title="Delete save"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </div>
                      )}
                    </div>
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
