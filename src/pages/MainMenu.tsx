import { useState, useRef, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { useGameStore, GameStateData } from "../store/gameStore";
import { useTheme } from "../context/ThemeContext";
import { Button, ThemeToggle } from "../components/ui";
import SavesList from "../components/menu/SavesList";
import WorldSelect, { WorldDatabaseInfo } from "../components/menu/WorldSelect";
import { FolderOpen, Settings, X, PlusCircle, ChevronRight, AlertCircle, ChevronDown, Check } from "lucide-react";

interface SaveMetadata {
  id: string;
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
  const { t } = useTranslation();
  
  const [menuState, setMenuState] = useState<"main" | "create" | "world" | "load">("main");
  const [saves, setSaves] = useState<SaveMetadata[]>([]);
  const [isLoadingSaves, setIsLoadingSaves] = useState(false);
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null);
  const [isStarting, setIsStarting] = useState(false);

  const [formData, setFormData] = useState({
    firstName: "",
    lastName: "",
    dob: "",
    nationality: "",
  });
  const [formErrors, setFormErrors] = useState<Record<string, string>>({});
  const [nationalityOpen, setNationalityOpen] = useState(false);
  const [nationalitySearch, setNationalitySearch] = useState("");
  const nationalityRef = useRef<HTMLDivElement>(null);

  // World database state
  const [worldDatabases, setWorldDatabases] = useState<WorldDatabaseInfo[]>([]);
  const [selectedWorldId, setSelectedWorldId] = useState<string>("random");
  const [isLoadingWorlds, setIsLoadingWorlds] = useState(false);

  const NATIONALITIES = [
    "Afghan", "Albanian", "Algerian", "American", "Andorran", "Angolan", "Argentine",
    "Armenian", "Australian", "Austrian", "Azerbaijani", "Bahamian", "Bahraini",
    "Bangladeshi", "Barbadian", "Belarusian", "Belgian", "Belizean", "Beninese",
    "Bhutanese", "Bolivian", "Bosnian", "Brazilian", "British", "Bruneian",
    "Bulgarian", "Burkinabe", "Burmese", "Burundian", "Cambodian", "Cameroonian",
    "Canadian", "Cape Verdean", "Central African", "Chadian", "Chilean", "Chinese",
    "Colombian", "Comorian", "Congolese", "Costa Rican", "Croatian", "Cuban",
    "Cypriot", "Czech", "Danish", "Djiboutian", "Dominican", "Dutch", "Ecuadorian",
    "Egyptian", "Emirati", "English", "Equatoguinean", "Eritrean", "Estonian",
    "Ethiopian", "Fijian", "Filipino", "Finnish", "French", "Gabonese", "Gambian",
    "Georgian", "German", "Ghanaian", "Greek", "Grenadian", "Guatemalan", "Guinean",
    "Guyanese", "Haitian", "Honduran", "Hungarian", "Icelandic", "Indian",
    "Indonesian", "Iranian", "Iraqi", "Irish", "Israeli", "Italian", "Ivorian",
    "Jamaican", "Japanese", "Jordanian", "Kazakh", "Kenyan", "Kosovar", "Kuwaiti",
    "Kyrgyz", "Laotian", "Latvian", "Lebanese", "Liberian", "Libyan", "Lithuanian",
    "Luxembourgish", "Macedonian", "Malagasy", "Malawian", "Malaysian", "Maldivian",
    "Malian", "Maltese", "Mauritanian", "Mauritian", "Mexican", "Moldovan",
    "Mongolian", "Montenegrin", "Moroccan", "Mozambican", "Namibian", "Nepalese",
    "New Zealander", "Nicaraguan", "Nigerian", "Nigerien", "North Korean", "Northern Irish",
    "Norwegian", "Omani", "Pakistani", "Palestinian", "Panamanian", "Paraguayan",
    "Peruvian", "Polish", "Portuguese", "Qatari", "Romanian", "Russian", "Rwandan",
    "Saudi", "Scottish", "Senegalese", "Serbian", "Sierra Leonean", "Singaporean",
    "Slovak", "Slovenian", "Somali", "South African", "South Korean", "Spanish",
    "Sri Lankan", "Sudanese", "Surinamese", "Swedish", "Swiss", "Syrian",
    "Taiwanese", "Tajik", "Tanzanian", "Thai", "Togolese", "Trinidadian",
    "Tunisian", "Turkish", "Turkmen", "Ugandan", "Ukrainian", "Uruguayan",
    "Uzbek", "Venezuelan", "Vietnamese", "Welsh", "Yemeni", "Zambian", "Zimbabwean",
  ];

  const filteredNationalities = NATIONALITIES.filter(n =>
    n.toLowerCase().includes(nationalitySearch.toLowerCase())
  );

  const validateForm = (): boolean => {
    const errors: Record<string, string> = {};
    if (!formData.firstName.trim()) errors.firstName = t('validation.required', { field: t('createManager.firstName') });
    if (!formData.lastName.trim()) errors.lastName = t('validation.required', { field: t('createManager.lastName') });
    if (!formData.dob) {
      errors.dob = t('validation.required', { field: t('createManager.dob') });
    } else {
      const birthDate = new Date(formData.dob);
      const today = new Date();
      const age = Math.floor((today.getTime() - birthDate.getTime()) / (365.25 * 24 * 60 * 60 * 1000));
      if (isNaN(age)) {
        errors.dob = t('validation.invalidDate');
      } else if (age < 30) {
        errors.dob = t('validation.minAge');
      } else if (age > 99) {
        errors.dob = t('validation.invalidDob');
      }
    }
    if (!formData.nationality) errors.nationality = t('validation.required', { field: t('createManager.nationality') });
    setFormErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const handleGoToWorldSelect = (e: React.FormEvent) => {
    e.preventDefault();
    if (!validateForm()) return;
    setMenuState("world");
    loadWorldDatabases();
  };

  // Close nationality dropdown on outside click
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (nationalityRef.current && !nationalityRef.current.contains(e.target as Node)) {
        setNationalityOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

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
        name: t('worldSelect.randomWorld'),
        description: t('worldSelect.randomDescription'),
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
          description: parsed.description || t('menu.importedDescription'),
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
                  <span className="font-heading font-bold text-lg uppercase tracking-wide">{t("menu.newGame")}</span>
                </div>
                <ChevronRight className="w-5 h-5 opacity-70 group-hover:opacity-100 group-hover:translate-x-0.5 transition-all" />
              </button>
              
              <button 
                onClick={handleOpenLoadMenu}
                className="group flex items-center justify-between w-full p-4 bg-white dark:bg-navy-700 hover:bg-gray-50 dark:hover:bg-navy-600 text-gray-800 dark:text-gray-200 rounded-xl transition-all duration-300 border border-gray-200 dark:border-navy-600 hover:border-accent-400 dark:hover:border-accent-400 shadow-sm"
              >
                <div className="flex items-center gap-3">
                  <FolderOpen className="w-6 h-6 text-accent-500 dark:text-accent-400" />
                  <span className="font-heading font-bold text-lg uppercase tracking-wide">{t("menu.loadGame")}</span>
                </div>
                <ChevronRight className="w-5 h-5 opacity-0 group-hover:opacity-70 group-hover:translate-x-0.5 transition-all text-accent-500" />
              </button>
              
              <button 
                onClick={() => navigate("/settings", { state: { from: "/" } })}
                className="group flex items-center justify-between w-full p-4 bg-white dark:bg-navy-700 hover:bg-gray-50 dark:hover:bg-navy-600 text-gray-800 dark:text-gray-200 rounded-xl transition-all duration-300 border border-gray-200 dark:border-navy-600 hover:border-gray-300 dark:hover:border-navy-600 shadow-sm"
              >
                <div className="flex items-center gap-3">
                  <Settings className="w-6 h-6 text-gray-400 dark:text-gray-500" />
                  <span className="font-heading font-bold text-lg uppercase tracking-wide">{t("menu.settings")}</span>
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
                  {t("createManager.title")}
                </h2>
                <button 
                  type="button" 
                  onClick={() => { setMenuState("main"); setFormErrors({}); }}
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
              
              {/* Name fields with labels */}
              <div className="flex gap-3">
                <div className="flex-1">
                  <label className="block text-xs font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-1.5">
                    {t("createManager.firstName")}
                  </label>
                  <input
                    className={`w-full bg-gray-50 dark:bg-navy-900 border text-gray-900 dark:text-white rounded-lg p-3 outline-none focus:ring-2 transition-all placeholder:text-gray-400 dark:placeholder:text-gray-500 ${
                      formErrors.firstName
                        ? "border-red-400 dark:border-red-500 focus:border-red-500 focus:ring-red-500/20"
                        : "border-gray-300 dark:border-navy-600 focus:border-primary-500 focus:ring-primary-500/20"
                    }`}
                    placeholder={t('createManager.placeholderFirst')}
                    value={formData.firstName}
                    onChange={e => { setFormData({...formData, firstName: e.target.value}); setFormErrors(prev => ({...prev, firstName: ""})); }}
                  />
                  {formErrors.firstName && (
                    <p className="flex items-center gap-1 text-xs text-red-500 mt-1"><AlertCircle className="w-3 h-3" />{formErrors.firstName}</p>
                  )}
                </div>
                <div className="flex-1">
                  <label className="block text-xs font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-1.5">
                    {t("createManager.lastName")}
                  </label>
                  <input
                    className={`w-full bg-gray-50 dark:bg-navy-900 border text-gray-900 dark:text-white rounded-lg p-3 outline-none focus:ring-2 transition-all placeholder:text-gray-400 dark:placeholder:text-gray-500 ${
                      formErrors.lastName
                        ? "border-red-400 dark:border-red-500 focus:border-red-500 focus:ring-red-500/20"
                        : "border-gray-300 dark:border-navy-600 focus:border-primary-500 focus:ring-primary-500/20"
                    }`}
                    placeholder={t('createManager.placeholderLast')}
                    value={formData.lastName}
                    onChange={e => { setFormData({...formData, lastName: e.target.value}); setFormErrors(prev => ({...prev, lastName: ""})); }}
                  />
                  {formErrors.lastName && (
                    <p className="flex items-center gap-1 text-xs text-red-500 mt-1"><AlertCircle className="w-3 h-3" />{formErrors.lastName}</p>
                  )}
                </div>
              </div>
              
              {/* Date of Birth with label */}
              <div>
                <label className="block text-xs font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-1.5">
                  {t("createManager.dob")}
                </label>
                <input
                  type="date"
                  className={`w-full bg-gray-50 dark:bg-navy-900 border text-gray-900 dark:text-white rounded-lg p-3 outline-none focus:ring-2 transition-all ${
                    formErrors.dob
                      ? "border-red-400 dark:border-red-500 focus:border-red-500 focus:ring-red-500/20"
                      : "border-gray-300 dark:border-navy-600 focus:border-primary-500 focus:ring-primary-500/20"
                  }`}
                  style={{ colorScheme: isDark ? 'dark' : 'light' }}
                  max={(() => { const d = new Date(); d.setFullYear(d.getFullYear() - 30); return d.toISOString().split('T')[0]; })()}
                  min="1930-01-01"
                  value={formData.dob}
                  onChange={e => { setFormData({...formData, dob: e.target.value}); setFormErrors(prev => ({...prev, dob: ""})); }}
                />
                {formErrors.dob ? (
                  <p className="flex items-center gap-1 text-xs text-red-500 mt-1"><AlertCircle className="w-3 h-3" />{formErrors.dob}</p>
                ) : (
                  <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">{t("createManager.minAge")}</p>
                )}
              </div>
              
              {/* Nationality combobox */}
              <div ref={nationalityRef}>
                <label className="block text-xs font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-1.5">
                  {t("createManager.nationality")}
                </label>
                <div className="relative">
                  <button
                    type="button"
                    onClick={() => { setNationalityOpen(!nationalityOpen); setNationalitySearch(""); }}
                    className={`w-full flex items-center justify-between bg-gray-50 dark:bg-navy-900 border text-left rounded-lg p-3 outline-none transition-all ${
                      formErrors.nationality
                        ? "border-red-400 dark:border-red-500"
                        : nationalityOpen
                          ? "border-primary-500 ring-2 ring-primary-500/20"
                          : "border-gray-300 dark:border-navy-600"
                    }`}
                  >
                    <span className={formData.nationality ? "text-gray-900 dark:text-white" : "text-gray-400 dark:text-gray-500"}>
                      {formData.nationality || t("createManager.selectNationality")}
                    </span>
                    <ChevronDown className={`w-4 h-4 text-gray-400 transition-transform ${nationalityOpen ? "rotate-180" : ""}`} />
                  </button>

                  {nationalityOpen && (
                    <div className="absolute z-50 top-full mt-1 left-0 right-0 bg-white dark:bg-navy-700 rounded-lg shadow-xl border border-gray-200 dark:border-navy-600 overflow-hidden">
                      <div className="p-2 border-b border-gray-100 dark:border-navy-600">
                        <input
                          type="text"
                          autoFocus
                          placeholder={t('createManager.searchNationalities')}
                          value={nationalitySearch}
                          onChange={e => setNationalitySearch(e.target.value)}
                          className="w-full bg-gray-50 dark:bg-navy-800 border border-gray-200 dark:border-navy-600 text-gray-900 dark:text-white rounded-md px-3 py-2 text-sm outline-none focus:border-primary-500 transition-colors placeholder:text-gray-400 dark:placeholder:text-gray-500"
                        />
                      </div>
                      <div className="max-h-48 overflow-y-auto">
                        {filteredNationalities.length === 0 ? (
                          <p className="px-3 py-2 text-xs text-gray-400 dark:text-gray-500">{t('menu.noResults')}</p>
                        ) : (
                          filteredNationalities.map(nat => (
                            <button
                              key={nat}
                              type="button"
                              onClick={() => {
                                setFormData({...formData, nationality: nat});
                                setNationalityOpen(false);
                                setNationalitySearch("");
                                setFormErrors(prev => ({...prev, nationality: ""}));
                              }}
                              className={`w-full text-left px-3 py-2 text-sm flex items-center justify-between transition-colors ${
                                formData.nationality === nat
                                  ? "bg-primary-50 dark:bg-primary-500/10 text-primary-600 dark:text-primary-400"
                                  : "text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-navy-600"
                              }`}
                            >
                              <span>{nat}</span>
                              {formData.nationality === nat && <Check className="w-4 h-4 text-primary-500" />}
                            </button>
                          ))
                        )}
                      </div>
                    </div>
                  )}
                </div>
                {formErrors.nationality && (
                  <p className="flex items-center gap-1 text-xs text-red-500 mt-1"><AlertCircle className="w-3 h-3" />{formErrors.nationality}</p>
                )}
              </div>
              
              <Button type="submit" variant="primary" size="lg" className="mt-2 w-full" iconRight={<ChevronRight />}>
                {t("createManager.chooseWorld")}
              </Button>
            </form>
          )}

          {/* Step 2: World Database Selection */}
          {menuState === "world" && (
            <WorldSelect
              worldDatabases={worldDatabases}
              selectedWorldId={selectedWorldId}
              isLoadingWorlds={isLoadingWorlds}
              isStarting={isStarting}
              onSelectWorld={setSelectedWorldId}
              onImportFile={handleImportFile}
              onStart={handleStartGame}
              onBack={() => setMenuState("create")}
              onClose={() => setMenuState("main")}
            />
          )}

          {/* Load Game List */}
          {menuState === "load" && (
            <SavesList
              saves={saves}
              isLoading={isLoadingSaves}
              confirmDeleteId={confirmDeleteId}
              onLoad={handleLoadGame}
              onDelete={handleDeleteSave}
              onConfirmDelete={setConfirmDeleteId}
              onClose={() => setMenuState("main")}
            />
          )}
        </div>
      </div>
      
      {/* Version */}
      <div className="absolute bottom-4 right-4 text-gray-400 dark:text-gray-600 text-xs font-heading uppercase tracking-widest transition-colors">
        {t("app.version")}
      </div>
    </div>
  );
}
