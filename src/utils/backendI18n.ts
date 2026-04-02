import i18n from '../i18n';
import type {
  MessageActionOption,
  MessageData,
  MessageAction,
  NewsArticle,
  BoardObjective,
} from '../store/gameStore';
import {
  inferLegacyDelegatedRenewalsParams,
  normalizeNewsParams,
  resolveLegacyDelegatedRenewalsMessage,
} from './backendI18n.legacy';

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

  return resolveLegacyDelegatedRenewalsMessage(resolved, resolve, p);
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
