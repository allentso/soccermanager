import { useEffect } from "react";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import MainMenu from "./pages/MainMenu";
import TeamSelection from "./pages/TeamSelection";
import Dashboard from "./pages/Dashboard";
import MatchSimulation from "./pages/MatchSimulation";
import Settings from "./pages/Settings";
import { useSettingsStore } from "./store/settingsStore";
import i18n from "./i18n";
import "./App.css";

const SCALE_MAP: Record<string, string> = {
  small: "14px",
  normal: "16px",
  large: "18px",
  xlarge: "20px",
};

function App() {
  const { settings, loaded, loadSettings } = useSettingsStore();

  useEffect(() => {
    if (!loaded) loadSettings();
  }, [loaded, loadSettings]);

  useEffect(() => {
    const size = SCALE_MAP[settings.ui_scale] || "16px";
    document.documentElement.style.fontSize = size;
  }, [settings.ui_scale]);

  useEffect(() => {
    document.documentElement.classList.toggle("high-contrast", settings.high_contrast);
  }, [settings.high_contrast]);

  // Apply saved language from settings once loaded (overrides OS detection)
  useEffect(() => {
    if (loaded && settings.language && settings.language !== i18n.language) {
      i18n.changeLanguage(settings.language);
    }
  }, [loaded, settings.language]);

  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<MainMenu />} />
        <Route path="/select-team" element={<TeamSelection />} />
        <Route path="/dashboard" element={<Dashboard />} />
        <Route path="/match" element={<MatchSimulation />} />
        <Route path="/settings" element={<Settings />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;


