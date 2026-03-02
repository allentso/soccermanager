import { useState } from "react";
import { GameStateData, NewsArticle } from "../store/gameStore";
import { getTeamName } from "../lib/helpers";
import { Newspaper, Trophy, BarChart3, TrendingUp, FileText, ArrowLeft, Clock } from "lucide-react";
import { useTranslation } from "react-i18next";
import { resolveNewsArticle } from "../utils/backendI18n";

const CAT_ICONS: Record<string, React.ReactNode> = {
  MatchReport: <Newspaper className="w-4 h-4" />, LeagueRoundup: <Trophy className="w-4 h-4" />,
  StandingsUpdate: <BarChart3 className="w-4 h-4" />, TransferRumour: <TrendingUp className="w-4 h-4" />,
  InjuryNews: <FileText className="w-4 h-4" />, SeasonPreview: <FileText className="w-4 h-4" />,
  Editorial: <FileText className="w-4 h-4" />, ManagerialChange: <FileText className="w-4 h-4" />,
};
const CAT_COLORS: Record<string, string> = {
  MatchReport: "text-primary-500", LeagueRoundup: "text-accent-500", StandingsUpdate: "text-blue-500",
  TransferRumour: "text-purple-500", InjuryNews: "text-red-500", SeasonPreview: "text-emerald-500",
  Editorial: "text-gray-500", ManagerialChange: "text-orange-500",
};
const CAT_BG: Record<string, string> = {
  MatchReport: "bg-primary-500/10", LeagueRoundup: "bg-accent-500/10", StandingsUpdate: "bg-blue-500/10",
  TransferRumour: "bg-purple-500/10", InjuryNews: "bg-red-500/10", SeasonPreview: "bg-emerald-500/10",
  Editorial: "bg-gray-500/10", ManagerialChange: "bg-orange-500/10",
};

interface NewsTabProps {
  gameState: GameStateData;
  onSelectTeam?: (id: string) => void;
}

function formatNewsDate(dateStr: string) {
  return new Date(dateStr).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
}

export default function NewsTab({ gameState, onSelectTeam }: NewsTabProps) {
  const { t } = useTranslation();
  const [filterCategory, setFilterCategory] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const news = (gameState.news || []).map(resolveNewsArticle);
  const sortedNews = [...news].sort((a, b) => b.date.localeCompare(a.date));
  const categories = Array.from(new Set(sortedNews.map(n => n.category)));
  const filtered = filterCategory ? sortedNews.filter(n => n.category === filterCategory) : sortedNews;
  const selectedArticle = selectedId ? filtered.find(a => a.id === selectedId) || sortedNews.find(a => a.id === selectedId) : null;

  // Empty state
  if (sortedNews.length === 0) {
    return (
      <div className="text-center py-16">
        <Newspaper className="w-12 h-12 text-gray-300 dark:text-navy-600 mx-auto mb-3" />
        <p className="text-gray-500 dark:text-gray-400 text-sm">{t('news.noNews')}</p>
        <p className="text-gray-400 dark:text-gray-500 text-xs mt-1">{t('news.newsWillAppear')}</p>
      </div>
    );
  }

  // Article detail view (replaces list on mobile, shown inline on desktop)
  if (selectedArticle) {
    return <ArticleDetail article={selectedArticle} gameState={gameState} onBack={() => setSelectedId(null)} onSelectTeam={onSelectTeam} />;
  }

  return (
    <div className="max-w-6xl mx-auto flex flex-col gap-5">
      {/* Category filter pills */}
      <div className="flex items-center gap-2 flex-wrap">
        <button
          onClick={() => setFilterCategory(null)}
          className={`px-3 py-1.5 rounded-full text-xs font-heading font-bold uppercase tracking-wider transition-colors ${
            !filterCategory
              ? "bg-primary-500 text-white shadow-sm"
              : "bg-gray-100 dark:bg-navy-700 text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-navy-600"
          }`}
        >
          {t('common.all')}
        </button>
        {categories.map(cat => (
            <button
              key={cat}
              onClick={() => setFilterCategory(filterCategory === cat ? null : cat)}
              className={`px-3 py-1.5 rounded-full text-xs font-heading font-bold uppercase tracking-wider transition-colors ${
                filterCategory === cat
                  ? "bg-primary-500 text-white shadow-sm"
                  : "bg-gray-100 dark:bg-navy-700 text-gray-500 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-navy-600"
              }`}
            >
              {t(`news.categories.${cat}`)}
            </button>
        ))}
        <span className="text-xs text-gray-400 dark:text-gray-500 ml-auto">
          {t('news.nArticles', { count: filtered.length })}
        </span>
      </div>

      {/* Hero article — latest/featured */}
      {filtered.length > 0 && (
        <HeroArticle article={filtered[0]} gameState={gameState} onSelect={() => setSelectedId(filtered[0].id)} onSelectTeam={onSelectTeam} />
      )}

      {/* Article grid */}
      {filtered.length > 1 && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtered.slice(1).map(article => (
            <ArticleCard key={article.id} article={article} gameState={gameState} onSelect={() => setSelectedId(article.id)} />
          ))}
        </div>
      )}
    </div>
  );
}

function HeroArticle({ article, gameState, onSelect, onSelectTeam }: {
  article: NewsArticle; gameState: GameStateData; onSelect: () => void; onSelectTeam?: (id: string) => void;
}) {
  const { t } = useTranslation();
  const meta = { icon: CAT_ICONS[article.category] || <FileText className="w-4 h-4" />, color: CAT_COLORS[article.category] || "text-gray-500", bg: CAT_BG[article.category] || "bg-gray-500/10", label: t(`news.categories.${article.category}`) };

  return (
    <button onClick={onSelect} className="w-full text-left bg-white dark:bg-navy-800 rounded-xl border border-gray-200 dark:border-navy-700 shadow-sm overflow-hidden hover:shadow-md dark:hover:border-navy-600 transition-all group">
      <div className="p-6">
        <div className="flex items-center gap-2 mb-3">
          <span className={`inline-flex items-center gap-1.5 text-[10px] font-heading font-bold uppercase tracking-widest px-2.5 py-1 rounded-full ${meta.color} ${meta.bg}`}>
            {meta.icon}
            {meta.label}
          </span>
          <span className="text-[10px] text-gray-400 dark:text-gray-500 flex items-center gap-1">
            <Clock className="w-3 h-3" />
            {formatNewsDate(article.date)}
          </span>
        </div>

        <h2 className="text-xl font-heading font-bold text-gray-900 dark:text-white leading-tight mb-3 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors">
          {article.headline}
        </h2>

        {/* Match score badge */}
        {article.match_score && (
          <div className="flex items-center gap-3 mb-3 p-3 bg-gray-50 dark:bg-navy-700/50 rounded-lg">
            <span className="text-sm font-heading font-bold text-gray-700 dark:text-gray-300">
              {getTeamName(gameState.teams, article.match_score.home_team_id)}
            </span>
            <span className="text-lg font-heading font-bold text-primary-500 bg-primary-500/10 px-3 py-1 rounded-lg">
              {article.match_score.home_goals} – {article.match_score.away_goals}
            </span>
            <span className="text-sm font-heading font-bold text-gray-700 dark:text-gray-300">
              {getTeamName(gameState.teams, article.match_score.away_team_id)}
            </span>
          </div>
        )}

        <p className="text-sm text-gray-600 dark:text-gray-400 line-clamp-3 leading-relaxed">
          {article.body}
        </p>

        <div className="flex items-center justify-between mt-4 pt-3 border-t border-gray-100 dark:border-navy-700">
          <p className="text-[10px] text-gray-400 dark:text-gray-600 font-heading uppercase tracking-widest">
            — {article.source}
          </p>
          {article.team_ids.length > 0 && onSelectTeam && (
            <div className="flex gap-1.5">
              {article.team_ids.slice(0, 3).map(tid => (
                <span
                  key={tid}
                  onClick={(e) => { e.stopPropagation(); onSelectTeam(tid); }}
                  className="text-[10px] font-heading font-bold uppercase tracking-wider text-primary-500 hover:text-primary-600 dark:hover:text-primary-400 bg-primary-500/5 hover:bg-primary-500/10 px-2 py-0.5 rounded-md transition-colors cursor-pointer"
                >
                  {getTeamName(gameState.teams, tid)}
                </span>
              ))}
            </div>
          )}
        </div>
      </div>
    </button>
  );
}

function ArticleCard({ article, gameState, onSelect }: {
  article: NewsArticle; gameState: GameStateData; onSelect: () => void;
}) {
  const { t } = useTranslation();
  const meta = { icon: CAT_ICONS[article.category] || <FileText className="w-4 h-4" />, color: CAT_COLORS[article.category] || "text-gray-500", bg: CAT_BG[article.category] || "bg-gray-500/10", label: t(`news.categories.${article.category}`) };

  return (
    <button onClick={onSelect} className="w-full text-left bg-white dark:bg-navy-800 rounded-xl border border-gray-200 dark:border-navy-700 shadow-sm overflow-hidden hover:shadow-md dark:hover:border-navy-600 transition-all group flex flex-col">
      <div className="p-4 flex-1 flex flex-col">
        <div className="flex items-center gap-2 mb-2">
          <span className={`inline-flex items-center gap-1 text-[9px] font-heading font-bold uppercase tracking-widest px-2 py-0.5 rounded-full ${meta.color} ${meta.bg}`}>
            {meta.icon}
            {meta.label}
          </span>
        </div>

        <h3 className="text-sm font-heading font-bold text-gray-900 dark:text-white leading-snug mb-2 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors">
          {article.headline}
        </h3>

        {article.match_score && (
          <div className="flex items-center gap-2 mb-2">
            <span className="text-xs font-medium text-gray-600 dark:text-gray-400">
              {getTeamName(gameState.teams, article.match_score.home_team_id)}
            </span>
            <span className="text-xs font-heading font-bold text-primary-500 bg-primary-500/10 px-1.5 py-0.5 rounded">
              {article.match_score.home_goals} – {article.match_score.away_goals}
            </span>
            <span className="text-xs font-medium text-gray-600 dark:text-gray-400">
              {getTeamName(gameState.teams, article.match_score.away_team_id)}
            </span>
          </div>
        )}

        <p className="text-xs text-gray-500 dark:text-gray-400 line-clamp-2 leading-relaxed flex-1">
          {article.body}
        </p>

        <div className="flex items-center justify-between mt-3 pt-2 border-t border-gray-100 dark:border-navy-700">
          <span className="text-[10px] text-gray-400 dark:text-gray-600 font-heading uppercase tracking-widest">
            {article.source}
          </span>
          <span className="text-[10px] text-gray-400 dark:text-gray-500 flex items-center gap-1">
            <Clock className="w-3 h-3" />
            {formatNewsDate(article.date)}
          </span>
        </div>
      </div>
    </button>
  );
}

function ArticleDetail({ article, gameState, onBack, onSelectTeam }: {
  article: NewsArticle; gameState: GameStateData; onBack: () => void; onSelectTeam?: (id: string) => void;
}) {
  const { t } = useTranslation();
  const meta = { icon: CAT_ICONS[article.category] || <FileText className="w-4 h-4" />, color: CAT_COLORS[article.category] || "text-gray-500", bg: CAT_BG[article.category] || "bg-gray-500/10", label: t(`news.categories.${article.category}`) };

  return (
    <div className="max-w-3xl mx-auto">
      <button onClick={onBack} className="flex items-center gap-1.5 text-xs font-heading font-bold uppercase tracking-wider text-gray-500 dark:text-gray-400 hover:text-primary-500 dark:hover:text-primary-400 mb-4 transition-colors">
        <ArrowLeft className="w-4 h-4" />
        {t('news.backToNews')}
      </button>

      <article className="bg-white dark:bg-navy-800 rounded-xl border border-gray-200 dark:border-navy-700 shadow-sm overflow-hidden">
        <div className="p-8">
          {/* Category + date */}
          <div className="flex items-center gap-3 mb-4">
            <span className={`inline-flex items-center gap-1.5 text-[10px] font-heading font-bold uppercase tracking-widest px-2.5 py-1 rounded-full ${meta.color} ${meta.bg}`}>
              {meta.icon}
              {meta.label}
            </span>
            <span className="text-xs text-gray-400 dark:text-gray-500 flex items-center gap-1">
              <Clock className="w-3.5 h-3.5" />
              {formatNewsDate(article.date)}
            </span>
          </div>

          {/* Headline */}
          <h1 className="text-2xl font-heading font-bold text-gray-900 dark:text-white leading-tight mb-4">
            {article.headline}
          </h1>

          {/* Match score */}
          {article.match_score && (
            <div className="flex items-center justify-center gap-4 mb-6 p-4 bg-gray-50 dark:bg-navy-700/50 rounded-xl">
              <div className="text-center">
                <p className="text-sm font-heading font-bold text-gray-700 dark:text-gray-300">
                  {getTeamName(gameState.teams, article.match_score.home_team_id)}
                </p>
              </div>
              <div className="text-2xl font-heading font-bold text-primary-500 bg-primary-500/10 px-4 py-2 rounded-xl">
                {article.match_score.home_goals} – {article.match_score.away_goals}
              </div>
              <div className="text-center">
                <p className="text-sm font-heading font-bold text-gray-700 dark:text-gray-300">
                  {getTeamName(gameState.teams, article.match_score.away_team_id)}
                </p>
              </div>
            </div>
          )}

          {/* Body */}
          <div className="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-line leading-relaxed">
            {article.body}
          </div>

          {/* Footer */}
          <div className="mt-6 pt-4 border-t border-gray-100 dark:border-navy-700 flex items-center justify-between">
            <p className="text-[10px] text-gray-400 dark:text-gray-600 font-heading uppercase tracking-widest">
              — {article.source}
            </p>
            {article.team_ids.length > 0 && onSelectTeam && (
              <div className="flex flex-wrap gap-2">
                {article.team_ids.map(tid => (
                  <button
                    key={tid}
                    onClick={() => onSelectTeam(tid)}
                    className="text-[10px] font-heading font-bold uppercase tracking-wider text-primary-500 hover:text-primary-600 dark:hover:text-primary-400 bg-primary-500/5 hover:bg-primary-500/10 px-2.5 py-1 rounded-md transition-colors"
                  >
                    {getTeamName(gameState.teams, tid)}
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      </article>
    </div>
  );
}
