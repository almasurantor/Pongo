'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import LandingFeatureShowcase from '@/components/LandingFeatureShowcase';
import PingPongAnimation from '@/components/PingPongAnimation';
import PongoLogo from '@/components/PongoLogo';
import PongoWordmark from '@/components/PongoWordmark';
import { RankIcon } from '@/components/RankBadge';
import { useTheme } from '@/components/ThemeProvider';
import { RankTierName } from '@/lib/ranks';

const ranks: { name: RankTierName; range: string }[] = [
  { name: 'Iron', range: '500–649 ELO' },
  { name: 'Bronze', range: '650–799 ELO' },
  { name: 'Silver', range: '800–949 ELO' },
  { name: 'Gold', range: '950–1099 ELO' },
  { name: 'Platinum', range: '1100–1249 ELO' },
  { name: 'Diamond', range: '1250–1399 ELO' },
  { name: 'Legend', range: '1400+ ELO' },
];

export default function HomePageClient({ authenticated = false }: { authenticated?: boolean }) {
  const { setPreference } = useTheme();

  const toggleTheme = () => {
    const isDark = document.documentElement.classList.contains('dark');
    setPreference(isDark ? 'light' : 'dark');
  };

  return (
    <main className="landing-page min-h-screen overflow-x-hidden bg-[#F8FAFC] text-[#0F172A] dark:bg-[#0B1120] dark:text-[#F8FAFC]">
      <nav className="sticky top-0 z-50 border-b border-[#E2E8F0] bg-[#F8FAFC] shadow-sm shadow-slate-900/5 dark:border-[#334155] dark:bg-[#0B1120]">
        <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-4 sm:h-[4.5rem] sm:px-8">
          <button
            type="button"
            onClick={toggleTheme}
            aria-label="Pongo — switch light or dark theme"
            title="Switch light or dark theme"
            className="group flex items-center gap-2 rounded-xl pr-2 text-[1.65rem] leading-none outline-none transition active:scale-[0.97] focus-visible:ring-2 focus-visible:ring-[#2563EB] focus-visible:ring-offset-2 focus-visible:ring-offset-[#F8FAFC] dark:focus-visible:ring-[#60A5FA] dark:focus-visible:ring-offset-[#0B1120] sm:text-3xl"
          >
            <PongoLogo priority imageClassName="transition-transform group-hover:rotate-[-3deg] group-hover:scale-105" />
            <PongoWordmark />
          </button>
          <Link href={authenticated ? '/dashboard' : '/login'} className={`flex min-h-11 items-center rounded-xl px-4 py-2 text-lg font-bold transition active:scale-95 sm:px-5 sm:text-xl ${authenticated ? 'bg-[#2563EB] text-white shadow-md shadow-blue-600/20 hover:bg-[#1D4ED8]' : 'text-[#1D4ED8] hover:bg-[#DBEAFE] dark:text-[#60A5FA] dark:hover:bg-[#1E40AF]/30'}`}>
            {authenticated ? 'Back to Dashboard' : 'Sign in'}
          </Link>
        </div>
      </nav>

      <section className="relative mx-auto grid min-h-[calc(100svh-7rem)] w-full max-w-6xl grid-cols-[minmax(0,1fr)] items-center gap-8 overflow-hidden px-5 py-10 sm:min-h-[calc(100svh-4.5rem)] sm:px-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,0.9fr)] lg:py-16">
        <motion.div initial={false} className="relative z-10 min-w-0 text-center lg:text-left">
          <h1 className="text-balance text-4xl font-black leading-[0.96] tracking-[-0.045em] sm:text-6xl sm:tracking-[-0.055em] lg:text-7xl">
            Play more.<br /><span className="text-[#2563EB]">Climb higher.</span>
          </h1>
          <p className="mx-auto mt-5 max-w-[22rem] text-lg font-medium leading-relaxed text-[#475569] dark:text-[#CBD5E1] sm:max-w-xl lg:mx-0">
            Challenge players, track every match, and climb from Iron to Legend.
          </p>
          <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row lg:justify-start">
            {authenticated ? (
              <><Link href="/dashboard" className="rounded-2xl bg-[#2563EB] px-7 py-4 text-center text-base font-black text-white shadow-lg shadow-blue-600/25 transition hover:bg-[#1D4ED8] active:scale-[0.97]">Back to Dashboard</Link><Link href="#features" className="rounded-2xl border-2 border-[#2563EB] bg-white px-7 py-4 text-center text-base font-black text-[#1D4ED8] transition hover:bg-[#EFF6FF] active:scale-[0.97] dark:bg-[#111827] dark:text-[#60A5FA]">Explore the app</Link></>
            ) : (
              <><Link href="/signup" className="rounded-2xl bg-[#F97316] px-7 py-4 text-center text-base font-black text-white shadow-lg shadow-orange-500/25 transition hover:bg-[#EA580C] active:scale-[0.97]">Get started</Link><Link href="/login" className="rounded-2xl border-2 border-[#2563EB] bg-white px-7 py-4 text-center text-base font-black text-[#1D4ED8] transition hover:bg-[#EFF6FF] active:scale-[0.97] dark:bg-[#111827] dark:text-[#60A5FA] dark:hover:bg-[#1F2937]">Sign in</Link></>
            )}
          </div>
        </motion.div>
        <motion.div initial={false} className="relative z-10 min-w-0 w-full max-w-full">
          <PingPongAnimation />
        </motion.div>
      </section>

      <section id="rules" className="border-b border-[#E2E8F0] bg-[#EFF6FF] px-5 py-16 dark:border-[#334155] dark:bg-[#17243C] sm:px-8 sm:py-20">
        <div className="mx-auto max-w-6xl">
          <div className="mx-auto max-w-2xl text-center"><p className="text-sm font-black uppercase tracking-[.2em] text-[#2563EB] dark:text-[#93C5FD]">How ranked play works</p><h2 className="mt-3 text-4xl font-black tracking-tight sm:text-5xl">Simple rules. Fair results.</h2></div>
          <div className="mt-10 grid gap-4 md:grid-cols-3">
            {[['1', 'Find a match', 'Challenge another player or join the live table queue.'], ['2', 'Play to 11', 'Win by two points. At 10–10, keep playing until someone leads by two.'], ['3', 'Confirm the result', 'Report the final score. Ratings update only after the result is verified.']].map(([step, title, copy]) => <article key={step} className="rounded-3xl border border-[#BFDBFE] bg-white p-6 shadow-sm dark:border-[#334155] dark:bg-[#111827]"><span className="grid h-11 w-11 place-items-center rounded-2xl bg-[#2563EB] text-lg font-black text-white">{step}</span><h3 className="mt-5 text-xl font-black">{title}</h3><p className="mt-2 leading-relaxed text-accent-gray-500 dark:text-accent-gray-300">{copy}</p></article>)}
          </div>
        </div>
      </section>

      <section id="features" className="flex min-h-[100svh] items-center border-y border-[#E2E8F0] bg-white px-5 py-16 dark:border-[#334155] dark:bg-[#111827] sm:px-8 sm:py-20">
        <div className="mx-auto w-full max-w-6xl">
          <div className="mx-auto mb-10 max-w-2xl text-center">
            <p className="text-sm font-black uppercase tracking-[0.2em] text-[#F97316]">Built for match day</p>
            <h2 className="mt-3 text-4xl font-black tracking-tight sm:text-5xl">Everything you need to play.</h2>
            <p className="mx-auto mt-4 max-w-xl text-base leading-relaxed text-accent-gray-500 dark:text-accent-gray-300">Try each preview to see how a match moves through Pongo.</p>
          </div>
          <LandingFeatureShowcase />
        </div>
      </section>

      <section className="px-5 pb-6 pt-12 sm:px-8 sm:py-24">
        <div className="mx-auto max-w-6xl text-center">
          <p className="text-sm font-black uppercase tracking-[0.2em] text-[#2563EB]">Your rank journey</p>
          <h2 className="mt-3 text-4xl font-black tracking-tight sm:text-5xl">Start at Iron. Climb to Legend.</h2>
          <div className="mx-auto mt-6 inline-flex items-center gap-2 rounded-full bg-[#DBEAFE] px-4 py-2 text-sm font-black text-[#1E40AF] dark:bg-[#1E40AF]/30 dark:text-[#93C5FD]">Starting ELO <span className="text-lg">500</span></div>
          <div className="mt-10 grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-7">
            {ranks.map((rank) => (
              <motion.div key={rank.name} initial={false} whileHover={{ y: -4 }} className="flex min-h-36 flex-col items-center justify-center rounded-2xl border border-[#E2E8F0] bg-white p-4 shadow-sm dark:border-[#334155] dark:bg-[#111827]">
                <RankIcon tier={rank.name} className="h-14 w-14" />
                <strong className="mt-2 text-sm">{rank.name}</strong>
                <span className="mt-1 text-[11px] font-medium text-accent-gray-500 dark:text-accent-gray-400">{rank.range}</span>
              </motion.div>
            ))}
          </div>
          <div className="mt-8 rounded-[2rem] bg-[#2563EB] px-6 py-7 text-white shadow-xl shadow-blue-600/20 sm:mt-14 sm:px-10 sm:py-10">
            <PongoLogo alt="Pongo mascot" size="xl" className="mx-auto mb-2" />
            <h3 className="text-3xl font-black">Take the #1 spot.</h3>
            <p className="mx-auto mt-3 max-w-md text-[#DBEAFE]">Find your next opponent and make every game count.</p>
            <div className="mt-7 flex flex-col justify-center gap-3 sm:flex-row">
              {authenticated ? <Link href="/dashboard" className="rounded-2xl bg-white px-7 py-4 font-black text-[#1D4ED8] transition hover:bg-[#EFF6FF] active:scale-[0.97]">Back to Dashboard</Link> : <><Link href="/signup" className="rounded-2xl bg-[#F97316] px-7 py-4 font-black text-white transition hover:bg-[#EA580C] active:scale-[0.97]">Join Pongo</Link><Link href="/login" className="rounded-2xl border border-white/40 px-7 py-4 font-black text-white transition hover:bg-white/10 active:scale-[0.97]">Sign in</Link></>}
            </div>
          </div>
        </div>
      </section>
    </main>
  );
}
