'use client';

import { AnimatePresence, motion } from 'framer-motion';
import { useState } from 'react';

function RankedDemo() {
  const [settled, setSettled] = useState(false);
  return (
    <article className="flex h-full min-h-[21rem] flex-col rounded-[1.75rem] border border-accent-gray-200 bg-white p-5 shadow-[0_18px_50px_rgba(15,23,42,0.07)] dark:border-accent-gray-700 dark:bg-accent-gray-800 sm:p-6">
      <div className="flex items-center justify-between">
        <span className="rounded-full bg-blue-50 px-3 py-1 text-xs font-black text-blue-700 dark:bg-blue-950/50 dark:text-blue-300">RANKED</span>
        <motion.span key={settled ? 'win' : 'ready'} initial={{ opacity: 0, y: -4 }} animate={{ opacity: 1, y: 0 }} className="text-xs font-black text-accent-gray-500">{settled ? 'CONFIRMED' : 'READY'}</motion.span>
      </div>
      <div className="my-auto py-7 text-center">
        <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-3">
          <div><strong className="block text-lg">You</strong><span className="text-xs text-accent-gray-500">Gold</span></div>
          <motion.div animate={settled ? { scale: [1, 1.12, 1] } : {}} className="rounded-2xl bg-accent-gray-100 px-3 py-2 font-black text-accent-gray-700 dark:bg-accent-gray-900 dark:text-white">{settled ? '11–8' : 'VS'}</motion.div>
          <div><strong className="block text-lg">Maya</strong><span className="text-xs text-accent-gray-500">Gold</span></div>
        </div>
        <AnimatePresence mode="wait">
          <motion.div key={settled ? 'settled' : 'pending'} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -8 }} className="mt-6">
            <strong className={`text-3xl ${settled ? 'text-emerald-600 dark:text-emerald-400' : 'text-accent-gray-400'}`}>{settled ? '+36' : '1042'}</strong>
            <span className="ml-2 text-sm font-bold text-accent-gray-500">{settled ? 'ELO' : 'current ELO'}</span>
          </motion.div>
        </AnimatePresence>
      </div>
      <button type="button" onClick={() => setSettled((value) => !value)} className="min-h-12 rounded-xl bg-primary-purple px-4 font-black text-white transition hover:bg-primary-purpleDark active:scale-[0.98]">
        {settled ? 'Replay result' : 'Confirm 11–8 win'}
      </button>
      <h3 className="mt-5 text-xl font-black">Ranked matches</h3>
      <p className="mt-1 text-sm leading-relaxed text-accent-gray-500 dark:text-accent-gray-300">Play, confirm the score, and see your rating move.</p>
    </article>
  );
}

function QueueDemo() {
  const [step, setStep] = useState(0);
  const players = step === 0 ? ['Kai · Playing', 'Maya · Next'] : step === 1 ? ['Kai · Playing', 'You · Called'] : ['You · Playing', 'Maya · Next'];
  return (
    <article className="flex h-full min-h-[21rem] flex-col rounded-[1.75rem] border border-accent-gray-200 bg-white p-5 shadow-[0_18px_50px_rgba(15,23,42,0.07)] dark:border-accent-gray-700 dark:bg-accent-gray-800 sm:p-6">
      <div className="flex items-center justify-between">
        <span className="rounded-full bg-orange-50 px-3 py-1 text-xs font-black text-orange-700 dark:bg-orange-950/50 dark:text-orange-300">LIVE QUEUE</span>
        <span className="flex items-center gap-1.5 text-xs font-black text-emerald-600 dark:text-emerald-400"><span className="h-2 w-2 rounded-full bg-emerald-500" />LIVE</span>
      </div>
      <div className="my-auto space-y-3 py-6">
        <AnimatePresence mode="popLayout">
          {players.map((player, index) => (
            <motion.div layout key={player} initial={{ opacity: 0, x: 15 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -15 }} className={`flex items-center gap-3 rounded-2xl p-3 ${player.startsWith('You') ? 'bg-orange-50 ring-2 ring-brand-orange/30 dark:bg-orange-950/30' : 'bg-accent-gray-50 dark:bg-accent-gray-900'}`}>
              <span className={`grid h-9 w-9 place-items-center rounded-xl text-sm font-black ${player.startsWith('You') ? 'bg-brand-orange text-white' : 'bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-300'}`}>{index + 1}</span>
              <strong className="text-sm">{player}</strong>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>
      <button type="button" onClick={() => setStep((value) => (value + 1) % 3)} className="min-h-12 rounded-xl bg-brand-orange px-4 font-black text-white transition hover:bg-brand-orangeDark active:scale-[0.98]">
        {step === 0 ? 'Join queue' : step === 1 ? "I'm here" : 'Play again'}
      </button>
      <h3 className="mt-5 text-xl font-black">Queue</h3>
      <p className="mt-1 text-sm leading-relaxed text-accent-gray-500 dark:text-accent-gray-300">Join the line, check in, and take the next open table.</p>
    </article>
  );
}

const standings = {
  Weekly: [['Kai', '6–1'], ['You', '5–1'], ['Maya', '4–2']],
  Monthly: [['You', '18–4'], ['Maya', '17–5'], ['Kai', '15–6']],
};

function LeaderboardDemo() {
  const [period, setPeriod] = useState<keyof typeof standings>('Weekly');
  return (
    <article className="flex h-full min-h-[21rem] flex-col rounded-[1.75rem] border border-accent-gray-200 bg-white p-5 shadow-[0_18px_50px_rgba(15,23,42,0.07)] dark:border-accent-gray-700 dark:bg-accent-gray-800 sm:p-6">
      <div className="grid grid-cols-2 rounded-xl bg-accent-gray-100 p-1 dark:bg-accent-gray-900" role="group" aria-label="Leaderboard period preview">
        {(Object.keys(standings) as (keyof typeof standings)[]).map((choice) => (
          <button key={choice} type="button" aria-pressed={period === choice} onClick={() => setPeriod(choice)} className={`min-h-9 rounded-lg text-xs font-black transition ${period === choice ? 'bg-white text-primary-purple shadow-sm dark:bg-accent-gray-700 dark:text-blue-300' : 'text-accent-gray-500'}`}>{choice}</button>
        ))}
      </div>
      <div className="my-auto space-y-2 py-5">
        <AnimatePresence mode="popLayout">
          {standings[period].map(([name, record], index) => (
            <motion.div layout key={name} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -10 }} transition={{ delay: index * 0.04 }} className={`grid grid-cols-[2rem_1fr_auto] items-center rounded-2xl p-3 ${name === 'You' ? 'bg-blue-50 ring-2 ring-primary-purple/20 dark:bg-blue-950/30' : 'bg-accent-gray-50 dark:bg-accent-gray-900'}`}>
              <strong className={index === 0 ? 'text-brand-orange' : 'text-accent-gray-400'}>#{index + 1}</strong>
              <span className="font-black">{name}</span>
              <span className="text-sm font-bold text-accent-gray-500">{record}</span>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>
      <div className="min-h-12 rounded-xl border-2 border-primary-purple/20 px-4 py-3 text-center text-sm font-black text-primary-purple dark:text-blue-300">Tap a tab to reorder</div>
      <h3 className="mt-5 text-xl font-black">Leaderboards</h3>
      <p className="mt-1 text-sm leading-relaxed text-accent-gray-500 dark:text-accent-gray-300">Track weekly and monthly movement at a glance.</p>
    </article>
  );
}

export default function LandingFeatureShowcase() {
  return (
    <div className="grid w-full gap-5 lg:grid-cols-3">
      <RankedDemo />
      <QueueDemo />
      <LeaderboardDemo />
    </div>
  );
}
