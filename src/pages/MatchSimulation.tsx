import { useEffect, useState, useCallback } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { invoke } from "@tauri-apps/api/core";
import { useTranslation } from "react-i18next";
import { useGameStore, GameStateData } from "../store/gameStore";
import { MatchSnapshot, MatchEvent, MatchDayStage } from "../components/match/types";
import PreMatchSetup from "../components/match/PreMatchSetup";
import MatchLive from "../components/match/MatchLive";
import HalfTimeBreak from "../components/match/HalfTimeBreak";
import PostMatchScreen from "../components/match/PostMatchScreen";
import PressConference from "../components/match/PressConference";

// ---------------------------------------------------------------------------
// Multi-stage Match Day Orchestrator
// ---------------------------------------------------------------------------

export default function MatchSimulation() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const location = useLocation();
  const matchMode = (location.state as { mode?: string })?.mode || "live";
  const { gameState, setGameState } = useGameStore();
  const [snapshot, setSnapshot] = useState<MatchSnapshot | null>(null);
  const [stage, setStage] = useState<MatchDayStage>("prematch");
  const [importantEvents, setImportantEvents] = useState<MatchEvent[]>([]);
  const [userSide, setUserSide] = useState<"Home" | "Away" | null>(null);
  const [isSpectator, setIsSpectator] = useState(matchMode === "spectator");

  // Determine user side from game state
  useEffect(() => {
    if (!gameState || !snapshot) return;
    const utid = gameState.manager.team_id;
    if (!utid) {
      setIsSpectator(true);
      return;
    }
    if (snapshot.home_team.id === utid) setUserSide("Home");
    else if (snapshot.away_team.id === utid) setUserSide("Away");
    else setIsSpectator(true);

    // If mode is spectator, force spectator regardless of team
    if (matchMode === "spectator") setIsSpectator(true);
  }, [gameState, snapshot?.home_team.id, snapshot?.away_team.id, matchMode]);

  // Fetch initial snapshot
  useEffect(() => {
    const fetchSnapshot = async () => {
      try {
        const snap = await invoke<MatchSnapshot>("get_match_snapshot");
        setSnapshot(snap);
      } catch (err) {
        console.error("Failed to get match snapshot:", err);
        navigate("/dashboard");
      }
    };
    fetchSnapshot();
  }, [navigate]);

  // Skip pre-match for spectators
  useEffect(() => {
    if (isSpectator && stage === "prematch") {
      setStage("first_half");
    }
  }, [isSpectator, stage]);

  // Callbacks for stage transitions
  const handleStartMatch = useCallback(() => {
    setStage("first_half");
  }, []);

  const handleHalfTime = useCallback(() => {
    setStage("halftime");
  }, []);

  const handleResumeFromHalfTime = useCallback(() => {
    setStage("second_half");
  }, []);

  const handleFullTime = useCallback(() => {
    setStage("postmatch");
  }, []);

  const handlePressConference = useCallback(() => {
    setStage("press");
  }, []);

  const handleFinishMatch = useCallback(async () => {
    try {
      const updatedGame = await invoke<GameStateData>("finish_live_match");
      setGameState(updatedGame);
      navigate("/dashboard");
    } catch (err) {
      console.error("Failed to finish match:", err);
    }
  }, [setGameState, navigate]);

  const handleSnapshotUpdate = useCallback((snap: MatchSnapshot) => {
    setSnapshot(snap);
  }, []);

  const handleImportantEvent = useCallback((evt: MatchEvent) => {
    setImportantEvents(prev => [...prev, evt]);
  }, []);

  // Loading state
  if (!snapshot || !gameState) {
    return (
      <div className="min-h-screen bg-navy-900 flex items-center justify-center">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 border-4 border-primary-500 border-t-transparent rounded-full animate-spin" />
          <span className="text-gray-400 font-heading uppercase tracking-wider text-sm">{t('dashboard.loading')}</span>
        </div>
      </div>
    );
  }

  // Render the current stage
  switch (stage) {
    case "prematch":
      return (
        <PreMatchSetup
          snapshot={snapshot}
          gameState={gameState}
          userSide={userSide || "Home"}
          onStart={handleStartMatch}
          onUpdateSnapshot={handleSnapshotUpdate}
        />
      );

    case "first_half":
    case "second_half":
      return (
        <MatchLive
          key={stage}
          snapshot={snapshot}
          gameState={gameState}
          userSide={userSide}
          isSpectator={isSpectator}
          importantEvents={importantEvents}
          onSnapshotUpdate={handleSnapshotUpdate}
          onImportantEvent={handleImportantEvent}
          onHalfTime={handleHalfTime}
          onFullTime={handleFullTime}
        />
      );

    case "halftime":
      return (
        <HalfTimeBreak
          snapshot={snapshot}
          gameState={gameState}
          userSide={userSide || "Home"}
          isSpectator={isSpectator}
          importantEvents={importantEvents}
          onResume={handleResumeFromHalfTime}
          onUpdateSnapshot={handleSnapshotUpdate}
        />
      );

    case "postmatch":
      return (
        <PostMatchScreen
          snapshot={snapshot}
          gameState={gameState}
          userSide={userSide}
          isSpectator={isSpectator}
          importantEvents={importantEvents}
          onPressConference={handlePressConference}
          onFinish={handleFinishMatch}
        />
      );

    case "press":
      return (
        <PressConference
          snapshot={snapshot}
          gameState={gameState}
          userSide={userSide || "Home"}
          onFinish={handleFinishMatch}
          onGameUpdate={setGameState}
        />
      );

    default:
      return null;
  }
}
