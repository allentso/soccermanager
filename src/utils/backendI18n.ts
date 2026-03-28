import i18n from '../i18n';
import type {
  MessageActionOption,
  MessageData,
  MessageAction,
  NewsArticle,
  BoardObjective,
} from '../store/gameStore';

const PLAYER_EVENT_PREFIX_TO_GROUP: Record<string, string> = {
  morale_talk_: 'moraleCrisis',
  bench_complaint_: 'benchComplaint',
  happy_player_: 'happyPlayer',
  contract_concern_: 'contractConcern',
};

const PLAYER_EVENT_OPTION_ID_TO_KEY: Record<string, string> = {
  encourage: 'encourage',
  promise_time: 'promiseTime',
  work_harder: 'workHarder',
  explain: 'explain',
  promise_chance: 'promiseChance',
  prove_yourself: 'proveYourself',
  praise_back: 'praiseBack',
  stay_professional: 'stayProfessional',
  higher_expectations: 'higherExpectations',
  reassure: 'reassure',
  noncommittal: 'noncommittal',
  no_renewal: 'noRenewal',
};

const LEGACY_DELEGATED_RENEWALS_PREFIX = 'delegated_renewals_';
const LEGACY_DELEGATED_RENEWALS_SUMMARY_RE =
  /^Boss, I went through our renewal list at (?<team>.+)\. (?<successes>\d+) completed, (?<stalled>\d+) still pending, (?<failures>\d+) failed\.$/;
const LEGACY_DELEGATED_RENEWALS_SUCCESS_RE =
  /^Completed: (?<player>.+) agreed to (?<years>\d+) year\(s\) on €(?<wage>\d+)\/wk\.$/;
const LEGACY_DELEGATED_RENEWALS_STATUS_RE =
  /^(?<status>Still difficult|Failed): (?<player>.+) — (?<detail>.+)$/;
const LEGACY_DELEGATED_RENEWALS_BEYOND_LIMITS_RE =
  /^Their camp want around €(?<wage>\d+)\/wk for (?<years>\d+) years, which is beyond the delegation limits\.$/;
const LEGACY_DELEGATED_RENEWALS_PREFERS_MANAGER_RE =
  /^They would listen, but they still want about €(?<wage>\d+)\/wk for (?<years>\d+) years and prefer to hear from you directly\.$/;
const LEGACY_DELEGATED_RENEWALS_MANAGER_BLOCKED_RE =
  /^You told me not to reopen contract talks yet\.$/;
const LEGACY_DELEGATED_RENEWALS_RELATIONSHIP_BLOCKED_RE =
  /^They are not willing to commit through me under the current relationship and contract situation\.$/;
const LEGACY_WEEKLY_DIGEST_WEEK_LABEL_RE =
  /^Week of (?<weekStart>\d{4}-\d{2}-\d{2})$/;
const LEGACY_WEEKLY_DIGEST_HEADLINE_RE =
  /^Weekly Digest — Week of (?<weekStart>\d{4}-\d{2}-\d{2})$/;

/**
 * Resolve a backend i18n key with params, falling back to the raw string.
 */
function resolve(key: string | undefined, fallback: string, params?: Record<string, string>): string {
  if (!key) return fallback;
  const resolved = i18n.t(key, params ?? {});
  // i18next returns the key itself if not found — fall back to raw string
  if (resolved === key) return fallback;
  return resolved;
}

export function resolveBackendText(
  key: string | undefined,
  fallback: string,
  params?: Record<string, string>,
): string {
  return resolve(key, fallback, params);
}

function boardObjectiveFallback(objective: BoardObjective): string {
  switch (objective.objective_type) {
    case 'LeaguePosition':
      return `Finish in the top ${objective.target}`;
    case 'Wins':
      return `Win at least ${objective.target} matches`;
    case 'GoalsScored':
      return `Score at least ${objective.target} goals`;
    default:
      return objective.description;
  }
}

/**
 * Pre-resolve any param values that are themselves i18n keys (e.g. "common.moods.excellent").
 * A value is treated as a key if it contains a dot and i18next resolves it to something different.
 */
function resolveParamValues(params?: Record<string, string>): Record<string, string> | undefined {
  if (!params) return params;
  const resolved = { ...params };
  for (const [key, value] of Object.entries(resolved)) {
    if (value.includes('.')) {
      const attempted = i18n.t(value);
      if (attempted !== value) {
        resolved[key] = attempted;
      }
    }
  }
  return resolved;
}

function inferPlayerEventGroup(messageId: string): string | undefined {
  for (const [prefix, group] of Object.entries(PLAYER_EVENT_PREFIX_TO_GROUP)) {
    if (messageId.startsWith(prefix)) {
      return group;
    }
  }

  return undefined;
}

function inferPlayerEventActionLabelKey(messageId: string, actionId: string): string | undefined {
  if (!inferPlayerEventGroup(messageId)) {
    return undefined;
  }

  if (actionId === 'respond') {
    return 'be.msg.playerEvent.respond';
  }

  return undefined;
}

function inferPlayerEventOptionBaseKey(messageId: string, optionId: string): string | undefined {
  const group = inferPlayerEventGroup(messageId);
  const optionKey = PLAYER_EVENT_OPTION_ID_TO_KEY[optionId];

  if (!group || !optionKey) {
    return undefined;
  }

  return `be.msg.playerEvent.options.${group}.${optionKey}`;
}

function inferLegacyDelegatedRenewalsParams(message: MessageData): Record<string, string> | undefined {
  if (!message.id.startsWith(LEGACY_DELEGATED_RENEWALS_PREFIX)) {
    return undefined;
  }

  const summaryLine = message.body
    .split('\n')
    .map((line) => line.trim())
    .find((line) => line.length > 0);

  const match = summaryLine?.match(LEGACY_DELEGATED_RENEWALS_SUMMARY_RE);
  if (!match?.groups) {
    return undefined;
  }

  return {
    team: match.groups.team,
    successes: match.groups.successes,
    stalled: match.groups.stalled,
    failures: match.groups.failures,
  };
}

function resolveLegacyDelegatedRenewalsDetail(detail: string): string {
  const beyondLimits = detail.match(LEGACY_DELEGATED_RENEWALS_BEYOND_LIMITS_RE);
  if (beyondLimits?.groups) {
    return resolve('be.msg.delegatedRenewals.notes.beyondLimits', detail, {
      wage: beyondLimits.groups.wage,
      years: beyondLimits.groups.years,
    });
  }

  const prefersManager = detail.match(LEGACY_DELEGATED_RENEWALS_PREFERS_MANAGER_RE);
  if (prefersManager?.groups) {
    return resolve('be.msg.delegatedRenewals.notes.prefersManager', detail, {
      wage: prefersManager.groups.wage,
      years: prefersManager.groups.years,
    });
  }

  if (LEGACY_DELEGATED_RENEWALS_MANAGER_BLOCKED_RE.test(detail)) {
    return resolve('be.msg.delegatedRenewals.notes.managerBlocked', detail);
  }

  if (LEGACY_DELEGATED_RENEWALS_RELATIONSHIP_BLOCKED_RE.test(detail)) {
    return resolve('be.msg.delegatedRenewals.notes.relationshipBlocked', detail);
  }

  return detail;
}

function resolveLegacyDelegatedRenewalsBody(body: string): string {
  const lines = body.split('\n');

  return lines
    .map((line) => {
      const trimmed = line.trim();

      if (trimmed.length === 0) {
        return line;
      }

      const summary = trimmed.match(LEGACY_DELEGATED_RENEWALS_SUMMARY_RE);
      if (summary?.groups) {
        return resolve('be.msg.delegatedRenewals.body', trimmed, {
          team: summary.groups.team,
          successes: summary.groups.successes,
          stalled: summary.groups.stalled,
          failures: summary.groups.failures,
        });
      }

      const success = trimmed.match(LEGACY_DELEGATED_RENEWALS_SUCCESS_RE);
      if (success?.groups) {
        return resolve('be.msg.delegatedRenewals.case.successful', trimmed, {
          player: success.groups.player,
          years: success.groups.years,
          wage: success.groups.wage,
        });
      }

      const status = trimmed.match(LEGACY_DELEGATED_RENEWALS_STATUS_RE);
      if (status?.groups) {
        const detail = resolveLegacyDelegatedRenewalsDetail(status.groups.detail);
        const key =
          status.groups.status === 'Still difficult'
            ? 'be.msg.delegatedRenewals.case.stalled'
            : 'be.msg.delegatedRenewals.case.failed';

        return resolve(key, trimmed, {
          player: status.groups.player,
          detail,
        });
      }

      return line;
    })
    .join('\n');
}

function resolveLegacyDelegatedRenewalsMessage(
  msg: MessageData,
  params?: Record<string, string>,
): MessageData {
  if (!msg.id.startsWith(LEGACY_DELEGATED_RENEWALS_PREFIX)) {
    return msg;
  }

  if (msg.subject_key || msg.body_key || msg.sender_key || msg.sender_role_key) {
    return msg;
  }

  if (msg.context?.delegated_renewal_report?.cases?.length) {
    return {
      ...msg,
      subject: resolve('be.msg.delegatedRenewals.subject', msg.subject, params),
      body: resolve('be.msg.delegatedRenewals.body', msg.body, params),
      sender: resolve('be.sender.assistantManager', msg.sender),
      sender_role: resolve('be.role.assistantManager', msg.sender_role),
    };
  }

  return {
    ...msg,
    subject: resolve('be.msg.delegatedRenewals.subject', msg.subject, params),
    body: resolveLegacyDelegatedRenewalsBody(msg.body),
    sender: resolve('be.sender.assistantManager', msg.sender),
    sender_role: resolve('be.role.assistantManager', msg.sender_role),
  };
}

/**
 * Resolve all translatable fields on a message, returning a copy with resolved strings.
 */
export function resolveMessage(msg: MessageData): MessageData {
  const inferredParams = msg.i18n_params ?? inferLegacyDelegatedRenewalsParams(msg);
  const p = resolveParamValues(inferredParams);
  const resolved = {
    ...msg,
    i18n_params: inferredParams,
    subject: resolve(msg.subject_key, msg.subject, p),
    body: resolve(msg.body_key, msg.body, p),
    sender: resolve(msg.sender_key, msg.sender, p),
    sender_role: resolve(msg.sender_role_key, msg.sender_role, p),
    actions: msg.actions.map((action) => resolveAction(action, msg.id, p)),
  };

  return resolveLegacyDelegatedRenewalsMessage(resolved, p);
}

/**
 * Resolve the label on a message action.
 */
export function resolveAction(
  action: MessageAction,
  messageId?: string,
  params?: Record<string, string>,
): MessageAction {
  const labelKey = action.label_key ?? inferPlayerEventActionLabelKey(messageId ?? '', action.id);

  if (typeof action.action_type === 'object' && 'ChooseOption' in action.action_type) {
    return {
      ...action,
      label: resolve(labelKey, action.label, params),
      action_type: {
        ChooseOption: {
          options: action.action_type.ChooseOption.options.map((option) =>
            resolveActionOption(option, messageId, params),
          ),
        },
      },
    };
  }

  return {
    ...action,
    label: resolve(labelKey, action.label, params),
  };
}

function resolveActionOption(
  option: MessageActionOption,
  messageId?: string,
  params?: Record<string, string>,
): MessageActionOption {
  const baseKey = inferPlayerEventOptionBaseKey(messageId ?? '', option.id);
  const labelKey = option.label_key ?? (baseKey ? `${baseKey}.label` : undefined);
  const descriptionKey = option.description_key ?? (baseKey ? `${baseKey}.description` : undefined);

  return {
    ...option,
    label: resolve(labelKey, option.label, params),
    description: resolve(descriptionKey, option.description, params),
  };
}

function normalizeNewsParams(article: NewsArticle): Record<string, string> | undefined {
  const params = article.i18n_params ? { ...article.i18n_params } : {};

  if (article.headline_key !== 'be.news.weeklyDigest.headline') {
    return Object.keys(params).length > 0 ? params : article.i18n_params;
  }

  if (!params.weekStart && params.weekLabel) {
    const weekLabelMatch = params.weekLabel.match(LEGACY_WEEKLY_DIGEST_WEEK_LABEL_RE);

    if (weekLabelMatch?.groups?.weekStart) {
      params.weekStart = weekLabelMatch.groups.weekStart;
    }
  }

  if (!params.weekStart) {
    const headlineMatch = article.headline.match(LEGACY_WEEKLY_DIGEST_HEADLINE_RE);

    if (headlineMatch?.groups?.weekStart) {
      params.weekStart = headlineMatch.groups.weekStart;
    }
  }

  delete params.weekLabel;

  return Object.keys(params).length > 0 ? params : undefined;
}

/**
 * Resolve all translatable fields on a news article, returning a copy with resolved strings.
 */
export function resolveNewsArticle(article: NewsArticle): NewsArticle {
  const p = normalizeNewsParams(article);
  return {
    ...article,
    i18n_params: p,
    headline: resolve(article.headline_key, article.headline, p),
    body: resolve(article.body_key, article.body, p),
    source: resolve(article.source_key, article.source, p),
  };
}

/**
 * Resolve a board objective description from its structured type and target.
 */
export function resolveBoardObjective(objective: BoardObjective): BoardObjective {
  const descriptionKey = `boardObjectives.objective.${objective.objective_type}`;
  const params = { target: String(objective.target) };

  return {
    ...objective,
    description: resolve(descriptionKey, boardObjectiveFallback(objective), params),
  };
}
