import { useEffect, useState } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { invoke } from "@tauri-apps/api/core";
import { useTranslation } from "react-i18next";
import { useSettingsStore, AppSettings } from "../store/settingsStore";
import { useTheme } from "../context/ThemeContext";
import { ThemeToggle } from "../components/ui";
import { SUPPORTED_LANGUAGES } from "../i18n";
import {
  ArrowLeft, Monitor, Moon, Sun, Gamepad2, Save,
  Zap, Trash2, Download, Globe,
} from "lucide-react";

const CURRENCY_OPTIONS = [
  { value: "EUR", label: "Euro (€)", symbol: "€" },
  { value: "GBP", label: "Pound (£)", symbol: "£" },
  { value: "USD", label: "Dollar ($)", symbol: "$" },
] as const;

const MATCH_MODE_OPTIONS = [
  { value: "live", label: "Go to the Field", desc: "Full match control" },
  { value: "spectator", label: "Watch as Spectator", desc: "Watch only, no controls" },
  { value: "delegate", label: "Delegate to Assistant", desc: "AI handles everything" },
] as const;

const MATCH_SPEED_OPTIONS = [
  { value: "slow", label: "Slow" },
  { value: "normal", label: "Normal" },
  { value: "fast", label: "Fast" },
] as const;

export default function Settings() {
  const navigate = useNavigate();
  const location = useLocation();
  const { i18n } = useTranslation();
  const { settings, loaded, loadSettings, updateSettings } = useSettingsStore();
  const { theme, toggleTheme } = useTheme();
  const [confirmClear, setConfirmClear] = useState(false);
  const [clearSuccess, setClearSuccess] = useState(false);
  const [exportPath, setExportPath] = useState<string | null>(null);

  // Where to go back to
  const returnTo = (location.state as { from?: string })?.from || "/";

  useEffect(() => {
    if (!loaded) loadSettings();
  }, [loaded, loadSettings]);

  // Sync language with i18n when settings are loaded
  useEffect(() => {
    if (loaded && settings.language && settings.language !== i18n.language) {
      i18n.changeLanguage(settings.language);
    }
  }, [loaded, settings.language, i18n]);

  const handleUpdate = (partial: Partial<AppSettings>) => {
    updateSettings(partial);

    // Sync theme with ThemeContext
    if (partial.theme) {
      const desired = partial.theme === "system"
        ? (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")
        : partial.theme;
      if (desired !== theme) toggleTheme();
    }

    // Sync language with i18n
    if (partial.language) {
      i18n.changeLanguage(partial.language);
    }
  };

  const handleClearSaves = async () => {
    try {
      await invoke("clear_all_saves");
      setClearSuccess(true);
      setConfirmClear(false);
      setTimeout(() => setClearSuccess(false), 3000);
    } catch (err) {
      console.error("Failed to clear saves:", err);
    }
  };

  const handleExportWorld = async () => {
    try {
      // Simple export to app data dir
      const path = await invoke<string>("export_world_database", {
        exportPath: "exported_world.json",
      });
      setExportPath(path);
      setTimeout(() => setExportPath(null), 5000);
    } catch (err) {
      console.error("Failed to export world:", err);
    }
  };

  if (!loaded) {
    return (
      <div className="min-h-screen bg-gray-100 dark:bg-navy-900 flex items-center justify-center transition-colors">
        <div className="w-8 h-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-100 dark:bg-navy-900 transition-colors duration-300">
      {/* Header */}
      <header className="bg-white dark:bg-navy-800 border-b border-gray-200 dark:border-navy-700 shadow-sm">
        <div className="max-w-3xl mx-auto px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <button
              onClick={() => navigate(returnTo)}
              className="p-2 rounded-lg text-gray-400 hover:text-gray-700 dark:hover:text-white hover:bg-gray-100 dark:hover:bg-navy-700 transition-colors"
            >
              <ArrowLeft className="w-5 h-5" />
            </button>
            <h1 className="text-xl font-heading font-bold uppercase tracking-wide text-gray-900 dark:text-white">
              Settings
            </h1>
          </div>
          <ThemeToggle />
        </div>
      </header>

      {/* Content */}
      <div className="max-w-3xl mx-auto px-6 py-8 flex flex-col gap-8">

        {/* ─── Display ─── */}
        <Section title="Display" icon={<Monitor className="w-5 h-5" />}>
          <SettingRow label="Theme" description="Choose how the app looks">
            <SegmentedControl
              options={[
                { value: "light", icon: <Sun className="w-4 h-4" /> },
                { value: "dark", icon: <Moon className="w-4 h-4" /> },
                { value: "system", icon: <Monitor className="w-4 h-4" /> },
              ]}
              value={settings.theme}
              onChange={(v) => handleUpdate({ theme: v as AppSettings["theme"] })}
            />
          </SettingRow>

          <SettingRow label="Language" description="Choose the display language">
            <div className="flex items-center gap-2">
              <Globe className="w-4 h-4 text-gray-400" />
              <select
                value={settings.language}
                onChange={(e) => handleUpdate({ language: e.target.value })}
                className="bg-gray-50 dark:bg-navy-700 border border-gray-300 dark:border-navy-600 text-gray-900 dark:text-white rounded-lg px-3 py-2 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 transition-all"
              >
                {SUPPORTED_LANGUAGES.map((lang) => (
                  <option key={lang.code} value={lang.code}>{lang.label}</option>
                ))}
              </select>
            </div>
          </SettingRow>

          <SettingRow label="Currency" description="How monetary values are displayed">
            <select
              value={settings.currency}
              onChange={(e) => handleUpdate({ currency: e.target.value as AppSettings["currency"] })}
              className="bg-gray-50 dark:bg-navy-700 border border-gray-300 dark:border-navy-600 text-gray-900 dark:text-white rounded-lg px-3 py-2 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 transition-all"
            >
              {CURRENCY_OPTIONS.map((c) => (
                <option key={c.value} value={c.value}>{c.symbol} {c.label}</option>
              ))}
            </select>
          </SettingRow>
        </Section>

        {/* ─── Gameplay ─── */}
        <Section title="Gameplay" icon={<Gamepad2 className="w-5 h-5" />}>
          <SettingRow label="Default Match Mode" description="How matches start when you press Continue">
            <select
              value={settings.default_match_mode}
              onChange={(e) => handleUpdate({ default_match_mode: e.target.value as AppSettings["default_match_mode"] })}
              className="bg-gray-50 dark:bg-navy-700 border border-gray-300 dark:border-navy-600 text-gray-900 dark:text-white rounded-lg px-3 py-2 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 transition-all"
            >
              {MATCH_MODE_OPTIONS.map((m) => (
                <option key={m.value} value={m.value}>{m.label}</option>
              ))}
            </select>
          </SettingRow>

          <SettingRow label="Match Speed" description="Default simulation speed for live matches">
            <SegmentedControl
              options={MATCH_SPEED_OPTIONS.map((s) => ({ value: s.value, label: s.label }))}
              value={settings.match_speed}
              onChange={(v) => handleUpdate({ match_speed: v as AppSettings["match_speed"] })}
            />
          </SettingRow>

          <SettingRow label="Match Commentary" description="Show event commentary during live matches">
            <Toggle
              checked={settings.show_match_commentary}
              onChange={(v) => handleUpdate({ show_match_commentary: v })}
            />
          </SettingRow>

          <SettingRow label="Confirm Before Advancing" description="Ask for confirmation before advancing a day">
            <Toggle
              checked={settings.confirm_advance}
              onChange={(v) => handleUpdate({ confirm_advance: v })}
            />
          </SettingRow>
        </Section>

        {/* ─── Saves & Data ─── */}
        <Section title="Saves & Data" icon={<Save className="w-5 h-5" />}>
          <SettingRow label="Auto-Save" description="Automatically save your game after each day">
            <Toggle
              checked={settings.auto_save}
              onChange={(v) => handleUpdate({ auto_save: v })}
            />
          </SettingRow>

          <SettingRow label="Export World Database" description="Save the current world data as a shareable JSON file">
            <button
              onClick={handleExportWorld}
              className="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-500/10 text-primary-600 dark:text-primary-400 hover:bg-primary-500/20 text-sm font-heading font-bold uppercase tracking-wider transition-colors"
            >
              <Download className="w-4 h-4" />
              Export
            </button>
          </SettingRow>
          {exportPath && (
            <p className="text-xs text-primary-500 -mt-2 ml-1">Exported to: {exportPath}</p>
          )}

          <div className="border-t border-gray-200 dark:border-navy-600 pt-4 mt-2">
            <SettingRow
              label="Clear All Saves"
              description="Permanently delete all saved games"
              danger
            >
              {confirmClear ? (
                <div className="flex items-center gap-2">
                  <button
                    onClick={handleClearSaves}
                    className="px-4 py-2 rounded-lg bg-red-500 text-white text-sm font-heading font-bold uppercase tracking-wider hover:bg-red-600 transition-colors"
                  >
                    Confirm
                  </button>
                  <button
                    onClick={() => setConfirmClear(false)}
                    className="px-4 py-2 rounded-lg bg-gray-200 dark:bg-navy-600 text-gray-700 dark:text-gray-300 text-sm font-heading font-bold uppercase tracking-wider hover:bg-gray-300 dark:hover:bg-navy-500 transition-colors"
                  >
                    Cancel
                  </button>
                </div>
              ) : clearSuccess ? (
                <span className="text-sm text-primary-500 font-heading font-bold uppercase tracking-wider">Saves cleared!</span>
              ) : (
                <button
                  onClick={() => setConfirmClear(true)}
                  className="flex items-center gap-2 px-4 py-2 rounded-lg bg-red-500/10 text-red-500 hover:bg-red-500/20 text-sm font-heading font-bold uppercase tracking-wider transition-colors"
                >
                  <Trash2 className="w-4 h-4" />
                  Clear
                </button>
              )}
            </SettingRow>
          </div>
        </Section>

        {/* ─── About ─── */}
        <Section title="About" icon={<Zap className="w-5 h-5" />}>
          <div className="flex justify-between items-center">
            <div>
              <p className="text-sm font-medium text-gray-800 dark:text-gray-200">OpenFoot Manager</p>
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">v0.1.0 Alpha</p>
            </div>
            <span className="text-[10px] font-heading uppercase tracking-widest text-gray-400 dark:text-gray-600">
              Sturdy Robot
            </span>
          </div>
        </Section>
      </div>
    </div>
  );
}

// ── Reusable sub-components ──

function Section({ title, icon, children }: { title: string; icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="bg-white dark:bg-navy-800 rounded-2xl border border-gray-200 dark:border-navy-700 shadow-sm overflow-hidden">
      <div className="flex items-center gap-2 px-6 py-4 border-b border-gray-100 dark:border-navy-700">
        <span className="text-primary-500">{icon}</span>
        <h2 className="text-sm font-heading font-bold uppercase tracking-wider text-gray-800 dark:text-gray-200">
          {title}
        </h2>
      </div>
      <div className="px-6 py-4 flex flex-col gap-5">{children}</div>
    </div>
  );
}

function SettingRow({ label, description, danger, children }: {
  label: string;
  description: string;
  danger?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-4">
      <div className="flex-1 min-w-0">
        <p className={`text-sm font-medium ${danger ? "text-red-500" : "text-gray-800 dark:text-gray-200"}`}>{label}</p>
        <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">{description}</p>
      </div>
      <div className="flex-shrink-0">{children}</div>
    </div>
  );
}

function Toggle({ checked, onChange }: { checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      onClick={() => onChange(!checked)}
      className={`relative w-11 h-6 rounded-full transition-colors duration-200 ${
        checked ? "bg-primary-500" : "bg-gray-300 dark:bg-navy-600"
      }`}
    >
      <div
        className={`absolute top-0.5 w-5 h-5 bg-white rounded-full shadow-sm transition-transform duration-200 ${
          checked ? "translate-x-[22px]" : "translate-x-0.5"
        }`}
      />
    </button>
  );
}

function SegmentedControl({ options, value, onChange }: {
  options: Array<{ value: string; label?: string; icon?: React.ReactNode }>;
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="flex rounded-lg bg-gray-100 dark:bg-navy-700 p-0.5 border border-gray-200 dark:border-navy-600">
      {options.map((opt) => (
        <button
          key={opt.value}
          onClick={() => onChange(opt.value)}
          className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-heading font-bold uppercase tracking-wider transition-all ${
            value === opt.value
              ? "bg-white dark:bg-navy-500 text-primary-600 dark:text-primary-400 shadow-sm"
              : "text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300"
          }`}
        >
          {opt.icon}
          {opt.label || opt.value}
        </button>
      ))}
    </div>
  );
}
