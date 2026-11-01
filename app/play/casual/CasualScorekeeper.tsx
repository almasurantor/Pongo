'use client';

import { useState } from 'react';

export default function CasualScorekeeper() {
  const [names, setNames] = useState<[string, string]>(['Player 1', 'Player 2']);
  const [score, setScore] = useState<[number, number]>([0, 0]);
  const [history, setHistory] = useState<[number, number][]>([]);
  const winner = Math.max(...score) >= 11 && Math.abs(score[0] - score[1]) >= 2
    ? (score[0] > score[1] ? 0 : 1)
    : null;
  const addPoint = (player: 0 | 1) => {
    if (winner != null) return;
    setHistory((current) => [...current, score]);
    setScore((current) => player === 0 ? [current[0] + 1, current[1]] : [current[0], current[1] + 1]);
  };
  const undo = () => {
    const previous = history.at(-1);
    if (!previous) return;
    setScore(previous);
    setHistory((current) => current.slice(0, -1));
  };
  const reset = () => { setScore([0, 0]); setHistory([]); };

  return (
    <main className="min-h-screen bg-gradient-to-br from-white via-accent-gray-50 to-primary-purple/5 px-4 py-7">
      <div className="mx-auto max-w-xl">
        <p className="text-sm font-black uppercase text-primary-purple">Casual mode</p>
        <h1 className="mt-1 text-4xl font-black">Scorekeeper</h1>
        <p className="mt-2 text-accent-gray-600">A local game to 11, win by two. Nothing here is saved and ELO never changes.</p>
        <section className="mt-7 overflow-hidden rounded-3xl bg-white shadow-xl">
          <div className="grid grid-cols-2 divide-x divide-accent-gray-200">
            {([0, 1] as const).map((player) => (
              <div key={player} className={`p-4 text-center ${winner === player ? 'bg-green-50' : ''}`}>
                <input aria-label={`Player ${player + 1} name`} value={names[player]} onChange={(event) => setNames((current) => player === 0 ? [event.target.value, current[1]] : [current[0], event.target.value])} className="h-11 w-full rounded-xl border-2 border-accent-gray-200 px-2 text-center font-black focus:border-primary-purple focus:outline-none" />
                <p className={`my-6 text-7xl font-black ${winner === player ? 'text-green-600' : 'text-primary-purple'}`}>{score[player]}</p>
                <button onClick={() => addPoint(player)} disabled={winner != null} className="min-h-16 w-full rounded-2xl gradient-purple text-3xl font-black text-white disabled:opacity-40">+1</button>
              </div>
            ))}
          </div>
          {winner != null && <div className="border-t border-green-200 bg-green-50 p-5 text-center"><p className="text-sm font-black uppercase text-green-700">Game over</p><p className="text-2xl font-black text-green-800">{names[winner] || `Player ${winner + 1}`} wins!</p></div>}
          <div className="grid grid-cols-2 gap-3 border-t border-accent-gray-100 p-4">
            <button onClick={undo} disabled={!history.length} className="min-h-12 rounded-xl border-2 border-accent-gray-200 font-bold disabled:opacity-40">Undo</button>
            <button onClick={reset} className="min-h-12 rounded-xl border-2 border-red-200 font-bold text-red-600">New game</button>
          </div>
        </section>
      </div>
    </main>
  );
}
