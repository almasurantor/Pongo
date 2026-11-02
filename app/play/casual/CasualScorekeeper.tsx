'use client';

import { useState } from 'react';

export default function CasualScorekeeper() {
  const [names, setNames] = useState<[string, string]>(['Player 1', 'Player 2']);
  const [score, setScore] = useState<[number, number]>([0, 0]);
  const [history, setHistory] = useState<[number, number][]>([]);
  const [gameTo, setGameTo] = useState<11 | 21>(11);
  const winner = Math.max(...score) >= gameTo && Math.abs(score[0] - score[1]) >= 2
    ? (score[0] > score[1] ? 0 : 1)
    : null;
  const addPoint = (player: 0 | 1) => {
    if (winner != null) return;
    setHistory((current) => [...current, score]);
    setScore((current) => player === 0 ? [current[0] + 1, current[1]] : [current[0], current[1] + 1]);
  };
  const quickWin = (player: 0 | 1) => {
    if (winner != null) return;
    const opponent = player === 0 ? 1 : 0;
    const winningScore = Math.max(gameTo, score[opponent] + 2);
    setHistory((current) => [...current, score]);
    setScore((current) => player === 0 ? [winningScore, current[1]] : [current[0], winningScore]);
  };
  const undo = () => {
    const previous = history.at(-1);
    if (!previous) return;
    setScore(previous);
    setHistory((current) => current.slice(0, -1));
  };
  const reset = () => { setScore([0, 0]); setHistory([]); };

  return (
    <main className="app-screen fixed-list-screen min-h-screen bg-gradient-to-br from-white via-accent-gray-50 to-primary-purple/5 px-3 py-4 sm:px-4 sm:py-8">
      <div className="app-screen-shell mx-auto max-w-xl">
        <div className="screen-fixed">
          <p className="text-xs font-black uppercase tracking-[.18em] text-primary-purple">Casual game</p>
          <h1 className="mt-1 text-4xl font-black tracking-tight sm:text-5xl">Scorekeeper</h1>
          <div className="mt-2 flex items-center gap-2">
            <div aria-label="Points needed to win" className="inline-flex rounded-full border border-primary-purple/15 bg-white p-1 shadow-sm" role="group">
              {([11, 21] as const).map((target) => (
                <button
                  key={target}
                  type="button"
                  aria-pressed={gameTo === target}
                  onClick={() => setGameTo(target)}
                  className={`min-h-8 rounded-full px-3 text-xs font-black transition active:scale-95 ${gameTo === target ? 'bg-primary-purple text-white shadow-sm' : 'text-accent-gray-500 hover:bg-primary-purple/5'}`}
                >
                  To {target}
                </button>
              ))}
            </div>
            <p className="text-xs font-bold text-accent-gray-500">Win by 2 · not saved</p>
          </div>
        </div>
        <section className="screen-flex flex min-h-0 flex-col overflow-hidden rounded-[2rem] border-2 border-primary-purple/10 bg-white shadow-xl sm:mt-6">
          <div className="grid min-h-0 flex-1 grid-cols-2">
            {([0, 1] as const).map((player) => (
              <div key={player} className={`flex min-w-0 flex-col p-3 text-center sm:p-6 ${player === 1 ? 'border-l border-accent-gray-200' : ''} ${winner === player ? 'bg-green-50' : ''}`}>
                <label className="text-[10px] font-black uppercase tracking-[.14em] text-accent-gray-400 sm:text-xs" htmlFor={`casual-player-${player}`}>
                  Player {player + 1}
                </label>
                <input
                  id={`casual-player-${player}`}
                  aria-label={`Player ${player + 1} name`}
                  maxLength={24}
                  value={names[player]}
                  onFocus={(event) => event.currentTarget.select()}
                  onChange={(event) => setNames((current) => player === 0 ? [event.target.value, current[1]] : [current[0], event.target.value])}
                  className="mt-2 h-12 w-full rounded-xl border border-accent-gray-200 bg-accent-gray-50 px-2 text-center text-base font-black focus:border-primary-purple focus:bg-white focus:outline-none focus:ring-4 focus:ring-primary-purple/10 sm:h-14 sm:text-lg"
                />
                <div className="flex min-h-0 flex-1 items-center justify-center py-2 sm:py-4">
                  <p aria-live="polite" className={`select-none text-[clamp(6rem,27vw,9rem)] font-black leading-none tabular-nums tracking-[-.08em] ${winner === player ? 'text-green-600' : 'text-primary-purple'}`}>
                    {score[player]}
                  </p>
                </div>
                <div className="space-y-2">
                  <button
                    type="button"
                    aria-label={`Add point for ${names[player] || `Player ${player + 1}`}`}
                    onClick={() => addPoint(player)}
                    disabled={winner != null}
                    className="min-h-20 w-full rounded-2xl gradient-purple text-4xl font-black text-white shadow-lg shadow-primary-purple/20 transition active:scale-[.97] disabled:cursor-not-allowed disabled:opacity-[.35] sm:min-h-24"
                  >
                    +1
                  </button>
                  <button
                    type="button"
                    onClick={() => quickWin(player)}
                    disabled={winner != null}
                    className="min-h-10 w-full rounded-xl border-2 border-primary-purple/20 bg-primary-purple/5 text-xs font-black text-primary-purple transition hover:bg-primary-purple/10 active:scale-[.97] disabled:cursor-not-allowed disabled:opacity-[.35]"
                  >
                    Quick win · {gameTo}+
                  </button>
                </div>
              </div>
            ))}
          </div>
          {winner != null && (
            <div className="border-t border-green-200 bg-green-50 px-4 py-3 text-center">
              <p className="text-[10px] font-black uppercase tracking-[.16em] text-green-700">Game over</p>
              <p className="text-xl font-black text-green-800 sm:text-2xl">{names[winner] || `Player ${winner + 1}`} wins!</p>
            </div>
          )}
          <div className="grid grid-cols-2 gap-3 border-t border-accent-gray-200 bg-accent-gray-50 p-3 sm:p-4">
            <button
              type="button"
              onClick={undo}
              disabled={!history.length}
              className="min-h-14 rounded-xl border-2 border-accent-gray-300 bg-white font-black text-accent-gray-700 transition active:scale-[.98] disabled:cursor-not-allowed disabled:border-accent-gray-200 disabled:bg-accent-gray-100 disabled:text-accent-gray-300 disabled:shadow-none"
            >
              Undo
            </button>
            <button type="button" onClick={reset} className="min-h-14 rounded-xl border-2 border-red-200 bg-red-50 font-black text-red-600 transition active:scale-[.98]">
              New game
            </button>
          </div>
        </section>
      </div>
    </main>
  );
}
