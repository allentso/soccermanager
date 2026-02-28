import { useState } from "react";
import { GameStateData, NewsArticle } from "../store/gameStore";
import { getTeamName } from "../lib/helpers";
import { Newspaper, Trophy, BarChart3, TrendingUp, FileText, Filter, ChevronDown, ChevronUp } from "lucide-react";

const CATEGORY_META: Record<string, { label: string; icon: React.ReactNode; color: string }> = {
  MatchReport:      { label: "Match Report",      icon: <Newspaper className="w-4 h-4" />,   color: "text-primary-500" },
  LeagueRoundup:    { label: "League Roundup",     icon: <Trophy className="w-4 h-4" />,      color: "text-accent-500" },
  StandingsUpdate:  { label: "Standings",          icon: <BarChart3 className="w-4 h-4" />,   color: "text-blue-500" },
  TransferRumour:   { label: "Transfer",           icon: <TrendingUp className="w-4 h-4" />,  color: "text-purple-500" },
  InjuryNews:       { label: "Injury",             icon: <FileText className="w-4 h-4" />,    color: "text-red-500" },
  SeasonPreview:    { label: "Season Preview",     icon: <FileText className="w-4 h-4" />,    color: "text-emerald-500" },
  Editorial:        { label: "Editorial",          icon: <FileText className="w-4 h-4" />,    color: "text-gray-500" },
  ManagerialChange: { label: "Managerial",         icon: <FileText className="w-4 h-4" />,    color: "text-orange-500" },
};

interface NewsTabProps {
  gameState: GameStateData;
  onSelectTeam?: (id: string) => void;
}

export default function NewsTab({ gameState, onSelectTeam }: NewsTabProps) {
  const [filterCategory, setFilterCategory] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [showFilters, setShowFilters] = useState(false);

  const news = gameState.news || [];
  const sortedNews = [...news].sort((a, b) => b.date.localeCompare(a.date));

  const categories = Array.from(new Set(sortedNews.map(n => n.category)));

  const filtered = filterCategory
    ? sortedNews.filter(n => n.category === filterCategory)
    : sortedNews;

  return (
    <div className="flex flex-col gap-5">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-heading font-bold uppercase tracking-wider text-gray-800 dark:text-gray-100">
            News Feed
          </h2>
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
            {filtered.length} article{filtered.length !== 1 ? "s" : ""}
          </p>
        </div>
        <button
          onClick={() => setShowFilters(!showFilters)}
          className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-heading font-bold uppercase tracking-wider transition-colors ${
            filterCategory
              ? "bg-primary-500/10 text-primary-500"
              : "bg-gray-100 dark:bg-navy-700 text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300"
          }`}
        >
          <Filter className="w-3.5 h-3.5" />
          {filterCategory ? CATEGORY_META[filterCategory]?.label || filterCategory : "Filter"}
        </button>
      </div>

      {/* Filter pills */}
      {showFilters && (
        <div className="flex flex-wrap gap-2">
          <button
            onClick={() => { setFilterCategory(null); setShowFilters(false); }}
            className={`px-3 py-1 rounded-full text-xs font-heading font-bold uppercase tracking-wider transition-colors ${
              !filterCategory
                ? "bg-primary-500 text-white"
                : "bg-gray-100 dark:bg-navy-700 text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-navy-600"
            }`}
          >
            All
          </button>
          {categories.map(cat => {
            const meta = CATEGORY_META[cat];
            return (
              <button
                key={cat}
                onClick={() => { setFilterCategory(cat); setShowFilters(false); }}
                className={`px-3 py-1 rounded-full text-xs font-heading font-bold uppercase tracking-wider transition-colors ${
                  filterCategory === cat
                    ? "bg-primary-500 text-white"
                    : "bg-gray-100 dark:bg-navy-700 text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-navy-600"
                }`}
              >
                {meta?.label || cat}
              </button>
            );
          })}
        </div>
      )}

      {/* News articles */}
      {filtered.length === 0 ? (
        <div className="text-center py-16">
          <Newspaper className="w-12 h-12 text-gray-300 dark:text-navy-600 mx-auto mb-3" />
          <p className="text-gray-500 dark:text-gray-400 text-sm">No news articles yet.</p>
          <p className="text-gray-400 dark:text-gray-500 text-xs mt-1">News will appear as the season progresses.</p>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          {filtered.map(article => (
            <ArticleCard
              key={article.id}
              article={article}
              gameState={gameState}
              expanded={expandedId === article.id}
              onToggle={() => setExpandedId(expandedId === article.id ? null : article.id)}
              onSelectTeam={onSelectTeam}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function ArticleCard({
  article,
  gameState,
  expanded,
  onToggle,
  onSelectTeam,
}: {
  article: NewsArticle;
  gameState: GameStateData;
  expanded: boolean;
  onToggle: () => void;
  onSelectTeam?: (id: string) => void;
}) {
  const meta = CATEGORY_META[article.category] || { label: article.category, icon: <FileText className="w-4 h-4" />, color: "text-gray-500" };
  const dateStr = new Date(article.date).toLocaleDateString(undefined, { month: "short", day: "numeric" });

  return (
    <div className="bg-white dark:bg-navy-800 rounded-xl border border-gray-200 dark:border-navy-700 shadow-sm overflow-hidden transition-all">
      {/* Header — always visible */}
      <button
        onClick={onToggle}
        className="w-full text-left px-5 py-4 flex items-start gap-3 hover:bg-gray-50 dark:hover:bg-navy-700/50 transition-colors"
      >
        <div className={`mt-0.5 flex-shrink-0 ${meta.color}`}>{meta.icon}</div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className={`text-[10px] font-heading font-bold uppercase tracking-widest ${meta.color}`}>
              {meta.label}
            </span>
            <span className="text-[10px] text-gray-400 dark:text-gray-500">{dateStr}</span>
          </div>
          <h3 className="text-sm font-heading font-bold text-gray-900 dark:text-white leading-snug">
            {article.headline}
          </h3>

          {/* Match score badge */}
          {article.match_score && (
            <div className="flex items-center gap-2 mt-2">
              <span className="text-xs font-medium text-gray-700 dark:text-gray-300">
                {getTeamName(gameState.teams, article.match_score.home_team_id)}
              </span>
              <span className="text-xs font-heading font-bold text-primary-500 bg-primary-500/10 px-2 py-0.5 rounded">
                {article.match_score.home_goals} - {article.match_score.away_goals}
              </span>
              <span className="text-xs font-medium text-gray-700 dark:text-gray-300">
                {getTeamName(gameState.teams, article.match_score.away_team_id)}
              </span>
            </div>
          )}
        </div>
        <div className="flex-shrink-0 mt-1 text-gray-400 dark:text-gray-500">
          {expanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
        </div>
      </button>

      {/* Expanded body */}
      {expanded && (
        <div className="px-5 pb-4 border-t border-gray-100 dark:border-navy-700">
          <p className="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-line leading-relaxed mt-3">
            {article.body}
          </p>

          {/* Team links */}
          {article.team_ids.length > 0 && onSelectTeam && (
            <div className="flex flex-wrap gap-2 mt-3">
              {article.team_ids.map(tid => (
                <button
                  key={tid}
                  onClick={(e) => { e.stopPropagation(); onSelectTeam(tid); }}
                  className="text-[10px] font-heading font-bold uppercase tracking-wider text-primary-500 hover:text-primary-600 dark:hover:text-primary-400 bg-primary-500/5 hover:bg-primary-500/10 px-2 py-1 rounded-md transition-colors"
                >
                  {getTeamName(gameState.teams, tid)}
                </button>
              ))}
            </div>
          )}

          <p className="text-[10px] text-gray-400 dark:text-gray-600 mt-3 font-heading uppercase tracking-widest">
            — {article.source}
          </p>
        </div>
      )}
    </div>
  );
}
