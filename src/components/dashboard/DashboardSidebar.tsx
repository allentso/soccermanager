import { useTranslation } from "react-i18next";
import { Users, Calendar as CalendarIcon, Mail, Settings, Briefcase, Trophy, TrendingUp, Crosshair, Dumbbell, DollarSign, Eye, User, UsersRound, Building2, UserCog, Newspaper, LogOut, GraduationCap } from "lucide-react";

interface DashboardSidebarProps {
  activeTab: string;
  onNavClick: (tab: string) => void;
  unreadMessagesCount: number;
  managerName: string | null;
  teamName: string | null;
  onNavigateSettings: () => void;
  onExitClick: () => void;
}

function NavItem({ icon, label, active, badge, onClick }: { icon: React.ReactNode; label: string; active?: boolean; badge?: number; onClick?: () => void }) {
  return (
    <button 
      onClick={onClick}
      className={`w-full flex items-center justify-between p-3 rounded-lg transition-all duration-200 ${
        active 
          ? 'bg-gradient-to-r from-primary-500 to-primary-600 text-white shadow-md shadow-primary-500/20' 
          : 'text-gray-400 hover:text-white hover:bg-white/5'
      }`}
    >
      <div className="flex items-center gap-3">
        <div className="[&>svg]:w-5 [&>svg]:h-5">{icon}</div>
        <span className="font-heading font-semibold text-sm uppercase tracking-wider">{label}</span>
      </div>
      {badge !== undefined && badge > 0 && (
        <span className="bg-primary-500 text-white text-xs font-bold px-2 py-0.5 rounded-full min-w-[1.25rem] text-center">
          {badge}
        </span>
      )}
    </button>
  );
}

export default function DashboardSidebar({ activeTab, onNavClick, unreadMessagesCount, managerName, teamName, onNavigateSettings, onExitClick }: DashboardSidebarProps) {
  const { t } = useTranslation();

  return (
    <aside className="w-64 bg-navy-800 dark:bg-navy-800 border-r border-navy-700 text-white flex flex-col flex-shrink-0">
      {/* Brand */}
      <div className="p-5 border-b border-navy-700">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 flex items-center justify-center">
            <img src="../../openfootball.svg" alt="Logo" className="w-8 h-8" />
          </div>
          <div>
            <h1 className="text-sm font-heading font-bold text-white uppercase tracking-wider">OpenFoot</h1>
            <h1 className="text-xs font-heading text-accent-400 uppercase tracking-wider">Manager</h1>
          </div>
        </div>
        <div className="mt-3 pt-3 border-t border-navy-700">
          <p className="text-xs text-gray-400 uppercase tracking-wider">{t('dashboard.manager')}</p>
          <p className="text-sm font-semibold text-white mt-0.5">{managerName}</p>
          {teamName && <p className="text-xs text-primary-400 mt-0.5">{teamName}</p>}
        </div>
      </div>
      
      {/* Navigation */}
      <nav className="flex-1 py-4 px-3 flex flex-col gap-1 overflow-y-auto">
        <NavItem icon={<Briefcase />} label={t('dashboard.home')} active={activeTab === "Home"} onClick={() => onNavClick("Home")} />
        <NavItem icon={<Mail />} label={t('dashboard.inbox')} badge={unreadMessagesCount > 0 ? unreadMessagesCount : undefined} active={activeTab === "Inbox"} onClick={() => onNavClick("Inbox")} />
        <NavItem icon={<User />} label={t('dashboard.manager')} active={activeTab === "Manager"} onClick={() => onNavClick("Manager")} />

        <p className="text-[10px] text-gray-500 uppercase tracking-widest font-heading px-3 pt-3 pb-1">{t('dashboard.sectionClub')}</p>
        <NavItem icon={<Users />} label={t('dashboard.squad')} active={activeTab === "Squad"} onClick={() => onNavClick("Squad")} />
        <NavItem icon={<Crosshair />} label={t('dashboard.tactics')} active={activeTab === "Tactics"} onClick={() => onNavClick("Tactics")} />
        <NavItem icon={<Dumbbell />} label={t('dashboard.training')} active={activeTab === "Training"} onClick={() => onNavClick("Training")} />
        <NavItem icon={<UserCog />} label={t('dashboard.staff')} active={activeTab === "Staff"} onClick={() => onNavClick("Staff")} />
        <NavItem icon={<Eye />} label={t('dashboard.scouting')} active={activeTab === "Scouting"} onClick={() => onNavClick("Scouting")} />
        <NavItem icon={<GraduationCap />} label={t('dashboard.youthAcademy')} active={activeTab === "Youth"} onClick={() => onNavClick("Youth")} />
        <NavItem icon={<DollarSign />} label={t('dashboard.finances')} active={activeTab === "Finances"} onClick={() => onNavClick("Finances")} />
        <NavItem icon={<TrendingUp />} label={t('dashboard.transfers')} active={activeTab === "Transfers"} onClick={() => onNavClick("Transfers")} />

        <p className="text-[10px] text-gray-500 uppercase tracking-widest font-heading px-3 pt-3 pb-1">{t('dashboard.sectionWorld')}</p>
        <NavItem icon={<UsersRound />} label={t('dashboard.players')} active={activeTab === "Players"} onClick={() => onNavClick("Players")} />
        <NavItem icon={<Building2 />} label={t('dashboard.teams')} active={activeTab === "Teams"} onClick={() => onNavClick("Teams")} />
        <NavItem icon={<Trophy />} label={t('dashboard.tournaments')} active={activeTab === "Tournaments"} onClick={() => onNavClick("Tournaments")} />
        <NavItem icon={<CalendarIcon />} label={t('dashboard.schedule')} active={activeTab === "Schedule"} onClick={() => onNavClick("Schedule")} />
        <NavItem icon={<Newspaper />} label={t('dashboard.news')} active={activeTab === "News"} onClick={() => onNavClick("News")} />
      </nav>
      
      {/* Settings & Exit */}
      <div className="p-3 border-t border-navy-700 flex flex-col gap-1">
        <button 
          onClick={onNavigateSettings}
          className="flex items-center gap-3 w-full p-3 hover:bg-white/5 rounded-lg transition-colors text-gray-500 hover:text-gray-300"
        >
          <Settings className="w-5 h-5" />
          <span className="font-heading text-sm uppercase tracking-wider">{t('dashboard.settings')}</span>
        </button>
        <button 
          onClick={onExitClick}
          className="flex items-center gap-3 w-full p-3 hover:bg-red-500/10 rounded-lg transition-colors text-gray-500 hover:text-red-400"
        >
          <LogOut className="w-5 h-5" />
          <span className="font-heading text-sm uppercase tracking-wider">{t('dashboard.exitToMenu')}</span>
        </button>
      </div>
    </aside>
  );
}
