import { useState } from "react";
import { GameStateData } from "../../store/gameStore";
import { MatchSnapshot } from "./types";
import { Badge } from "../ui";
import { ChevronRight, Mic, MessageSquare } from "lucide-react";

interface PressConferenceProps {
  snapshot: MatchSnapshot;
  gameState: GameStateData;
  userSide: "Home" | "Away";
  onFinish: () => void;
}

interface PressQuestion {
  id: string;
  journalist: string;
  outlet: string;
  question: string;
  responses: PressResponse[];
}

interface PressResponse {
  id: string;
  tone: string;
  text: string;
}

function generateQuestions(snapshot: MatchSnapshot, userSide: "Home" | "Away"): PressQuestion[] {
  const userScore = userSide === "Home" ? snapshot.home_score : snapshot.away_score;
  const oppScore = userSide === "Home" ? snapshot.away_score : snapshot.home_score;
  const oppName = userSide === "Home" ? snapshot.away_team.name : snapshot.home_team.name;
  const isWin = userScore > oppScore;
  const isLoss = userScore < oppScore;

  const questions: PressQuestion[] = [];

  // Result question
  questions.push({
    id: "result",
    journalist: "David Thomson",
    outlet: "Sports Daily",
    question: isWin
      ? `A strong result today, ${userScore}-${oppScore} against ${oppName}. How pleased are you with the performance?`
      : isLoss
        ? `A tough result today, losing ${userScore}-${oppScore} to ${oppName}. What went wrong out there?`
        : `A ${userScore}-${oppScore} draw against ${oppName}. Is that a fair result?`,
    responses: isWin ? [
      { id: "humble", tone: "Humble", text: "The players worked hard. We prepared well and executed the game plan." },
      { id: "confident", tone: "Confident", text: "We were the better side from start to finish. A deserved result." },
      { id: "deflect", tone: "Deflect", text: "It's just three points. We move on to the next one." },
    ] : isLoss ? [
      { id: "accept", tone: "Accept", text: "We weren't good enough today. We have to look at what went wrong." },
      { id: "defiant", tone: "Defiant", text: "I don't think we deserved to lose. We created enough chances." },
      { id: "deflect", tone: "Deflect", text: "I'd rather not dwell on it. We'll be ready for the next match." },
    ] : [
      { id: "fair", tone: "Fair", text: "It was a fair result. Both teams had chances." },
      { id: "frustrated", tone: "Frustrated", text: "We should have won that. Too many missed opportunities." },
      { id: "positive", tone: "Positive", text: "A point is a point. There are positives to take from today." },
    ],
  });

  // Tactical question
  questions.push({
    id: "tactics",
    journalist: "Sarah Mitchell",
    outlet: "Football Weekly",
    question: "Can you talk us through your tactical approach today?",
    responses: [
      { id: "detailed", tone: "Detailed", text: "We set up to control the midfield and use our width. I think the shape worked well." },
      { id: "brief", tone: "Brief", text: "We had a plan and the players executed it. That's all that matters." },
      { id: "evasive", tone: "Evasive", text: "I'd rather not give away too much. Every team has their secrets." },
    ],
  });

  // Looking ahead
  questions.push({
    id: "ahead",
    journalist: "Mark Williams",
    outlet: "The Athletic",
    question: "What's your focus going into the next match?",
    responses: [
      { id: "focused", tone: "Focused", text: "Recovery first, then preparation. We take it one game at a time." },
      { id: "ambitious", tone: "Ambitious", text: "We want to keep building momentum. The target is clear." },
      { id: "curt", tone: "Curt", text: "Next question, please. We'll worry about that when it comes." },
    ],
  });

  return questions;
}

export default function PressConference({ snapshot, gameState: _gameState, userSide, onFinish }: PressConferenceProps) {
  const [questions] = useState(() => generateQuestions(snapshot, userSide));
  const [currentIdx, setCurrentIdx] = useState(0);
  const [answers, setAnswers] = useState<Record<string, string>>({});

  const currentQ = questions[currentIdx];
  const isLastQuestion = currentIdx === questions.length - 1;
  const hasAnswered = currentQ ? !!answers[currentQ.id] : false;

  const handleAnswer = (responseId: string) => {
    if (!currentQ) return;
    setAnswers(prev => ({ ...prev, [currentQ.id]: responseId }));
  };

  const handleNext = () => {
    if (isLastQuestion) {
      onFinish();
    } else {
      setCurrentIdx(prev => prev + 1);
    }
  };

  const userTeamName = userSide === "Home" ? snapshot.home_team.name : snapshot.away_team.name;

  return (
    <div className="min-h-screen bg-navy-900 text-white flex flex-col">
      {/* Header */}
      <header className="bg-gradient-to-r from-navy-800 via-navy-900 to-navy-800 border-b border-navy-700 px-4 py-6">
        <div className="max-w-3xl mx-auto text-center">
          <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-navy-700 rounded-full mb-3">
            <Mic className="w-4 h-4 text-accent-400" />
            <span className="font-heading font-bold text-xs uppercase tracking-widest text-gray-300">
              Press Conference
            </span>
          </div>
          <p className="text-sm text-gray-500">
            Post-match press conference — {userTeamName}
          </p>
          <div className="flex items-center justify-center gap-1 mt-3">
            {questions.map((_, i) => (
              <div
                key={i}
                className={`w-8 h-1 rounded-full transition-colors ${
                  i < currentIdx ? "bg-primary-500" :
                  i === currentIdx ? "bg-primary-400" :
                  "bg-navy-700"
                }`}
              />
            ))}
          </div>
        </div>
      </header>

      {/* Main content */}
      <div className="flex-1 flex items-center justify-center p-6">
        {currentQ && (
          <div className="max-w-2xl w-full">
            {/* Journalist */}
            <div className="flex items-start gap-4 mb-8">
              <div className="w-12 h-12 rounded-full bg-navy-700 flex items-center justify-center flex-shrink-0">
                <MessageSquare className="w-5 h-5 text-gray-400" />
              </div>
              <div>
                <div className="flex items-center gap-2 mb-1">
                  <span className="font-heading font-bold text-sm text-gray-200">{currentQ.journalist}</span>
                  <Badge variant="neutral" size="sm">{currentQ.outlet}</Badge>
                </div>
                <p className="text-lg text-gray-300 leading-relaxed italic">
                  "{currentQ.question}"
                </p>
              </div>
            </div>

            {/* Responses */}
            <div className="flex flex-col gap-3 ml-16">
              {currentQ.responses.map(r => {
                const isSelected = answers[currentQ.id] === r.id;
                return (
                  <button
                    key={r.id}
                    onClick={() => handleAnswer(r.id)}
                    disabled={hasAnswered}
                    className={`p-4 rounded-xl text-left transition-all ${
                      isSelected
                        ? "bg-primary-500/20 ring-2 ring-primary-500/50"
                        : hasAnswered
                          ? "bg-navy-800/50 opacity-40"
                          : "bg-navy-800 hover:bg-navy-700 border border-navy-700"
                    }`}
                  >
                    <div className="flex items-center gap-2 mb-1">
                      <Badge
                        variant={isSelected ? "primary" : "neutral"}
                        size="sm"
                      >
                        {r.tone}
                      </Badge>
                    </div>
                    <p className={`text-sm ${isSelected ? "text-gray-200" : "text-gray-400"}`}>
                      "{r.text}"
                    </p>
                  </button>
                );
              })}
            </div>

            {/* Next button */}
            {hasAnswered && (
              <div className="flex justify-end mt-6 ml-16">
                <button
                  onClick={handleNext}
                  className="flex items-center gap-2 px-6 py-3 bg-gradient-to-r from-primary-500 to-primary-600 hover:from-primary-600 hover:to-primary-700 rounded-xl font-heading font-bold uppercase tracking-wider text-sm text-white shadow-lg shadow-primary-500/20 transition-all"
                >
                  {isLastQuestion ? "Leave Conference" : "Next Question"}
                  <ChevronRight className="w-4 h-4" />
                </button>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Skip button */}
      <footer className="bg-navy-800 border-t border-navy-700 px-6 py-3">
        <div className="max-w-3xl mx-auto flex justify-end">
          <button
            onClick={onFinish}
            className="text-xs font-heading uppercase tracking-wider text-gray-600 hover:text-gray-400 transition-colors"
          >
            Skip Conference →
          </button>
        </div>
      </footer>
    </div>
  );
}
