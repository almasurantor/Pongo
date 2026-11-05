'use client';

import { useState } from 'react';
import toast from 'react-hot-toast';
import { useDatabaseRefresh } from '@/lib/use-database-refresh';
import { useRouter } from 'next/navigation';
import InAppConfirmDialog from '@/components/InAppConfirmDialog';
import InAppPromptDialog from '@/components/InAppPromptDialog';

type PlayerSummary = { id: string; display_name: string };
type AdminDispute = {
  id: string;
  reason: string;
  status: string;
  requested_resolution: 'correction' | 'void';
  original_player_one_score: number;
  original_player_two_score: number;
  original_winner_id: string;
  proposed_player_one_score: number;
  proposed_player_two_score: number;
  proposed_winner_id: string;
  match: {
    player_one_id: string;
    player_two_id: string;
    player_one: PlayerSummary;
    player_two: PlayerSummary;
  };
};
type IntegrityLevel = 'normal' | 'monitored' | 'dual_verification' | 'ranked_restricted';
type IntegrityRow = {
  player_id: string;
  verification_level: IntegrityLevel;
  confirmed_violations: number;
  player: PlayerSummary | null;
};
type IntegrityFlag = {
  id: string;
  flag_type: string;
  details: Record<string, unknown>;
  created_at: string;
  player: PlayerSummary | null;
  match: { player_one: PlayerSummary; player_two: PlayerSummary } | null;
};
type ResolutionPayload = {
  winner_id?: string;
  winner_score?: number;
  loser_score?: number;
  violation_user_id?: string | null;
  notes?: string;
};

type QueueGame = {
  id: string;
  king_id: string;
  challenger_id: string;
  king_name: string;
  challenger_name: string;
  status: 'completed' | 'abandoned';
  winner_id: string | null;
  loser_id: string | null;
  reported_by: string | null;
  completed_at: string;
  corrected_at: string | null;
};

export default function AdminClient({ disputes, integrity, flags, queueGames }: { disputes: AdminDispute[]; integrity: IntegrityRow[]; flags: IntegrityFlag[]; queueGames: QueueGame[] }) {
  const router = useRouter();
  useDatabaseRefresh('admin-review', ['disputes', 'integrity_flags', 'player_integrity', 'beaver_queue_games', 'beaver_queue_game_corrections']);
  const [selected, setSelected] = useState<AdminDispute | null>(null);
  const [loading, setLoading] = useState(false);
  const [customWinner, setCustomWinner] = useState('');
  const [customWinnerScore, setCustomWinnerScore] = useState(11);
  const [customLoserScore, setCustomLoserScore] = useState(0);
  const [notes, setNotes] = useState('');
  const [violationUser, setViolationUser] = useState('');
  const [violationResolution, setViolationResolution] = useState<'original' | 'proposed' | 'custom' | 'voided'>('original');
  const [confirmation, setConfirmation] = useState<{ title: string; message: string; confirmLabel: string; action: () => void } | null>(null);
  const [queueCorrection, setQueueCorrection] = useState<QueueGame | null>(null);
  const [correctionReason, setCorrectionReason] = useState('');
  const openDispute = (dispute: AdminDispute) => {
    setSelected(dispute);
    setCustomWinner(dispute.original_winner_id);
    setCustomWinnerScore(Math.max(dispute.original_player_one_score, dispute.original_player_two_score));
    setCustomLoserScore(Math.min(dispute.original_player_one_score, dispute.original_player_two_score));
    setNotes('');
    setViolationUser(dispute.match.player_one_id);
    setViolationResolution('original');
  };
  const performResolve = async (resolution: string, payload: ResolutionPayload = {}) => {
    if (!selected) return;
    setLoading(true);
    try { const response=await fetch(`/api/admin/disputes/${selected.id}/resolve`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({resolution,...payload,notes:payload.notes ?? notes})});const result=await response.json();if(!response.ok)throw new Error(result.error||'Could not resolve dispute');toast.success('Dispute resolved');setSelected(null);router.refresh(); }
    catch(error){toast.error(error instanceof Error?error.message:'Could not resolve dispute');}finally{setLoading(false);}
  };
  const resolve = (resolution: string, payload: ResolutionPayload = {}) => {
    if (resolution === 'voided' || payload.violation_user_id) {
      const recordsViolation = Boolean(payload.violation_user_id);
      setConfirmation({
        title: recordsViolation ? 'Record confirmed violation?' : 'Void this match?',
        message: recordsViolation ? 'This resolution will also assign a confirmed reporting violation to the selected player.' : 'This will void the match and replay the affected ratings.',
        confirmLabel: recordsViolation ? 'Resolve & record' : 'Void match',
        action: () => void performResolve(resolution, payload),
      });
      return;
    }
    void performResolve(resolution, payload);
  };
  const performSetLevel = async (playerId:string,level:IntegrityLevel) => {
    try{const response=await fetch(`/api/admin/players/${playerId}/integrity`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({level})});const result=await response.json();if(!response.ok)throw new Error(result.error||'Could not update player');toast.success('Integrity level updated');router.refresh();}catch(error){toast.error(error instanceof Error?error.message:'Could not update player');}
  };
  const setLevel = (playerId:string,level:IntegrityLevel) => {
    if (level === 'ranked_restricted') {
      setConfirmation({
        title: 'Restrict ranked play?',
        message: 'This player will be blocked from all ranked play until their integrity level is changed.',
        confirmLabel: 'Restrict player',
        action: () => void performSetLevel(playerId, level),
      });
      return;
    }
    void performSetLevel(playerId, level);
  };
  const reviewFlag = async (flagId: string) => {
    try { const response=await fetch(`/api/admin/integrity-flags/${flagId}/review`,{method:'POST'});const result=await response.json();if(!response.ok)throw new Error(result.error||'Could not review flag');toast.success('Integrity flag reviewed');router.refresh(); }
    catch(error){toast.error(error instanceof Error?error.message:'Could not review flag');}
  };
  const requestQueueCorrection = (game: QueueGame) => {
    if (game.status !== 'completed' || !game.winner_id) return;
    setCorrectionReason('');
    setQueueCorrection(game);
  };
  const correctQueueGame = async () => {
    const game = queueCorrection;
    if (!game || game.status !== 'completed' || !game.winner_id) return;
    const newWinnerId = game.winner_id === game.king_id ? game.challenger_id : game.king_id;
    const reason = correctionReason.trim();
    if (reason.length < 3) { toast.error('The correction reason must be at least 3 characters.'); return; }
    try {
      const response = await fetch(`/api/admin/queue-games/${game.id}/correct`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ winner_id: newWinnerId, reason }) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Could not correct queue game');
      toast.success('Queue history corrected. Live queue state was not changed.');
      setQueueCorrection(null);
      router.refresh();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Could not correct queue game'); }
  };
  const resolveWithViolation = () => {
    const payload: ResolutionPayload = { violation_user_id: violationUser };
    if (violationResolution === 'custom') {
      payload.winner_id = customWinner;
      payload.winner_score = customWinnerScore;
      payload.loser_score = customLoserScore;
    }
    void resolve(violationResolution, payload);
  };
  const resultText = (dispute: AdminDispute, proposed = false) => {
    const match = dispute.match;
    const playerOneScore = proposed ? dispute.proposed_player_one_score : dispute.original_player_one_score;
    const playerTwoScore = proposed ? dispute.proposed_player_two_score : dispute.original_player_two_score;
    return `${match.player_one.display_name} ${playerOneScore}–${playerTwoScore} ${match.player_two.display_name}`;
  };
  const modalFieldClass = 'h-11 w-full rounded-xl border-2 border-slate-200 bg-white px-3 text-slate-900 outline-none transition focus:border-[#2563EB] focus:ring-2 focus:ring-blue-500/15 dark:border-slate-600 dark:bg-[#0B1120] dark:text-slate-100';

  return (
    <main className="min-h-screen bg-accent-gray-50 px-4 py-7">
      <div className="mx-auto max-w-5xl">
        <h1 className="text-4xl font-black">Integrity</h1>
        <div className="mt-8 grid gap-8 lg:grid-cols-[1.4fr_1fr]">
          <section>
            <h2 className="text-xl font-black">Disputes</h2>
            <div className="mt-3 space-y-3">
              {disputes.map((dispute) => (
                <button key={dispute.id} onClick={() => openDispute(dispute)} className="w-full rounded-2xl border-2 border-accent-gray-200 bg-white p-5 text-left">
                  <div className="flex justify-between gap-3">
                    <span className="font-black">{dispute.match.player_one.display_name} vs {dispute.match.player_two.display_name}</span>
                    <span className="rounded-full bg-amber-100 px-2 py-1 text-xs font-bold text-amber-800">{dispute.status.replace('_', ' ')}</span>
                  </div>
                  <p className="mt-2 text-sm text-accent-gray-500">Original: {resultText(dispute)} · Proposed: {resultText(dispute, true)}</p>
                </button>
              ))}
              {!disputes.length && <div className="rounded-2xl bg-white p-8 text-center text-accent-gray-500">No unresolved disputes.</div>}
            </div>
          </section>

          <section>
            <h2 className="text-xl font-black">Player integrity</h2>
            <div className="mt-3 space-y-3">
              {integrity.map((row) => (
                <div key={row.player_id} className="rounded-2xl bg-white p-4">
                  <p className="font-black">{row.player?.display_name}</p>
                  <p className="text-sm text-accent-gray-500">{row.confirmed_violations} confirmed violations</p>
                  <select aria-label={`Integrity level for ${row.player?.display_name}`} value={row.verification_level} onChange={(event) => setLevel(row.player_id, event.target.value as IntegrityLevel)} className="mt-3 h-11 w-full rounded-xl border-2 border-accent-gray-200 bg-white px-3 font-bold dark:bg-[#0B1120]">
                    <option value="normal">Normal</option>
                    <option value="monitored">Monitored</option>
                    <option value="dual_verification">Dual verification</option>
                    <option value="ranked_restricted">Ranked restricted</option>
                  </select>
                </div>
              ))}
            </div>
          </section>
        </div>

        <section className="mt-8">
          <h2 className="text-xl font-black">Signals</h2>
          <div className="mt-3 grid gap-3 sm:grid-cols-2">
            {flags.map((flag) => (
              <div key={flag.id} className="rounded-2xl border-2 border-accent-gray-200 bg-white p-4">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-black">{flag.flag_type.replaceAll('_', ' ')}</p>
                    <p className="mt-1 text-sm text-accent-gray-500">{flag.player?.display_name || (flag.match ? `${flag.match.player_one.display_name} vs ${flag.match.player_two.display_name}` : 'System signal')}</p>
                  </div>
                  <button onClick={() => reviewFlag(flag.id)} className="rounded-xl border-2 border-accent-gray-200 px-3 py-2 text-sm font-black">Reviewed</button>
                </div>
                <p className="mt-3 break-words text-xs text-accent-gray-400">{JSON.stringify(flag.details)}</p>
              </div>
            ))}
            {!flags.length && <div className="rounded-2xl bg-white p-8 text-center text-accent-gray-500">No unreviewed integrity signals.</div>}
          </div>
        </section>

        <section className="mt-8">
          <div className="flex items-end justify-between gap-3">
            <div>
              <h2 className="text-xl font-black">Queue history audit</h2>
              <p className="mt-1 text-sm text-accent-gray-500">Corrections change history only. They never alter the live holder, ELO, or ranked records.</p>
            </div>
            <span className="shrink-0 text-xs font-bold text-accent-gray-400">Latest 50</span>
          </div>
          <div className="mt-3 max-h-[32rem] space-y-3 overflow-y-auto pr-1">
            {queueGames.map((game) => {
              const winnerName = game.winner_id === game.king_id ? game.king_name : game.challenger_name;
              const loserName = game.loser_id === game.king_id ? game.king_name : game.challenger_name;
              return (
                <div key={game.id} className="rounded-2xl border-2 border-accent-gray-200 bg-white p-4 dark:border-slate-700 dark:bg-[#111827]">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <p className="font-black">{game.status === 'abandoned' ? `${game.king_name} vs ${game.challenger_name}` : `${winnerName} won vs ${loserName}`}</p>
                      <p className="mt-1 text-xs text-accent-gray-500">{new Date(game.completed_at).toLocaleString()}</p>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {game.status === 'abandoned' && <span className="rounded-full bg-amber-100 px-2 py-1 text-xs font-black text-amber-800">Abandoned · 10m</span>}
                      {game.corrected_at && <span className="rounded-full bg-blue-100 px-2 py-1 text-xs font-black text-blue-800">Corrected</span>}
                    </div>
                  </div>
                  {game.status === 'completed' && <button onClick={() => requestQueueCorrection(game)} className="mt-3 rounded-xl border-2 border-accent-gray-200 px-3 py-2 text-sm font-black transition hover:border-blue-300 hover:text-blue-700 dark:border-slate-600">Change recorded winner</button>}
                  {game.status === 'abandoned' && <p className="mt-3 text-xs text-accent-gray-500">Audit only — an abandoned game cannot be assigned a winner.</p>}
                </div>
              );
            })}
            {!queueGames.length && <div className="rounded-2xl bg-white p-8 text-center text-accent-gray-500 dark:bg-[#111827]">No queue games to audit.</div>}
          </div>
        </section>

        {selected && (
          <div role="dialog" aria-modal="true" aria-labelledby="review-dispute-title" className="fixed inset-0 z-[70] flex items-end bg-slate-950/60 p-4 backdrop-blur-sm sm:items-center sm:justify-center">
            <div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-3xl border border-slate-200 bg-white p-5 text-slate-900 shadow-2xl dark:border-slate-700 dark:bg-[#111827] dark:text-slate-100 sm:p-6">
              <h2 id="review-dispute-title" className="text-2xl font-black">Review dispute</h2>
              <div className="mt-4 rounded-2xl bg-slate-50 p-4 dark:bg-[#0B1120]">
                <p className="text-sm font-bold text-slate-500 dark:text-slate-400">Original report</p>
                <p className="text-lg font-black">{resultText(selected)}</p>
                <p className="mt-4 text-sm font-bold text-slate-500 dark:text-slate-400">Requested resolution</p>
                <p className="text-lg font-black">{selected.requested_resolution === 'void' ? 'Void this match' : resultText(selected, true)}</p>
                <p className="mt-3 text-sm text-slate-500 dark:text-slate-400">Reason: {selected.reason.replaceAll('_', ' ')}</p>
              </div>

              <div className="mt-5 space-y-3">
                <button disabled={loading} onClick={() => resolve('original')} className="min-h-12 w-full rounded-xl bg-[#2563EB] px-4 font-bold text-white transition hover:bg-[#1D4ED8] disabled:opacity-50">Keep original result</button>
                <button disabled={loading} onClick={() => resolve('proposed')} className="min-h-12 w-full rounded-xl bg-green-600 px-4 font-bold text-white transition hover:bg-green-700 disabled:opacity-50">Approve requested {selected.requested_resolution}</button>
                <button disabled={loading} onClick={() => resolve('no_violation')} className="min-h-12 w-full rounded-xl border-2 border-slate-300 bg-white px-4 font-bold text-slate-700 transition hover:bg-slate-50 disabled:opacity-50 dark:border-slate-600 dark:bg-[#111827] dark:text-slate-100 dark:hover:bg-slate-800">Resolve original — no violation</button>

                <div className="rounded-2xl border border-slate-200 bg-slate-50/70 p-4 dark:border-slate-700 dark:bg-[#0B1120]">
                  <p className="font-black">Enter another valid result</p>
                  <select aria-label="Resolved winner" value={customWinner} onChange={(event) => setCustomWinner(event.target.value)} className={`${modalFieldClass} mt-3`}>
                    <option value={selected.match.player_one_id}>{selected.match.player_one.display_name}</option>
                    <option value={selected.match.player_two_id}>{selected.match.player_two.display_name}</option>
                  </select>
                  <div className="mt-2 grid grid-cols-2 gap-2">
                    <input aria-label="Winner score" type="number" min="0" max="99" value={customWinnerScore} onChange={(event) => setCustomWinnerScore(Number(event.target.value))} className={modalFieldClass} />
                    <input aria-label="Loser score" type="number" min="0" max="99" value={customLoserScore} onChange={(event) => setCustomLoserScore(Number(event.target.value))} className={modalFieldClass} />
                  </div>
                  <button disabled={loading} onClick={() => resolve('custom', { winner_id: customWinner, winner_score: customWinnerScore, loser_score: customLoserScore })} className="mt-3 min-h-12 w-full rounded-xl bg-[#2563EB] px-4 font-bold text-white transition hover:bg-[#1D4ED8] disabled:opacity-50">Approve custom result</button>
                </div>

                <textarea aria-label="Private admin notes" placeholder="Private admin notes (optional)" value={notes} onChange={(event) => setNotes(event.target.value)} className="min-h-24 w-full rounded-xl border-2 border-slate-200 bg-white p-3 text-slate-900 outline-none transition focus:border-[#2563EB] focus:ring-2 focus:ring-blue-500/15 dark:border-slate-600 dark:bg-[#0B1120] dark:text-slate-100" />

                <div className="rounded-2xl border border-red-200 bg-red-50/60 p-4 dark:border-red-900/60 dark:bg-red-950/20">
                  <p className="font-black text-red-800 dark:text-red-300">Record a confirmed violation</p>
                  <p className="mt-1 text-xs text-red-700/80 dark:text-red-300/75">Use only when a player intentionally submitted a false report.</p>
                  <div className="mt-3 grid gap-2 sm:grid-cols-2">
                    <select aria-label="Player responsible for violation" value={violationUser} onChange={(event) => setViolationUser(event.target.value)} className={modalFieldClass}>
                      <option value={selected.match.player_one_id}>{selected.match.player_one.display_name}</option>
                      <option value={selected.match.player_two_id}>{selected.match.player_two.display_name}</option>
                    </select>
                    <select aria-label="Resolution applied with violation" value={violationResolution} onChange={(event) => setViolationResolution(event.target.value as 'original' | 'proposed' | 'custom' | 'voided')} className={modalFieldClass}>
                      <option value="original">Keep original</option>
                      <option value="proposed">Approve request</option>
                      <option value="custom">Use custom result</option>
                      <option value="voided">Void match</option>
                    </select>
                  </div>
                  <button disabled={loading || !violationUser} onClick={resolveWithViolation} className="mt-3 min-h-12 w-full rounded-xl border-2 border-red-300 bg-white px-4 text-sm font-bold text-red-700 transition hover:bg-red-50 disabled:opacity-50 dark:border-red-800 dark:bg-transparent dark:text-red-300 dark:hover:bg-red-950/30">Resolve and record violation</button>
                </div>

                <button disabled={loading} onClick={() => resolve('voided')} className="min-h-12 w-full rounded-xl border-2 border-red-200 px-4 font-bold text-red-600 transition hover:bg-red-50 disabled:opacity-50 dark:border-red-900 dark:text-red-400 dark:hover:bg-red-950/20">Void duplicate/nonexistent match</button>
                <button onClick={() => setSelected(null)} className="min-h-12 w-full rounded-xl font-bold text-slate-500 transition hover:bg-slate-100 dark:text-slate-400 dark:hover:bg-slate-800">Close</button>
              </div>
            </div>
          </div>
        )}
        {confirmation && (
          <InAppConfirmDialog
            title={confirmation.title}
            message={confirmation.message}
            confirmLabel={confirmation.confirmLabel}
            onCancel={() => setConfirmation(null)}
            onConfirm={() => { const action = confirmation.action; setConfirmation(null); action(); }}
          />
        )}
        {queueCorrection && (() => {
          const newWinnerId = queueCorrection.winner_id === queueCorrection.king_id ? queueCorrection.challenger_id : queueCorrection.king_id;
          const newWinnerName = newWinnerId === queueCorrection.king_id ? queueCorrection.king_name : queueCorrection.challenger_name;
          return (
            <InAppPromptDialog
              title="Change recorded winner?"
              message={`The queue history will show ${newWinnerName} as the winner. Live queue state and ratings will not change.`}
              label="Audit reason"
              value={correctionReason}
              placeholder="Explain why this correction is needed"
              confirmLabel="Save correction"
              onChange={setCorrectionReason}
              onCancel={() => setQueueCorrection(null)}
              onConfirm={() => void correctQueueGame()}
            />
          );
        })()}
      </div>
    </main>
  );
}
