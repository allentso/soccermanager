import { GameStateData } from "../store/gameStore";
import { Card, CardHeader, CardBody, Badge, ProgressBar } from "./ui";
import { getTeamName, getTeamShort, findNextFixture, formatMatchDate } from "../lib/helpers";

interface HomeTabProps {
  gameState: GameStateData;
}

export default function HomeTab({ gameState }: HomeTabProps) {
  return (
    <div className="max-w-6xl mx-auto grid grid-cols-1 md:grid-cols-3 gap-5">
      
      {/* Next Match Card */}
      <Card accent="primary" className="md:col-span-2">
        <CardHeader>Next Match</CardHeader>
        <CardBody>
          <NextMatchDisplay gameState={gameState} />
        </CardBody>
      </Card>

      {/* Board Confidence */}
      <Card accent="accent">
        <CardHeader>Board Confidence</CardHeader>
        <CardBody>
          <div className="flex flex-col gap-4">
            <div>
              <div className="flex justify-between text-sm mb-2">
                <span className="font-medium text-gray-700 dark:text-gray-300">Overall Satisfaction</span>
                <span className="font-heading font-bold text-accent-600 dark:text-accent-400">Stable</span>
              </div>
              <ProgressBar value={50} variant="accent" size="md" showLabel />
            </div>
            <div>
              <div className="flex justify-between text-sm mb-2">
                <span className="font-medium text-gray-700 dark:text-gray-300">Financial Health</span>
                <span className="font-heading font-bold text-success-500 dark:text-success-400">Good</span>
              </div>
              <ProgressBar value={75} variant="success" size="md" showLabel />
            </div>
          </div>
        </CardBody>
      </Card>
      
      {/* Recent Messages */}
      <Card className="md:col-span-3">
        <CardHeader
          action={
            <button className="text-primary-500 dark:text-primary-400 text-xs font-heading font-bold uppercase tracking-wider hover:text-primary-600 dark:hover:text-primary-300 transition-colors">
              View All
            </button>
          }
        >
          Recent Messages
        </CardHeader>
        <CardBody className="p-0">
          <div className="divide-y divide-gray-100 dark:divide-navy-600">
            {gameState.messages?.length === 0 ? (
              <p className="text-gray-500 dark:text-gray-400 p-6">No recent messages.</p>
            ) : (
              gameState.messages?.map(message => (
                <div key={message.id} className={`flex gap-4 px-6 py-4 hover:bg-gray-50 dark:hover:bg-navy-600/50 cursor-pointer transition-colors ${!message.read ? 'border-l-4 border-l-primary-500' : 'border-l-4 border-l-transparent'}`}>
                  <div className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 font-heading font-bold text-sm ${
                    message.read 
                      ? 'bg-gray-100 dark:bg-navy-600 text-gray-400 dark:text-gray-500' 
                      : 'bg-primary-500/10 dark:bg-primary-500/20 text-primary-600 dark:text-primary-400'
                  }`}>
                    {message.sender.charAt(0)}
                  </div>
                  <div className="min-w-0 flex-1">
                    <h4 className={`font-semibold text-sm ${message.read ? 'text-gray-500 dark:text-gray-400' : 'text-gray-900 dark:text-gray-100'}`}>{message.subject}</h4>
                    <p className={`text-xs truncate mt-0.5 ${message.read ? 'text-gray-400 dark:text-gray-500' : 'text-gray-600 dark:text-gray-300'}`}>
                      {message.body}
                    </p>
                    <span className="text-xs text-gray-400 dark:text-gray-500 mt-1.5 block">
                      {new Date(message.date).toLocaleDateString()} — {message.sender}
                    </span>
                  </div>
                </div>
              ))
            )}
          </div>
        </CardBody>
      </Card>
    </div>
  );
}

function NextMatchDisplay({ gameState }: { gameState: GameStateData }) {
  const userTeamId = gameState.manager.team_id;
  const league = gameState.league;

  if (!userTeamId || !league) {
    return <p className="text-gray-500 dark:text-gray-400 text-sm text-center py-4">No league schedule yet.</p>;
  }

  const nextFixture = findNextFixture(league.fixtures, userTeamId);
  if (!nextFixture) {
    return <p className="text-gray-500 dark:text-gray-400 text-sm text-center py-4">Season complete — no upcoming matches.</p>;
  }

  const isHome = nextFixture.home_team_id === userTeamId;
  const opponentId = isHome ? nextFixture.away_team_id : nextFixture.home_team_id;

  return (
    <div className="flex items-center justify-between py-6 px-4 bg-gray-50 dark:bg-navy-800 rounded-lg border border-gray-100 dark:border-navy-600 transition-colors">
      <div className="text-center flex-1">
        <div className="w-16 h-16 bg-gradient-to-br from-primary-500/20 to-primary-600/20 dark:from-primary-500/10 dark:to-primary-600/10 rounded-full mx-auto mb-2 flex items-center justify-center font-heading font-bold text-primary-600 dark:text-primary-400 text-lg border-2 border-primary-200 dark:border-primary-800 transition-colors">
          {getTeamShort(gameState.teams, nextFixture.home_team_id)}
        </div>
        <p className={`font-heading font-bold uppercase tracking-wide text-sm ${isHome ? "text-primary-600 dark:text-primary-400" : "text-gray-500 dark:text-gray-400"}`}>
          {getTeamName(gameState.teams, nextFixture.home_team_id)}
        </p>
      </div>

      <div className="text-center px-4 flex flex-col items-center gap-1.5">
        <span className="font-heading font-bold text-2xl text-gray-300 dark:text-navy-600">VS</span>
        <Badge variant="neutral">{formatMatchDate(nextFixture.date)}</Badge>
        <span className="text-xs text-gray-400 dark:text-gray-500">Matchday {nextFixture.matchday}</span>
        <Badge variant={isHome ? "success" : "accent"} size="sm">{isHome ? "Home" : "Away"}</Badge>
      </div>

      <div className="text-center flex-1">
        <div className="w-16 h-16 bg-gray-200 dark:bg-navy-600 rounded-full mx-auto mb-2 flex items-center justify-center font-heading font-bold text-gray-500 dark:text-gray-400 text-lg border-2 border-gray-300 dark:border-navy-600 transition-colors">
          {getTeamShort(gameState.teams, opponentId)}
        </div>
        <p className={`font-heading font-bold uppercase tracking-wide text-sm ${!isHome ? "text-primary-600 dark:text-primary-400" : "text-gray-500 dark:text-gray-400"}`}>
          {getTeamName(gameState.teams, opponentId)}
        </p>
      </div>
    </div>
  );
}
