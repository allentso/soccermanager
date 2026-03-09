import i18n from '../i18n';
import type {
  MessageData,
  MessageAction,
  NewsArticle,
  BoardObjective,
} from '../store/gameStore';

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

/**
 * Resolve all translatable fields on a message, returning a copy with resolved strings.
 */
export function resolveMessage(msg: MessageData): MessageData {
  const p = resolveParamValues(msg.i18n_params);
  return {
    ...msg,
    subject: resolve(msg.subject_key, msg.subject, p),
    body: resolve(msg.body_key, msg.body, p),
    sender: resolve(msg.sender_key, msg.sender, p),
    sender_role: resolve(msg.sender_role_key, msg.sender_role, p),
    actions: msg.actions.map(resolveAction),
  };
}

/**
 * Resolve the label on a message action.
 */
export function resolveAction(action: MessageAction): MessageAction {
  return {
    ...action,
    label: resolve(action.label_key, action.label),
  };
}

/**
 * Resolve all translatable fields on a news article, returning a copy with resolved strings.
 */
export function resolveNewsArticle(article: NewsArticle): NewsArticle {
  const p = article.i18n_params;
  return {
    ...article,
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
