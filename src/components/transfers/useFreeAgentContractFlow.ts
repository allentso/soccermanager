import { useEffect, useState } from "react";

import {
  getRenewalStatusClassName,
  getRenewalStatusMessage,
  shouldDisableRenewalSubmit,
  type RenewalStatus,
} from "../playerProfile/PlayerProfile.renewal";
import type { GameStateData, PlayerData, TeamData } from "../../store/gameStore";
import {
  offerFreeAgentContract,
  previewFreeAgentContractImpact,
  type FreeAgentContractProjection,
  type FreeAgentContractResponseData,
} from "../../services/freeAgentService";

interface UseFreeAgentContractFlowArgs {
  gameState: GameStateData;
  onGameUpdate?: (game: GameStateData) => void;
}

interface UseFreeAgentContractFlowResult {
  freeAgentTarget: PlayerData | null;
  contractWage: string;
  setContractWage: (value: string) => void;
  contractLength: string;
  setContractLength: (value: string) => void;
  contractStatus: RenewalStatus;
  contractError: string | null;
  contractFeedback: FreeAgentContractResponseData["feedback"];
  contractProjection: FreeAgentContractProjection | null;
  contractSubmitting: boolean;
  contractSubmitDisabled: boolean;
  contractStatusMessage: (t: TranslateFn) => string | null;
  contractStatusClassName: string;
  myTeam: TeamData | null;
  openFreeAgentContract: (player: PlayerData) => void;
  closeFreeAgentContract: () => void;
  submitFreeAgentContract: () => Promise<void>;
}

type TranslateFn = (
  key: string,
  options?: Record<string, string | number>,
) => string;

function defaultContractYears(dateOfBirth: string, asOfDate: string): string {
  const birthDate = new Date(dateOfBirth);
  const today = new Date(asOfDate);
  let age = today.getUTCFullYear() - birthDate.getUTCFullYear();
  const birthMonth = birthDate.getUTCMonth();
  const birthDay = birthDate.getUTCDate();
  if (
    today.getUTCMonth() < birthMonth ||
    (today.getUTCMonth() === birthMonth && today.getUTCDate() < birthDay)
  ) {
    age -= 1;
  }

  if (age <= 28) return "3";
  if (age <= 32) return "2";
  return "1";
}

function defaultContractWage(player: PlayerData): string {
  const baseline = player.wage > 0 ? player.wage : Math.max(Math.round(player.market_value / 200), 500);
  return String(Math.ceil(baseline / 1000) * 1000);
}

export function useFreeAgentContractFlow({
  gameState,
  onGameUpdate,
}: UseFreeAgentContractFlowArgs): UseFreeAgentContractFlowResult {
  const myTeam = gameState.teams.find(
    (team) => team.id === gameState.manager.team_id,
  ) ?? null;
  const [freeAgentTarget, setFreeAgentTarget] = useState<PlayerData | null>(null);
  const [contractWage, setContractWage] = useState("");
  const [contractLength, setContractLength] = useState("");
  const [contractStatus, setContractStatus] = useState<RenewalStatus>("idle");
  const [contractError, setContractError] = useState<string | null>(null);
  const [contractFeedback, setContractFeedback] =
    useState<FreeAgentContractResponseData["feedback"]>(null);
  const [contractProjection, setContractProjection] =
    useState<FreeAgentContractProjection | null>(null);
  const [contractSubmitting, setContractSubmitting] = useState(false);
  const [contractSessionStatus, setContractSessionStatus] =
    useState<FreeAgentContractResponseData["session_status"]>("idle");
  const [contractSuggestedWage, setContractSuggestedWage] = useState<number | null>(null);
  const [contractSuggestedYears, setContractSuggestedYears] = useState<number | null>(null);
  const [contractIsTerminal, setContractIsTerminal] = useState(false);

  const offeredWage = Number(contractWage);
  const offeredYears = Number(contractLength);
  const isContractWageValid = Number.isFinite(offeredWage) && offeredWage > 0;
  const isContractLengthValid = Number.isInteger(offeredYears) && offeredYears > 0;
  const contractViolatesSoftCap =
    isContractWageValid &&
    contractProjection !== null &&
    !contractProjection.policy_allows;

  useEffect(() => {
    if (!freeAgentTarget || !isContractWageValid) {
      setContractProjection(null);
      return;
    }

    let cancelled = false;

    const loadProjection = async (): Promise<void> => {
      try {
        const result = await previewFreeAgentContractImpact(
          freeAgentTarget.id,
          offeredWage,
        );

        if (!cancelled) {
          setContractProjection(result.projection ?? null);
        }
      } catch {
        if (!cancelled) {
          setContractProjection(null);
        }
      }
    };

    void loadProjection();

    return () => {
      cancelled = true;
    };
  }, [freeAgentTarget, isContractWageValid, offeredWage]);

  const openFreeAgentContract = (player: PlayerData): void => {
    setFreeAgentTarget(player);
    setContractWage(defaultContractWage(player));
    setContractLength(defaultContractYears(player.date_of_birth, gameState.clock.current_date));
    setContractStatus("idle");
    setContractError(null);
    setContractFeedback(null);
    setContractProjection(null);
    setContractSessionStatus("idle");
    setContractSuggestedWage(null);
    setContractSuggestedYears(null);
    setContractIsTerminal(false);
  };

  const closeFreeAgentContract = (): void => {
    if (contractSubmitting) {
      return;
    }

    setFreeAgentTarget(null);
    setContractWage("");
    setContractLength("");
    setContractStatus("idle");
    setContractError(null);
    setContractFeedback(null);
    setContractProjection(null);
    setContractSessionStatus("idle");
    setContractSuggestedWage(null);
    setContractSuggestedYears(null);
    setContractIsTerminal(false);
  };

  const submitFreeAgentContract = async (): Promise<void> => {
    if (!freeAgentTarget || !isContractWageValid || !isContractLengthValid) {
      return;
    }

    setContractSubmitting(true);
    setContractStatus("idle");
    setContractError(null);

    try {
      const result = await offerFreeAgentContract(
        freeAgentTarget.id,
        offeredWage,
        offeredYears,
      );

      onGameUpdate?.(result.game);
      setContractStatus(result.outcome);
      setContractFeedback(result.feedback ?? null);
      setContractSessionStatus(result.session_status);
      setContractSuggestedWage(result.suggested_wage);
      setContractSuggestedYears(result.suggested_years);
      setContractIsTerminal(result.is_terminal);

      if (result.outcome === "counter_offer") {
        if (result.suggested_wage !== null) {
          setContractWage(String(result.suggested_wage));
        }
        if (result.suggested_years !== null) {
          setContractLength(String(result.suggested_years));
        }
      }

      if (result.outcome === "accepted") {
        setTimeout(() => {
          closeFreeAgentContract();
        }, 2000);
      }
    } catch (error) {
      setContractStatus("error");
      setContractError(String(error));
      setContractFeedback(null);
    } finally {
      setContractSubmitting(false);
    }
  };

  return {
    freeAgentTarget,
    contractWage,
    setContractWage,
    contractLength,
    setContractLength,
    contractStatus,
    contractError,
    contractFeedback,
    contractProjection,
    contractSubmitting,
    contractSubmitDisabled: shouldDisableRenewalSubmit({
      renewalSubmitting: contractSubmitting,
      renewalIsTerminal: contractIsTerminal,
      isRenewalWageValid: isContractWageValid,
      isRenewalLengthValid: isContractLengthValid,
      renewalViolatesSoftCap: contractViolatesSoftCap,
    }),
    contractStatusMessage: (t: TranslateFn) =>
      getRenewalStatusMessage(
        {
          renewalSessionStatus: contractSessionStatus,
          renewalStatus: contractStatus,
          renewalSuggestedWage: contractSuggestedWage,
          renewalSuggestedYears: contractSuggestedYears,
          renewalError: contractError,
        },
        t,
      ),
    contractStatusClassName: getRenewalStatusClassName(contractStatus),
    myTeam,
    openFreeAgentContract,
    closeFreeAgentContract,
    submitFreeAgentContract,
  };
}
