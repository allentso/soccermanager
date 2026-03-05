import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { invoke } from "@tauri-apps/api/core";
import { GameStateData } from "../store/gameStore";

export interface BlockerData {
  id: string;
  severity: string;
  text: string;
  tab: string;
}

export interface BlockerModal {
  blockers: BlockerData[];
  pendingAction?: () => void;
}

export type MatchModeType = "live" | "spectator" | "delegate";

export function useAdvanceTime(
  setGameState: (state: GameStateData) => void,
  hasMatchToday: boolean,
  defaultMatchMode: MatchModeType | undefined,
  settingsLoaded: boolean,
) {
  const navigate = useNavigate();
  const [isAdvancing, setIsAdvancing] = useState(false);
  const [showContinueMenu, setShowContinueMenu] = useState(false);
  const [showMatchConfirm, setShowMatchConfirm] = useState(false);
  const [matchMode, setMatchMode] = useState<MatchModeType>("live");
  const [blockerModal, setBlockerModal] = useState<BlockerModal | null>(null);

  // Sync matchMode with settings when loaded
  useEffect(() => {
    if (settingsLoaded && defaultMatchMode) {
      setMatchMode(defaultMatchMode);
    }
  }, [settingsLoaded, defaultMatchMode]);

  const doAdvance = async (effectiveMode: string) => {
    setIsAdvancing(true);
    setShowContinueMenu(false);
    setShowMatchConfirm(false);
    setBlockerModal(null);
    try {
      const result = await invoke<{ action: string; game?: GameStateData; snapshot?: unknown; fixture_index?: number; mode?: string }>("advance_time_with_mode", { mode: effectiveMode });
      if (result.action === "live_match") {
        navigate("/match", { state: { mode: result.mode || effectiveMode } });
      } else if (result.action === "advanced" && result.game) {
        setGameState(result.game as GameStateData);
      }
    } catch (err) {
      console.error("Failed to advance time:", err);
    } finally {
      setIsAdvancing(false);
    }
  };

  const handleContinue = async (mode?: string) => {
    const effectiveMode = mode || matchMode;
    // If there's a match today, show confirmation modal first
    if (hasMatchToday && !showMatchConfirm) {
      if (mode) setMatchMode(mode as MatchModeType);
      setShowContinueMenu(false);
      setShowMatchConfirm(true);
      return;
    }
    if (isAdvancing) return;
    // Check for blocking actions before advancing
    try {
      const blockers = await invoke<BlockerData[]>("check_blocking_actions");
      if (blockers.length > 0) {
        setBlockerModal({ blockers, pendingAction: () => doAdvance(effectiveMode) });
        return;
      }
    } catch {}
    doAdvance(effectiveMode);
  };

  const handleConfirmMatch = () => {
    doAdvance(matchMode);
  };

  const handleSkipToMatchDay = async () => {
    if (isAdvancing) return;
    // Check blockers before starting skip
    try {
      const blockers = await invoke<BlockerData[]>("check_blocking_actions");
      if (blockers.length > 0) {
        setBlockerModal({ blockers, pendingAction: doSkipToMatchDay });
        return;
      }
    } catch {}
    doSkipToMatchDay();
  };

  const doSkipToMatchDay = async () => {
    setIsAdvancing(true);
    setShowContinueMenu(false);
    setBlockerModal(null);
    try {
      const result = await invoke<{ action: string; game?: GameStateData; blockers?: BlockerData[]; days_skipped?: number }>("skip_to_match_day");
      if (result.game) setGameState(result.game as GameStateData);
      if (result.action === "blocked" && result.blockers && result.blockers.length > 0) {
        setBlockerModal({ blockers: result.blockers });
      }
    } catch (err) {
      console.error("Failed to skip to match day:", err);
    } finally {
      setIsAdvancing(false);
    }
  };

  return {
    isAdvancing,
    showContinueMenu, setShowContinueMenu,
    showMatchConfirm, setShowMatchConfirm,
    matchMode, setMatchMode,
    blockerModal, setBlockerModal,
    handleContinue,
    handleConfirmMatch,
    handleSkipToMatchDay,
  };
}
