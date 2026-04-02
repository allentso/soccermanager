import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  GameStateData,
  PlayerData,
  PlayerSelectionOptions,
  TransferOfferData,
} from "../store/gameStore";
import { Card, CardBody, Badge, CountryFlag } from "./ui";
import {
  Search,
  TrendingUp,
  ShoppingCart,
  Handshake,
  ArrowRightLeft,
  Filter,
  Gavel,
  Check,
  X,
} from "lucide-react";
import {
  getTeamName,
  calcOvr,
  calcAge,
  formatVal,
  formatWeeklyAmount,
  positionBadgeVariant,
} from "../lib/helpers";
import {
  annualAmountToWeeklyCommitment,
} from "../lib/finance";
import { useTranslation } from "react-i18next";
import { countryName } from "../lib/countries";
import {
  normalisePosition,
  translatePositionAbbreviation,
} from "./SquadTab.helpers";
import { resolveSeasonContext } from "../lib/seasonContext";
import NegotiationFeedbackPanel, {
  type NegotiationFeedbackPanelData,
} from "./NegotiationFeedbackPanel";

interface TransfersTabProps {
  gameState: GameStateData;
  onSelectPlayer: (id: string, options?: PlayerSelectionOptions) => void;
  onSelectTeam: (id: string) => void;
  onGameUpdate?: (game: GameStateData) => void;
}

type TabView = "my_list" | "market" | "loans" | "offers";

type CounterTarget = {
  player: PlayerData;
  offerId: string;
  fromTeamId: string;
  fee: number;
};

type TransferNegotiationFeedbackData = NegotiationFeedbackPanelData;

type TransferNegotiationResponseData = {
  decision: "accepted" | "rejected" | "counter_offer";
  suggested_fee: number | null;
  is_terminal: boolean;
  feedback: TransferNegotiationFeedbackData;
  game: GameStateData;
};

type TransferBidProjectionData = {
  projection: {
    transfer_budget_before: number;
    transfer_budget_after: number;
    finance_before: number;
    finance_after: number;
    annual_wage_bill_before: number;
    annual_wage_bill_after: number;
    annual_wage_budget: number;
    projected_wage_budget_usage_pct: number;
    exceeds_transfer_budget: boolean;
    exceeds_finance: boolean;
  };
};

function getOutgoingNegotiationOffer(
  player: PlayerData,
  userTeamId: string | null,
): TransferOfferData | null {
  if (!userTeamId) {
    return null;
  }

  return (
    player.transfer_offers.find(
      (offer) =>
        offer.from_team_id === userTeamId && offer.status === "Pending",
    ) ?? null
  );
}

function buildResumedBidFeedback(
  offer: TransferOfferData | null,
): TransferNegotiationFeedbackData | null {
  if (!offer) {
    return null;
  }

  const round = Math.max(offer.negotiation_round || 1, 1);
  const tension = Math.min(36 + (round - 1) * 16, 84);
  const patience = Math.max(82 - (round - 1) * 16, 30);

  return {
    mood: round >= 3 ? "tense" : "firm",
    headline_key: "transfers.resumeNegotiationHeadline",
    detail_key: "transfers.resumeNegotiationDetail",
    tension,
    patience,
    round,
    params: {
      fee: String(offer.suggested_counter_fee ?? offer.fee),
    },
  };
}

function buildResumedCounterFeedback(
  offer: TransferOfferData | null,
): TransferNegotiationFeedbackData | null {
  if (!offer) {
    return null;
  }

  const round = Math.max(offer.negotiation_round || 1, 1);
  const tension = Math.min(40 + (round - 1) * 14, 86);
  const patience = Math.max(78 - (round - 1) * 14, 28);

  return {
    mood: round >= 3 ? "tense" : "firm",
    headline_key: "transfers.resumeNegotiationHeadline",
    detail_key: "transfers.resumeNegotiationDetail",
    tension,
    patience,
    round,
    params: {
      fee: String(offer.suggested_counter_fee ?? offer.fee),
    },
  };
}

function renderNegotiationHistory(
  t: (key: string, options?: Record<string, string | number>) => string,
  offer: TransferOfferData | null,
  mode: "outgoing" | "incoming",
) {
  if (!offer || offer.negotiation_round < 2) {
    return null;
  }

  const managerLabel =
    mode === "outgoing"
      ? t("transfers.lastBidLabel")
      : t("transfers.lastCounterLabel");
  const clubLabel =
    mode === "outgoing"
      ? t("transfers.lastClubSignalLabel")
      : t("transfers.currentOfferLabel");
  const managerFee = offer.last_manager_fee;
  const clubFee = offer.suggested_counter_fee ?? offer.fee;

  return (
    <div className="rounded-lg border border-gray-200 dark:border-navy-700 bg-white/70 dark:bg-navy-900/40 p-3 mb-3 space-y-2">
      <p className="text-[11px] font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
        {t("transfers.negotiationHistory")}
      </p>
      {managerFee !== null && managerFee !== undefined ? (
        <div className="flex items-center justify-between gap-3 text-xs text-gray-600 dark:text-gray-300">
          <span>{managerLabel}</span>
          <span className="font-semibold tabular-nums text-gray-900 dark:text-gray-100">
            {formatVal(managerFee)}
          </span>
        </div>
      ) : null}
      <div className="flex items-center justify-between gap-3 text-xs text-gray-600 dark:text-gray-300">
        <span>{clubLabel}</span>
        <span className="font-semibold tabular-nums text-gray-900 dark:text-gray-100">
          {formatVal(clubFee)}
        </span>
      </div>
    </div>
  );
}

function getTransferOfferStatusLabel(
  t: (key: string, options?: Record<string, string | number>) => string,
  status: TransferOfferData["status"],
): string {
  switch (status) {
    case "Pending":
      return t("transfers.offerStatusPending");
    case "Accepted":
      return t("transfers.offerStatusAccepted");
    case "Rejected":
      return t("transfers.offerStatusRejected");
    case "Withdrawn":
      return t("transfers.offerStatusWithdrawn");
    default:
      return status;
  }
}

function getTransferOfferBadgeVariant(status: TransferOfferData["status"]) {
  switch (status) {
    case "Pending":
      return "accent" as const;
    case "Accepted":
      return "success" as const;
    case "Withdrawn":
      return "neutral" as const;
    case "Rejected":
    default:
      return "danger" as const;
  }
}

function mapTransferNegotiationError(
  t: (key: string, options?: Record<string, string | number>) => string,
  error: string,
): string {
  if (error.includes("Offer not found or not pending")) {
    return t("transfers.negotiationExpiredError");
  }

  return error;
}

export default function TransfersTab({
  gameState,
  onSelectPlayer,
  onSelectTeam,
  onGameUpdate,
}: TransfersTabProps) {
  const { t, i18n } = useTranslation();
  const weeklySuffix = t("finances.perWeekSuffix", "/wk");
  const userTeamId = gameState.manager.team_id;
  const [view, setView] = useState<TabView>("my_list");
  const [search, setSearch] = useState("");
  const [posFilter, setPosFilter] = useState<string | null>(null);
  const [bidTarget, setBidTarget] = useState<PlayerData | null>(null);
  const [bidAmount, setBidAmount] = useState("");
  const [bidResult, setBidResult] = useState<
    TransferNegotiationResponseData["decision"] | "error" | null
  >(null);
  const [bidLoading, setBidLoading] = useState(false);
  const [bidFeedback, setBidFeedback] =
    useState<TransferNegotiationFeedbackData | null>(null);
  const [bidProjection, setBidProjection] =
    useState<TransferBidProjectionData["projection"] | null>(null);
  const [counterTarget, setCounterTarget] = useState<CounterTarget | null>(
    null,
  );
  const [counterAmount, setCounterAmount] = useState("");
  const [counterLoading, setCounterLoading] = useState(false);
  const [counterError, setCounterError] = useState<string | null>(null);
  const [counterResult, setCounterResult] = useState<
    TransferNegotiationResponseData["decision"] | "error" | null
  >(null);
  const [counterFeedback, setCounterFeedback] =
    useState<TransferNegotiationFeedbackData | null>(null);

  const openBidNegotiation = (player: PlayerData) => {
    const existingOffer = getOutgoingNegotiationOffer(player, userTeamId);

    setBidTarget(player);
    setBidAmount(
      (
        (existingOffer?.suggested_counter_fee ?? existingOffer?.fee ?? player.market_value) /
        1_000_000
      ).toFixed(existingOffer ? 2 : 1),
    );
    setBidResult(null);
    setBidFeedback(buildResumedBidFeedback(existingOffer));
    setBidProjection(null);
  };

  const openCounterNegotiation = (
    player: PlayerData,
    offer: TransferOfferData,
  ) => {
    setCounterTarget({
      player,
      offerId: offer.id,
      fromTeamId: offer.from_team_id,
      fee: offer.fee,
    });
    setCounterAmount(
      ((offer.suggested_counter_fee ?? offer.fee) / 1_000_000).toFixed(
        offer.negotiation_round > 1 ? 2 : 1,
      ),
    );
    setCounterError(null);
    setCounterResult(null);
    setCounterFeedback(buildResumedCounterFeedback(offer));
  };

  const handleMakeBid = async () => {
    if (!bidTarget || !bidAmount) return;
    setBidLoading(true);
    setBidResult(null);
    setBidFeedback(null);
    try {
      const fee = Math.round(parseFloat(bidAmount) * 1_000_000);
      const res = await invoke<TransferNegotiationResponseData>(
        "make_transfer_bid",
        { playerId: bidTarget.id, fee },
      );
      setBidResult(res.decision);
      setBidFeedback(res.feedback);
      if (onGameUpdate) onGameUpdate(res.game);
      if (res.suggested_fee !== null) {
        setBidAmount((res.suggested_fee / 1_000_000).toFixed(2));
      }
      if (res.decision === "accepted") {
        setTimeout(() => {
          setBidTarget(null);
          setBidResult(null);
          setBidFeedback(null);
        }, 2000);
      }
    } catch (err: any) {
      setBidResult(err?.toString() || "error");
      setBidFeedback(null);
    } finally {
      setBidLoading(false);
    }
  };

  const handleRespondOffer = async (
    playerId: string,
    offerId: string,
    accept: boolean,
  ) => {
    try {
      const game = await invoke<GameStateData>("respond_to_offer", {
        playerId,
        offerId,
        accept,
      });
      if (onGameUpdate) onGameUpdate(game);
    } catch (err) {
      console.error("Failed to respond to offer:", err);
    }
  };

  const handleCounterOffer = async () => {
    if (!counterTarget || !counterAmount) return;

    setCounterLoading(true);
    setCounterError(null);
    setCounterResult(null);
    setCounterFeedback(null);

    try {
      const requestedFee = Math.round(parseFloat(counterAmount) * 1_000_000);
      const response = await invoke<TransferNegotiationResponseData>(
        "counter_offer",
        {
          playerId: counterTarget.player.id,
          offerId: counterTarget.offerId,
          requestedFee,
        },
      );

      if (onGameUpdate) onGameUpdate(response.game);
      setCounterResult(response.decision);
      setCounterFeedback(response.feedback);
      if (response.suggested_fee !== null) {
        setCounterAmount((response.suggested_fee / 1_000_000).toFixed(2));
      }
      if (response.decision === "accepted") {
        setTimeout(() => {
          setCounterTarget(null);
          setCounterAmount("");
          setCounterResult(null);
          setCounterFeedback(null);
        }, 1500);
      }
    } catch (err: any) {
      setCounterError(
        mapTransferNegotiationError(t, err?.toString() || "error"),
      );
    } finally {
      setCounterLoading(false);
    }
  };

  const myTeam = gameState.teams.find(
    (team) => team.id === gameState.manager.team_id,
  );
  const activeBidOffer = bidTarget
    ? getOutgoingNegotiationOffer(bidTarget, userTeamId)
    : null;
  const activeCounterOffer = counterTarget
    ? counterTarget.player.transfer_offers.find(
      (offer) => offer.id === counterTarget.offerId,
    ) ?? null
    : null;
  const seasonContext = resolveSeasonContext(gameState);
  const transferWindow = seasonContext.transfer_window;
  const transferWindowVariant =
    transferWindow.status === "DeadlineDay"
      ? "danger"
      : transferWindow.status === "Open"
        ? "success"
        : "neutral";
  const transferWindowSummary =
    transferWindow.status === "DeadlineDay"
      ? t("season.windowClosesToday")
      : transferWindow.status === "Open" &&
        transferWindow.days_remaining !== null
        ? t("season.windowClosesInDays", {
          count: transferWindow.days_remaining,
        })
        : transferWindow.status === "Closed" &&
          transferWindow.days_until_opens !== null
          ? t("season.windowOpensInDays", {
            count: transferWindow.days_until_opens,
          })
          : t("season.windowClosed");

  // My team's transfer-listed players
  const myTransferList = gameState.players.filter(
    (p) => p.team_id === userTeamId && p.transfer_listed,
  );
  const myLoanList = gameState.players.filter(
    (p) => p.team_id === userTeamId && p.loan_listed,
  );

  // Market: all transfer-listed players from other teams
  const marketPlayers = gameState.players.filter(
    (p) => p.transfer_listed && p.team_id !== userTeamId,
  );

  // Loans available: all loan-listed players from other teams
  const loanPlayers = gameState.players.filter(
    (p) => p.loan_listed && p.team_id !== userTeamId,
  );

  // Players with offers involving user's team (either incoming to user's players or user's bids)
  const playersWithOffers = gameState.players.filter(
    (p) =>
      p.transfer_offers.length > 0 &&
      (p.team_id === userTeamId ||
        p.transfer_offers.some((o) => o.from_team_id === userTeamId)),
  );

  const applyFilters = (list: PlayerData[]) => {
    return list.filter((p) => {
      if (
        posFilter &&
        normalisePosition(p.natural_position || p.position) !== posFilter
      ) {
        return false;
      }
      if (search.length >= 2) {
        const q = search.toLowerCase();
        if (
          !p.full_name.toLowerCase().includes(q) &&
          !p.nationality.toLowerCase().includes(q)
        )
          return false;
      }
      return true;
    });
  };

  const positions = ["Goalkeeper", "Defender", "Midfielder", "Forward"];

  const tabs: {
    id: TabView;
    label: string;
    icon: React.ReactNode;
    count: number;
  }[] = [
      {
        id: "my_list",
        label: t("transfers.myTransferList"),
        icon: <ShoppingCart className="w-4 h-4" />,
        count: myTransferList.length + myLoanList.length,
      },
      {
        id: "market",
        label: t("transfers.transferMarket"),
        icon: <TrendingUp className="w-4 h-4" />,
        count: marketPlayers.length,
      },
      {
        id: "loans",
        label: t("transfers.loanMarket"),
        icon: <ArrowRightLeft className="w-4 h-4" />,
        count: loanPlayers.length,
      },
      {
        id: "offers",
        label: t("transfers.offers"),
        icon: <Handshake className="w-4 h-4" />,
        count: playersWithOffers.length,
      },
    ];

  const currentList =
    view === "my_list"
      ? [...myTransferList, ...myLoanList]
      : view === "market"
        ? marketPlayers
        : view === "loans"
          ? loanPlayers
          : playersWithOffers;

  const filteredList = applyFilters(currentList);
  const weeklyWageBudget = myTeam
    ? annualAmountToWeeklyCommitment(myTeam.wage_budget)
    : 0;
  const bidAmountMillions = Number.parseFloat(bidAmount);
  const bidFee = Number.isFinite(bidAmountMillions)
    ? Math.round(bidAmountMillions * 1_000_000)
    : null;

  useEffect(() => {
    if (!bidTarget || bidFee === null || bidFee <= 0) {
      setBidProjection(null);
      return;
    }

    let cancelled = false;

    const loadProjection = async (): Promise<void> => {
      try {
        const result = await invoke<TransferBidProjectionData>(
          "preview_transfer_bid_financial_impact",
          {
            playerId: bidTarget.id,
            fee: bidFee,
          },
        );

        if (!cancelled) {
          setBidProjection(result.projection ?? null);
        }
      } catch {
        if (!cancelled) {
          setBidProjection(null);
        }
      }
    };

    loadProjection();

    return () => {
      cancelled = true;
    };
  }, [bidFee, bidTarget]);

  const bidSubmitDisabled =
    bidLoading ||
    bidResult === "accepted" ||
    bidFee === null ||
    bidFee <= 0 ||
    bidProjection === null ||
    bidProjection.exceeds_transfer_budget ||
    bidProjection.exceeds_finance;

  return (
    <div className="max-w-6xl mx-auto">
      {/* Budget header */}
      {myTeam && (
        <Card accent="primary" className="mb-5">
          <div className="bg-gradient-to-r from-navy-700 to-navy-800 p-5 rounded-t-xl flex items-center gap-6">
            <div className="flex-1">
              <div className="flex flex-wrap items-center gap-2">
                <h2 className="text-lg font-heading font-bold text-white uppercase tracking-wide flex items-center gap-2">
                  <TrendingUp className="w-5 h-5 text-accent-400" />
                  {t("transfers.centre")}
                </h2>
                <Badge variant={transferWindowVariant} size="sm">
                  {t(`season.transferWindowStatus.${transferWindow.status}`)}
                </Badge>
              </div>
              <p className="text-gray-400 text-xs mt-0.5">
                {t("transfers.transferWindow", { team: myTeam.name })}
              </p>
              <p className="text-gray-500 text-xs mt-1">
                {transferWindowSummary}
              </p>
            </div>
            <div className="hidden md:flex gap-4">
              <div className="bg-white/5 rounded-xl px-4 py-2 text-center">
                <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">
                  {t("finances.transferBudget")}
                </p>
                <p className="font-heading font-bold text-lg text-accent-400">
                  {formatVal(myTeam.transfer_budget)}
                </p>
              </div>
              <div className="bg-white/5 rounded-xl px-4 py-2 text-center">
                <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">
                  {t("finances.wageBudget")}
                </p>
                <p className="font-heading font-bold text-lg text-white">
                  {formatWeeklyAmount(
                    formatVal(weeklyWageBudget),
                    weeklySuffix,
                  )}
                </p>
              </div>
              <div className="bg-white/5 rounded-xl px-4 py-2 text-center">
                <p className="text-xs text-gray-400 font-heading uppercase tracking-wider">
                  {t("transfers.listed")}
                </p>
                <p className="font-heading font-bold text-lg text-white">
                  {myTransferList.length + myLoanList.length}
                </p>
              </div>
            </div>
          </div>
        </Card>
      )}

      {/* Tab navigation */}
      <div className="flex gap-2 mb-4 flex-wrap">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setView(tab.id)}
            className={`px-4 py-2 rounded-lg font-heading font-bold text-sm uppercase tracking-wider transition-all flex items-center gap-1.5 ${view === tab.id
              ? "bg-primary-500 text-white shadow-md shadow-primary-500/20"
              : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600 hover:text-gray-700 dark:hover:text-gray-200"
              }`}
          >
            {tab.icon} {tab.label} ({tab.count})
          </button>
        ))}
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-3 mb-4 items-center">
        <div className="relative flex-1 min-w-[180px] max-w-xs">
          <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 dark:text-gray-500" />
          <input
            type="text"
            placeholder={t("transfers.searchByName")}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2 rounded-lg bg-white dark:bg-navy-800 border border-gray-200 dark:border-navy-600 text-sm text-gray-800 dark:text-gray-200 placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-500/50"
          />
        </div>
        <div className="flex gap-1.5">
          <button
            onClick={() => setPosFilter(null)}
            className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${!posFilter ? "bg-primary-500 text-white shadow-sm" : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600"}`}
          >
            {t("common.all")}
          </button>
          {positions.map((pos) => (
            <button
              key={pos}
              onClick={() => setPosFilter(posFilter === pos ? null : pos)}
              className={`px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-all ${posFilter === pos ? "bg-primary-500 text-white shadow-sm" : "bg-white dark:bg-navy-800 text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-navy-600"}`}
            >
              {t(`common.posAbbr.${pos}`)}
            </button>
          ))}
        </div>
        <p className="text-xs text-gray-400 dark:text-gray-500 font-heading uppercase tracking-wider">
          <Filter className="w-3.5 h-3.5 inline mr-1 -mt-0.5" />
          {t("common.nResults", { count: filteredList.length })}
        </p>
      </div>

      {/* Content */}
      {view === "my_list" && filteredList.length === 0 && (
        <Card>
          <CardBody>
            <div className="text-center py-8">
              <ShoppingCart className="w-10 h-10 text-gray-300 dark:text-navy-600 mx-auto mb-3" />
              <p className="text-sm text-gray-500 dark:text-gray-400">
                {t("transfers.noPlayersListed")}
              </p>
              <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">
                {t("transfers.goToProfile")}
              </p>
            </div>
          </CardBody>
        </Card>
      )}

      {view === "offers" && filteredList.length === 0 && (
        <Card>
          <CardBody>
            <div className="text-center py-8">
              <Handshake className="w-10 h-10 text-gray-300 dark:text-navy-600 mx-auto mb-3" />
              <p className="text-sm text-gray-500 dark:text-gray-400">
                {t("transfers.noOffers")}
              </p>
            </div>
          </CardBody>
        </Card>
      )}

      {filteredList.length > 0 && (
        <Card>
          <CardBody className="p-0">
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="bg-gray-50 dark:bg-navy-800 border-b border-gray-200 dark:border-navy-600 text-xs">
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                      {t("common.position")}
                    </th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                      {t("common.player")}
                    </th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                      {t("common.age")}
                    </th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                      {t("common.team")}
                    </th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                      {t("common.value")}
                    </th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                      {t("common.wage")}
                    </th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                      {t("common.ovr")}
                    </th>
                    <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                      {t("common.status")}
                    </th>
                    {view === "offers" && (
                      <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                        {t("transfers.offers")}
                      </th>
                    )}
                    {(view === "market" || view === "loans") && (
                      <th className="py-3 px-4 font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                        {t("common.action")}
                      </th>
                    )}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100 dark:divide-navy-600">
                  {filteredList.map((player) => {
                    const ovr = calcOvr(
                      player,
                      player.natural_position || player.position,
                    );
                    const age = calcAge(player.date_of_birth);
                    const offersForThisPlayer = player.transfer_offers;
                    return (
                      <tr
                        key={player.id}
                        className="hover:bg-gray-50 dark:hover:bg-navy-700/50 transition-colors cursor-pointer group"
                        onClick={() => onSelectPlayer(player.id)}
                      >
                        <td className="py-2.5 px-4">
                          <Badge
                            variant={positionBadgeVariant(
                              player.natural_position || player.position,
                            )}
                            size="sm"
                          >
                            {translatePositionAbbreviation(
                              t,
                              player.natural_position || player.position,
                            )}
                          </Badge>
                        </td>
                        <td className="py-2.5 px-4">
                          <span className="font-semibold text-sm text-gray-800 dark:text-gray-200 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors">
                            {player.full_name}
                          </span>
                          <div className="text-xs text-gray-400 dark:text-gray-500 mt-0.5 flex items-center gap-1">
                            <CountryFlag
                              code={player.nationality}
                              locale={i18n.language}
                              className="text-sm leading-none"
                            />
                            <span>
                              {countryName(player.nationality, i18n.language)}
                            </span>
                          </div>
                        </td>
                        <td className="py-2.5 px-4 text-sm text-gray-600 dark:text-gray-400 tabular-nums">
                          {age}
                        </td>
                        <td className="py-2.5 px-4">
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              if (player.team_id) onSelectTeam(player.team_id);
                            }}
                            className="text-sm text-gray-600 dark:text-gray-400 hover:text-primary-500 hover:underline transition-colors"
                          >
                            {getTeamName(gameState.teams, player.team_id)}
                          </button>
                        </td>
                        <td className="py-2.5 px-4 text-sm text-gray-600 dark:text-gray-400 font-medium tabular-nums">
                          {formatVal(player.market_value)}
                        </td>
                        <td className="py-2.5 px-4 text-sm text-gray-600 dark:text-gray-400 tabular-nums">
                          {formatVal(player.wage)}/yr
                        </td>
                        <td className="py-2.5 px-4">
                          <span
                            className={`font-heading font-bold text-base tabular-nums ${ovr >= 75 ? "text-primary-500" : ovr >= 55 ? "text-accent-500" : "text-gray-400"}`}
                          >
                            {ovr}
                          </span>
                        </td>
                        <td className="py-2.5 px-4">
                          <div className="flex gap-1">
                            {player.transfer_listed && (
                              <Badge variant="accent" size="sm">
                                {t("transfers.transfer")}
                              </Badge>
                            )}
                            {player.loan_listed && (
                              <Badge variant="primary" size="sm">
                                {t("transfers.loan")}
                              </Badge>
                            )}
                          </div>
                        </td>
                        {view === "offers" && (
                          <td className="py-2.5 px-4">
                            <div className="flex flex-col gap-1">
                              {offersForThisPlayer.length === 0 ? (
                                <span className="text-xs text-gray-400">
                                  {t("transfers.none")}
                                </span>
                              ) : (
                                offersForThisPlayer.map((offer) => (
                                  <div
                                    key={offer.id}
                                    className="flex items-center gap-2"
                                  >
                                    <span className="text-xs text-gray-600 dark:text-gray-300 font-medium">
                                      {getTeamName(
                                        gameState.teams,
                                        offer.from_team_id,
                                      )}
                                    </span>
                                    <Badge
                                      variant={getTransferOfferBadgeVariant(
                                        offer.status,
                                      )}
                                      size="sm"
                                    >
                                      {formatVal(offer.fee)} — {getTransferOfferStatusLabel(t, offer.status)}
                                    </Badge>
                                    {offer.status === "Pending" &&
                                      player.team_id === userTeamId && (
                                        <div className="flex gap-1 ml-1">
                                          <button
                                            onClick={(e) => {
                                              e.stopPropagation();
                                              handleRespondOffer(
                                                player.id,
                                                offer.id,
                                                true,
                                              );
                                            }}
                                            className="p-1 rounded bg-green-500/20 hover:bg-green-500/30 text-green-500"
                                            title={t("transfers.acceptOffer")}
                                          >
                                            <Check className="w-3 h-3" />
                                          </button>
                                          <button
                                            onClick={(e) => {
                                              e.stopPropagation();
                                              handleRespondOffer(
                                                player.id,
                                                offer.id,
                                                false,
                                              );
                                            }}
                                            className="p-1 rounded bg-red-500/20 hover:bg-red-500/30 text-red-500"
                                            title={t("transfers.rejectOffer")}
                                          >
                                            <X className="w-3 h-3" />
                                          </button>
                                          <button
                                            onClick={(e) => {
                                              e.stopPropagation();
                                              openCounterNegotiation(player, offer);
                                            }}
                                            aria-label={t("transfers.counterOffer")}
                                            className="flex items-center gap-1 px-2 py-1 rounded bg-amber-500/20 hover:bg-amber-500/30 text-amber-500 text-xs font-heading font-bold uppercase tracking-wider"
                                            title={t("transfers.counterOffer")}
                                          >
                                            <Gavel className="w-3 h-3" />{" "}
                                            {t("transfers.counter")}
                                          </button>
                                        </div>
                                      )}
                                  </div>
                                ))
                              )}
                            </div>
                          </td>
                        )}
                        {(view === "market" || view === "loans") && (
                          <td className="py-2.5 px-4">
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                openBidNegotiation(player);
                              }}
                              className="flex items-center gap-1 px-3 py-1.5 bg-primary-500/10 hover:bg-primary-500/20 text-primary-500 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-colors"
                            >
                              <Gavel className="w-3 h-3" /> {t("transfers.bid")}
                            </button>
                          </td>
                        )}
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </CardBody>
        </Card>
      )}

      {(view === "market" || view === "loans") && filteredList.length === 0 && (
        <Card>
          <CardBody>
            <div className="text-center py-8">
              <TrendingUp className="w-10 h-10 text-gray-300 dark:text-navy-600 mx-auto mb-3" />
              <p className="text-sm text-gray-500 dark:text-gray-400">
                {view === "market"
                  ? t("transfers.noTransferMarket")
                  : t("transfers.noLoanMarket")}
              </p>
            </div>
          </CardBody>
        </Card>
      )}
      {/* Bid Modal */}
      {bidTarget && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
          onClick={() => {
            setBidTarget(null);
            setBidFeedback(null);
            setBidResult(null);
            setBidProjection(null);
          }}
        >
          <div
            className="bg-white dark:bg-navy-800 rounded-xl shadow-2xl border border-gray-200 dark:border-navy-600 p-6 w-full max-w-sm"
            onClick={(e) => e.stopPropagation()}
          >
            <h3 className="text-sm font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-3">
              {t("transfers.makeBid")}
            </h3>
            <div className="flex items-center gap-3 mb-4">
              <Badge
                variant={positionBadgeVariant(bidTarget.position)}
                size="sm"
              >
                {translatePositionAbbreviation(t, bidTarget.position)}
              </Badge>
              <div>
                <p className="font-semibold text-sm text-gray-800 dark:text-gray-200">
                  {bidTarget.full_name}
                </p>
                <p className="text-xs text-gray-400">
                  {getTeamName(gameState.teams, bidTarget.team_id)} •{" "}
                  {t("transfers.playerValue", {
                    value: formatVal(bidTarget.market_value),
                  })}
                </p>
              </div>
            </div>
            {getOutgoingNegotiationOffer(bidTarget, userTeamId) ? (
              <p className="text-xs text-gray-500 dark:text-gray-400 mb-3">
                {t("transfers.resumeNegotiationHint")}
              </p>
            ) : null}
            <label htmlFor="bid-amount" className="text-xs font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-1 block">
              {t("transfers.bidAmount")}
            </label>
            <input
              id="bid-amount"
              type="number"
              step="0.1"
              min="0"
              value={bidAmount}
              onChange={(e) => setBidAmount(e.target.value)}
              className="w-full px-3 py-2 rounded-lg bg-gray-50 dark:bg-navy-700 border border-gray-200 dark:border-navy-600 text-sm text-gray-800 dark:text-gray-200 mb-3 focus:outline-none focus:ring-2 focus:ring-primary-500/50"
            />
            {myTeam && bidFee !== null && bidProjection ? (
              <div className="rounded-lg border border-gray-200 dark:border-navy-700 bg-white/70 dark:bg-navy-900/40 p-3 mb-3 space-y-2">
                <p className="text-[11px] font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400">
                  {t("transfers.bidImpactTitle", {
                    defaultValue: "Projected impact",
                  })}
                </p>
                <p className="text-xs text-gray-600 dark:text-gray-300">
                  {t("transfers.bidImpactTransferBudget", {
                    before: formatVal(bidProjection.transfer_budget_before),
                    after: formatVal(bidProjection.transfer_budget_after),
                    defaultValue: "Transfer budget {{before}} -> {{after}}",
                  })}
                </p>
                <p className="text-xs text-gray-600 dark:text-gray-300">
                  {t("transfers.bidImpactBalance", {
                    before: formatVal(bidProjection.finance_before),
                    after: formatVal(bidProjection.finance_after),
                    defaultValue: "Club balance {{before}} -> {{after}}",
                  })}
                </p>
                <p className="text-xs text-gray-600 dark:text-gray-300">
                  {t("transfers.bidImpactWagePressure", {
                    percent: bidProjection.projected_wage_budget_usage_pct,
                    defaultValue: "Projected wage budget usage {{percent}}%",
                  })}
                </p>
                {bidProjection.exceeds_transfer_budget ? (
                  <p className="text-xs text-red-500">
                    {t("transfers.bidImpactOverTransferBudget", {
                      defaultValue: "This bid exceeds your transfer budget",
                    })}
                  </p>
                ) : null}
                {bidProjection.exceeds_finance ? (
                  <p className="text-xs text-red-500">
                    {t("transfers.bidImpactOverBalance", {
                      defaultValue: "This bid would push the club into debt",
                    })}
                  </p>
                ) : null}
              </div>
            ) : null}
            <NegotiationFeedbackPanel
              feedback={bidFeedback}
              titleKey="transfers.negotiationPulse"
              roundKey="transfers.negotiationRound"
              patienceKey="transfers.negotiationPatience"
              tensionKey="transfers.negotiationTension"
              className="mb-3"
            />
            {renderNegotiationHistory(t, activeBidOffer, "outgoing")}
            {bidResult && (
              <div
                className={`text-xs font-heading font-bold uppercase tracking-wider mb-3 ${bidResult === "accepted" ? "text-green-500" : bidResult === "rejected" ? "text-red-500" : "text-amber-500"}`}
              >
                {bidResult === "accepted"
                  ? t("transfers.bidAccepted")
                  : bidResult === "rejected"
                    ? t("transfers.bidRejected")
                    : bidResult === "counter_offer"
                      ? t("transfers.bidCountered")
                      : bidResult}
              </div>
            )}
            <div className="flex gap-2">
              <button
                onClick={handleMakeBid}
                disabled={bidSubmitDisabled}
                className="flex-1 py-2 bg-primary-500 hover:bg-primary-600 text-white rounded-lg font-heading font-bold text-sm uppercase tracking-wider transition-colors disabled:opacity-50"
              >
                {bidLoading
                  ? t("transfers.submitting")
                  : t("transfers.submitBid")}
              </button>
              <button
                onClick={() => {
                  setBidTarget(null);
                  setBidFeedback(null);
                  setBidResult(null);
                  setBidProjection(null);
                }}
                className="px-4 py-2 bg-gray-200 dark:bg-navy-700 text-gray-600 dark:text-gray-300 rounded-lg font-heading font-bold text-sm uppercase tracking-wider hover:bg-gray-300 dark:hover:bg-navy-600 transition-colors"
              >
                {t("transfers.close")}
              </button>
            </div>
          </div>
        </div>
      )}
      {counterTarget && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
          onClick={() => {
            setCounterTarget(null);
            setCounterAmount("");
            setCounterError(null);
            setCounterResult(null);
            setCounterFeedback(null);
          }}
        >
          <div
            className="bg-white dark:bg-navy-800 rounded-xl shadow-2xl border border-gray-200 dark:border-navy-600 p-6 w-full max-w-sm"
            onClick={(e) => e.stopPropagation()}
          >
            <h3 className="text-sm font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-3">
              {t("transfers.counterOffer")}
            </h3>
            <div className="flex items-center gap-3 mb-4">
              <Badge
                variant={positionBadgeVariant(counterTarget.player.position)}
                size="sm"
              >
                {translatePositionAbbreviation(
                  t,
                  counterTarget.player.position,
                )}
              </Badge>
              <div>
                <p className="font-semibold text-sm text-gray-800 dark:text-gray-200">
                  {counterTarget.player.full_name}
                </p>
                <p className="text-xs text-gray-400">
                  {getTeamName(gameState.teams, counterTarget.fromTeamId)} •
                  {t("transfers.currentOffer", {
                    fee: formatVal(counterTarget.fee),
                  })}
                </p>
              </div>
            </div>
            {counterFeedback ? (
              <p className="text-xs text-gray-500 dark:text-gray-400 mb-3">
                {t("transfers.resumeNegotiationHint")}
              </p>
            ) : null}
            <label
              htmlFor="counter-offer-amount"
              className="text-xs font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-1 block"
            >
              {t("transfers.counterAmount")}
            </label>
            <input
              id="counter-offer-amount"
              type="number"
              step="0.1"
              min="0"
              value={counterAmount}
              onChange={(e) => setCounterAmount(e.target.value)}
              className="w-full px-3 py-2 rounded-lg bg-gray-50 dark:bg-navy-700 border border-gray-200 dark:border-navy-600 text-sm text-gray-800 dark:text-gray-200 mb-3 focus:outline-none focus:ring-2 focus:ring-primary-500/50"
            />
            <NegotiationFeedbackPanel
              feedback={counterFeedback}
              titleKey="transfers.negotiationPulse"
              roundKey="transfers.negotiationRound"
              patienceKey="transfers.negotiationPatience"
              tensionKey="transfers.negotiationTension"
              className="mb-3"
            />
            {renderNegotiationHistory(t, activeCounterOffer, "incoming")}
            {counterResult && (
              <div
                className={`text-xs font-heading font-bold uppercase tracking-wider mb-3 ${counterResult === "accepted" ? "text-green-500" : counterResult === "rejected" ? "text-red-500" : "text-amber-500"}`}
              >
                {counterResult === "accepted"
                  ? t("transfers.counterAccepted")
                  : counterResult === "rejected"
                    ? t("transfers.counterRejected")
                    : t("transfers.counterCountered")}
              </div>
            )}
            {counterError && (
              <div className="text-xs font-heading font-bold uppercase tracking-wider mb-3 text-red-500">
                {counterError}
              </div>
            )}
            <div className="flex gap-2">
              <button
                onClick={handleCounterOffer}
                disabled={counterLoading || counterResult === "accepted"}
                className="flex-1 py-2 bg-primary-500 hover:bg-primary-600 text-white rounded-lg font-heading font-bold text-sm uppercase tracking-wider transition-colors disabled:opacity-50"
              >
                {counterLoading
                  ? t("transfers.submitting")
                  : t("transfers.submitCounter")}
              </button>
              <button
                onClick={() => {
                  setCounterTarget(null);
                  setCounterAmount("");
                  setCounterError(null);
                  setCounterResult(null);
                  setCounterFeedback(null);
                }}
                className="px-4 py-2 bg-gray-200 dark:bg-navy-700 text-gray-600 dark:text-gray-300 rounded-lg font-heading font-bold text-sm uppercase tracking-wider hover:bg-gray-300 dark:hover:bg-navy-600 transition-colors"
              >
                {t("transfers.close")}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
