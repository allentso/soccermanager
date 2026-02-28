import { BrowserRouter, Routes, Route } from "react-router-dom";
import MainMenu from "./pages/MainMenu";
import TeamSelection from "./pages/TeamSelection";
import Dashboard from "./pages/Dashboard";
import MatchSimulation from "./pages/MatchSimulation";
import Settings from "./pages/Settings";
import "./App.css";

function App() {
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


