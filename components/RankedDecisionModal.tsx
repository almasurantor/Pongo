import RankBadge from '@/components/RankBadge';

export interface RankedDecisionPlayer {
  display_name: string;
  current_elo: number;
  total_wins: number;
  total_losses: number;
}

interface Props {
  challenger?: RankedDecisionPlayer | null;
  busy: boolean;
  onAccept: () => void;
  onDecline: () => void;
  onDismiss: () => void;
}

export default function RankedDecisionModal({ challenger, busy, onAccept, onDecline, onDismiss }: Props) {
  return (
    <div className="fixed inset-0 z-[90] grid place-items-center bg-slate-950/70 p-4" role="presentation">
      <section className="relative grid w-full max-w-md justify-items-center rounded-3xl border border-[#b8c8e6] bg-[#e5ebf5] px-5 pb-5 pt-8 text-center text-[#142b53] shadow-2xl dark:border-[#29469d] dark:bg-[#151f3c] dark:text-white" role="dialog" aria-modal="true" aria-labelledby="ranked-decision-title" aria-describedby="ranked-decision-description">
        <button
          type="button"
          aria-label="Dismiss incoming challenge popup"
          onClick={onDismiss}
          className="absolute right-3 top-3 grid h-11 w-11 place-items-center rounded-full text-2xl font-bold text-[#5e7194] transition hover:bg-white/50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#3774ef] dark:text-[#b7c3e0] dark:hover:bg-white/10"
        >
          ×
        </button>
        <p className="text-xs font-black uppercase tracking-[.14em] text-[#3774ef]">Incoming challenge</p>
        <h2 id="ranked-decision-title" className="mt-2 text-4xl font-black leading-[.95] tracking-[-.05em] sm:text-5xl">Play a Ranked match?</h2>
        <p id="ranked-decision-description" className="mt-4 text-[#5e7194] dark:text-[#b7c3e0]"><strong className="text-[#142b53] dark:text-white">{challenger?.display_name ?? 'Your opponent'}</strong> challenged you.</p>
        {challenger && (
          <div className="mt-4 flex flex-wrap items-center justify-center gap-2">
            <RankBadge elo={challenger.current_elo} totalGames={challenger.total_wins + challenger.total_losses} compact />
            <span className="text-sm font-bold text-[#5e7194] dark:text-[#b7c3e0]">{challenger.current_elo} ELO</span>
          </div>
        )}
        <div className="mt-6 grid w-full grid-cols-2 gap-3">
          <button disabled={busy} onClick={onDecline} className="min-h-14 rounded-2xl border-2 border-[#b8c8e6] bg-white/45 font-black text-[#142b53] disabled:opacity-50 dark:border-[#6f99d6] dark:bg-transparent dark:text-white">Decline</button>
          <button autoFocus disabled={busy} onClick={onAccept} className="min-h-14 rounded-2xl bg-[#2e8b57] font-black text-white transition hover:bg-[#26784b] disabled:opacity-50">Accept</button>
        </div>
      </section>
    </div>
  );
}
