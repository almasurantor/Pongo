'use client';

import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import toast from 'react-hot-toast';
import ScoreStepper from '@/components/ScoreStepper';
import { validateMatchScore } from '@/lib/match-result';
import { calculateElo } from '@/lib/elo';
import { Dispute, Match, MatchCancellationRequest, MatchSubmission, RatingPreview } from '@/lib/types';
import { isMatchOverdue } from '@/lib/ranking-rules';
import { createClient } from '@/lib/supabase/client';
import { useDatabaseRefresh } from '@/lib/use-database-refresh';
import RankBadge from '@/components/RankBadge';
import { rankTransition } from '@/lib/ranks';
import DeadlineCountdown from '@/components/DeadlineCountdown';

interface Props {
  match: Match;
  cancellationRequest: MatchCancellationRequest | null;
  ratingPreview: RatingPreview | null;
  dispute: Dispute | null;
  mySubmission: MatchSubmission | null;
  currentUserId: string;
}

const deadlineFormatter = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/New_York',
  month: 'short',
  day: 'numeric',
  hour: 'numeric',
  minute: '2-digit',
  timeZoneName: 'short',
});

export default function MatchClient({
  match: initialMatch,
  cancellationRequest: initialCancellationRequest,
  ratingPreview,
  dispute: initialDispute,
  mySubmission: initialMySubmission,
  currentUserId,
}: Props) {
  useDatabaseRefresh(`match-${initialMatch.id}`);
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [match, setMatch] = useState(initialMatch);
  const [cancellationRequest, setCancellationRequest] = useState(initialCancellationRequest);
  const [dispute, setDispute] = useState(initialDispute);
  const [mySubmission, setMySubmission] = useState(initialMySubmission);
  const [winnerId, setWinnerId] = useState(currentUserId);
  const [myScore, setMyScore] = useState(11);
  const [theirScore, setTheirScore] = useState(9);
  const [loading, setLoading] = useState<string | null>(null);
  const [showReportConfirmation, setShowReportConfirmation] = useState(false);
  const [resultSummary, setResultSummary] = useState<{ won: boolean; change: number; placementBefore: number | null; placementAfter: number | null; placementChange: number } | null>(null);
  const [showDisputeForm, setShowDisputeForm] = useState(false);
  const [disputeReason, setDisputeReason] = useState<'incorrect_score' | 'incorrect_winner' | 'match_never_happened' | 'other'>('incorrect_score');
  const [disputeResolution, setDisputeResolution] = useState<'correction' | 'void'>('correction');
  const [correctionWinnerId, setCorrectionWinnerId] = useState(match.winner_id || currentUserId);
  const [correctionMyScore, setCorrectionMyScore] = useState(isNaN(Number(match.player_one_score)) ? 11 : (currentUserId === match.player_one_id ? match.player_one_score! : match.player_two_score!));
  const [correctionTheirScore, setCorrectionTheirScore] = useState(isNaN(Number(match.player_two_score)) ? 9 : (currentUserId === match.player_one_id ? match.player_two_score! : match.player_one_score!));

  useEffect(() => {
    setMatch(initialMatch);
    setCancellationRequest(initialCancellationRequest);
    setDispute(initialDispute);
    setMySubmission(initialMySubmission);
  }, [initialCancellationRequest, initialDispute, initialMatch, initialMySubmission]);

  const isPlayerOne = currentUserId === match.player_one_id;
  const opponent = isPlayerOne ? match.player_two : match.player_one;
  const mine = isPlayerOne ? match.player_one_score : match.player_two_score;
  const theirs = isPlayerOne ? match.player_two_score : match.player_one_score;
  const myRatingChange = (isPlayerOne ? match.player_one_elo_change : match.player_two_elo_change) ?? 0;
  const myRatingBefore = isPlayerOne ? match.player_one_elo_before : match.player_two_elo_before;
  const myRankTransition = myRatingBefore == null
    ? null
    : rankTransition(myRatingBefore, myRatingBefore + myRatingChange);
  const overdue = match.status === 'ready' && isMatchOverdue(match.expires_at);
  const baselineWin = ratingPreview
    ? (isPlayerOne ? ratingPreview.player_one_win_change : ratingPreview.player_two_win_change)
    : null;
  const baselineLoss = ratingPreview
    ? (isPlayerOne ? ratingPreview.player_one_loss_change : ratingPreview.player_two_loss_change)
    : null;
  const projectedChange = useMemo(() => {
    if (!ratingPreview || validateMatchScore(myScore, theirScore)) return null;
    const selectedWinnerHasHigherScore = winnerId === currentUserId
      ? myScore > theirScore
      : theirScore > myScore;
    if (!selectedWinnerHasHigherScore) return null;
    const playerOneScore = isPlayerOne ? myScore : theirScore;
    const playerTwoScore = isPlayerOne ? theirScore : myScore;
    const result = calculateElo(
      ratingPreview.player_one_rating,
      ratingPreview.player_two_rating,
      playerOneScore,
      playerTwoScore,
    );
    return isPlayerOne ? result.eloChangeA : result.eloChangeB;
  }, [currentUserId, isPlayerOne, myScore, ratingPreview, theirScore, winnerId]);
  const calculation = match.rating_calculation;
  const disputeDeadline = match.confirmed_at ? new Date(match.confirmed_at).getTime() + 48 * 60 * 60 * 1000 : 0;
  const canOpenDispute = match.status === 'confirmed' && !dispute && disputeDeadline > Date.now();

  useEffect(() => {
    if (mine != null && theirs != null) {
      setMyScore(mine);
      setTheirScore(theirs);
      setWinnerId(match.winner_id || (mine > theirs ? currentUserId : opponent?.id || currentUserId));
    }
  }, [currentUserId, match.winner_id, mine, opponent?.id, theirs]);

  useEffect(() => {
    const matchChannel = supabase
      .channel(`match-row-${match.id}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'matches', filter: `id.eq.${match.id}` },
        (payload) => {
          const next = payload.new as Match;
          setMatch((current) => ({ ...current, ...next }));
          if (next.status === 'confirmed') toast.success('Result finalized — ratings updated!', { icon: '🎉' });
          if (next.status === 'canceled') toast.success('Match canceled with mutual approval');
        },
      )
      .subscribe();
    return () => { void supabase.removeChannel(matchChannel); };
  }, [match.id, supabase]);

  const scorePayload = () => {
    const winnerScore = winnerId === currentUserId ? myScore : theirScore;
    const loserScore = winnerId === currentUserId ? theirScore : myScore;
    const error = validateMatchScore(myScore, theirScore);
    if (error) throw new Error(error);
    if (winnerScore <= loserScore) throw new Error('The selected winner must have the higher score');
    return { winner_id: winnerId, winner_score: winnerScore, loser_score: loserScore };
  };

  const call = async (url: string, body: object, key: string) => {
    setLoading(key);
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Request failed');
      router.refresh();
      return data;
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Request failed');
      router.refresh();
      throw error;
    } finally {
      setLoading(null);
    }
  };

  const prepareReport = () => {
    try {
      scorePayload();
      setShowReportConfirmation(true);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Invalid score');
    }
  };

  const submitReport = async () => {
    let payload: ReturnType<typeof scorePayload>;
    try {
      payload = scorePayload();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Invalid score');
      return;
    }
    try {
      const result = await call(`/api/matches/${match.id}/report`, payload, 'report');
      if (result.status === 'awaiting_independent_report') {
        const playerOneScore = isPlayerOne ? myScore : theirScore;
        const playerTwoScore = isPlayerOne ? theirScore : myScore;
        setMySubmission({
          id: result.submission_id || 'pending-refresh',
          match_id: match.id,
          submitted_by: currentUserId,
          winner_id: winnerId,
          player_one_score: playerOneScore,
          player_two_score: playerTwoScore,
          created_at: new Date().toISOString(),
        });
        setShowReportConfirmation(false);
        toast.success('Report saved. Ratings stay unchanged until your opponent independently reports the same result.');
        return;
      }
      const change = isPlayerOne ? result.player_one_change : result.player_two_change;
      setShowReportConfirmation(false);
      setResultSummary({
        won: result.match?.winner_id === currentUserId,
        change,
        placementBefore: result.placement_before,
        placementAfter: result.placement_after,
        placementChange: result.placement_change || 0,
      });
      toast.success(
        result.already_finalized
          ? 'This result was already finalized.'
          : `Result finalized! ${change >= 0 ? '+' : ''}${change} ELO`,
        { icon: '🎉' },
      );
    } catch {}
  };

  const cancellationAction = async (action: 'request' | 'approve' | 'decline') => {
    try {
      const result = await call(`/api/matches/${match.id}/cancellation`, { action }, `cancel-${action}`);
      if (result.status === 'pending') {
        setCancellationRequest({
          id: result.request_id,
          match_id: match.id,
          requested_by: currentUserId,
          responded_by: null,
          status: 'pending',
          created_at: new Date().toISOString(),
          responded_at: null,
        });
        toast.success('Cancellation requested');
      } else if (result.status === 'canceled') {
        setMatch((current) => ({ ...current, status: 'canceled' }));
        setCancellationRequest(null);
        toast.success('Match canceled');
      } else {
        setCancellationRequest(null);
        toast.success('Cancellation declined; the match remains active');
      }
    } catch {}
  };

  const submitDispute = async () => {
    const payload: Record<string, unknown> = { reason: disputeReason, resolution: disputeResolution };
    if (disputeResolution === 'correction') {
      const winnerScore = correctionWinnerId === currentUserId ? correctionMyScore : correctionTheirScore;
      const loserScore = correctionWinnerId === currentUserId ? correctionTheirScore : correctionMyScore;
      const validation = validateMatchScore(correctionMyScore, correctionTheirScore);
      if (validation || winnerScore <= loserScore) {
        toast.error(validation || 'The corrected winner must have the higher score');
        return;
      }
      payload.winner_id = correctionWinnerId;
      payload.winner_score = winnerScore;
      payload.loser_score = loserScore;
    }
    try {
      const result = await call(`/api/matches/${match.id}/dispute`, payload, 'dispute-create');
      setDispute({
        id: result.dispute_id, match_id: match.id, opened_by: currentUserId,
        reason: disputeReason, requested_resolution: disputeResolution,
        original_winner_id: match.winner_id!, original_player_one_score: match.player_one_score!, original_player_two_score: match.player_two_score!,
        proposed_winner_id: disputeResolution === 'correction' ? correctionWinnerId : match.winner_id,
        proposed_player_one_score: disputeResolution === 'correction' ? (isPlayerOne ? correctionMyScore : correctionTheirScore) : match.player_one_score,
        proposed_player_two_score: disputeResolution === 'correction' ? (isPlayerOne ? correctionTheirScore : correctionMyScore) : match.player_two_score,
        status: 'pending', responded_by: null, response: null, responded_at: null,
        expires_at: result.expires_at, escalated_at: null, created_at: new Date().toISOString(),
      });
      setShowDisputeForm(false);
      toast.success('Dispute sent to your opponent. Ratings are unchanged.');
    } catch {}
  };

  const respondDispute = async (action: 'approve' | 'decline') => {
    if (!dispute) return;
    try {
      const result = await call(`/api/disputes/${dispute.id}/respond`, { action }, `dispute-${action}`);
      const escalated = result.status === 'admin_review';
      setDispute(escalated ? { ...dispute, status: 'admin_review', response: action === 'decline' ? 'declined' : null } : null);
      toast.success(escalated ? 'Dispute escalated to an administrator. Ratings remain unchanged.' : `Correction applied. ${result.replayed_matches || 0} ratings replayed.`);
    } catch {}
  };

  const Score = ({ one, two }: { one: number | null; two: number | null }) => (
    <div className="grid grid-cols-2 gap-3 rounded-3xl bg-accent-gray-50 p-5 text-center">
      <div><p className="truncate text-sm font-bold text-accent-gray-500">{match.player_one?.display_name}</p><p className="text-5xl font-black text-primary-purple">{one}</p></div>
      <div><p className="truncate text-sm font-bold text-accent-gray-500">{match.player_two?.display_name}</p><p className="text-5xl font-black text-primary-purple">{two}</p></div>
    </div>
  );

  return (
    <main className="min-h-screen bg-accent-gray-50 px-4 py-6">
      <div className="mx-auto max-w-xl">
        <header className="mb-6">
          <p className="text-sm font-bold text-primary-purple">Ranked match</p>
          <h1 className="text-3xl font-black">You vs {opponent?.display_name}</h1>
          <div className="mt-3 flex flex-wrap items-center gap-2">
            {isPlayerOne && match.player_one && <RankBadge elo={match.player_one.current_elo} totalGames={match.player_one.total_wins + match.player_one.total_losses} compact />}
            {!isPlayerOne && match.player_two && <RankBadge elo={match.player_two.current_elo} totalGames={match.player_two.total_wins + match.player_two.total_losses} compact />}
            <span className="text-xs font-black text-accent-gray-400">VS</span>
            {opponent && <RankBadge elo={opponent.current_elo} totalGames={opponent.total_wins + opponent.total_losses} compact />}
          </div>
          {match.status === 'ready' && match.expires_at && !overdue && (
            <div className="mt-2 text-sm font-bold text-accent-gray-500"><p>Submit before {deadlineFormatter.format(new Date(match.expires_at))}</p><DeadlineCountdown deadline={match.expires_at} className="mt-1 block" /></div>
          )}
        </header>

        {match.status === 'confirmed' && (
          <section className="rounded-3xl border-2 border-green-300 bg-white p-6 shadow-lg">
            <p className="font-black uppercase text-green-700">Result finalized</p>
            <div className="mt-4"><Score one={match.player_one_score} two={match.player_two_score} /></div>
            <div className="mt-5 flex items-center justify-between rounded-2xl bg-green-50 p-4">
              <span className="font-bold">Your rating change</span>
              <span className={`text-2xl font-black ${myRatingChange >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                {myRatingChange >= 0 ? '+' : ''}{myRatingChange}
              </span>
            </div>
            {myRankTransition?.changed && (
              <div className={`mt-4 rounded-2xl p-5 text-center ${myRankTransition.direction === 'promotion' ? 'bg-primary-purple/10 text-primary-purple' : 'bg-amber-50 text-amber-800'}`}>
                <p className="text-sm font-black uppercase">{myRankTransition.direction === 'promotion' ? 'Rank promotion' : 'Rank demotion'}</p>
                <p className="mt-1 text-2xl font-black">{myRankTransition.beforeTier} → {myRankTransition.afterTier}</p>
              </div>
            )}
            {calculation && (
              <div className="mt-4 rounded-2xl border border-green-200 p-4">
                <p className="font-black text-accent-gray-800">Rating breakdown</p>
                <div className="mt-3 grid grid-cols-2 gap-3 text-sm">
                  <div><p className="text-accent-gray-500">Winner expectation</p><p className="font-black">{Math.round(calculation.winner_expected * 100)}%</p></div>
                  <div><p className="text-accent-gray-500">K-factor</p><p className="font-black">{calculation.k_factor}</p></div>
                  <div><p className="text-accent-gray-500">Base change</p><p className="font-black">+{calculation.base_delta}</p></div>
                  <div><p className="text-accent-gray-500">Score adjustment</p><p className="font-black">+{calculation.margin_bonus}</p></div>
                  <div><p className="text-accent-gray-500">Winning margin</p><p className="font-black">{calculation.score_margin} points</p></div>
                  <div><p className="text-accent-gray-500">Final transfer</p><p className="font-black">{calculation.final_delta} ELO</p></div>
                </div>
                <p className="mt-3 text-xs text-accent-gray-500">Exactly zero-sum: the winner gains what the loser gives up.</p>
              </div>
            )}
          </section>
        )}

        {match.status === 'confirmed' && dispute && (
          <section className="mt-5 rounded-3xl border-2 border-amber-300 bg-amber-50 p-6">
            <p className="text-sm font-black uppercase text-amber-700">Result dispute</p>
            {dispute.status === 'admin_review' ? (
              <><h2 className="mt-2 text-xl font-black text-amber-900">Awaiting administrator review</h2><p className="mt-1 text-sm text-amber-800">The recorded result and ratings remain unchanged until an administrator resolves the dispute.</p></>
            ) : dispute.opened_by === currentUserId ? (
              <><h2 className="mt-2 text-xl font-black text-amber-900">Waiting for {opponent?.display_name}</h2><p className="mt-1 text-sm text-amber-800">Your {dispute.requested_resolution === 'void' ? 'void request' : 'correction'} does not change ratings unless they approve it. No response will escalate it for review.</p></>
            ) : (
              <>
                <h2 className="mt-2 text-xl font-black text-amber-900">{opponent?.display_name} requested a {dispute.requested_resolution}</h2>
                <p className="mt-1 text-sm text-amber-800">Approve to apply it and replay affected ratings, or decline to escalate without changing the current result.</p>
                {dispute.requested_resolution === 'correction' && <p className="mt-3 rounded-xl bg-white p-3 font-black text-amber-900">Proposed score: {dispute.proposed_player_one_score}–{dispute.proposed_player_two_score}</p>}
                <div className="mt-4 grid grid-cols-2 gap-3">
                  <button disabled={loading !== null} onClick={() => respondDispute('decline')} className="min-h-12 rounded-xl border-2 border-amber-400 bg-white font-bold text-amber-800 disabled:opacity-50">Decline & escalate</button>
                  <button disabled={loading !== null} onClick={() => respondDispute('approve')} className="min-h-12 rounded-xl bg-green-600 font-bold text-white disabled:opacity-50">Approve</button>
                </div>
              </>
            )}
            {dispute.expires_at && dispute.status === 'pending' && <p className="mt-3 text-xs font-bold text-amber-700">Response due {deadlineFormatter.format(new Date(dispute.expires_at))}</p>}
          </section>
        )}

        {canOpenDispute && !showDisputeForm && (
          <button onClick={() => setShowDisputeForm(true)} className="mt-5 min-h-12 w-full rounded-2xl border-2 border-amber-300 bg-white font-bold text-amber-800">Dispute this result</button>
        )}

        {canOpenDispute && showDisputeForm && (
          <section className="mt-5 rounded-3xl border-2 border-amber-300 bg-white p-6 shadow-lg">
            <h2 className="text-2xl font-black">Request a correction</h2>
            <p className="mt-1 text-sm text-accent-gray-600">Ratings stay unchanged until your opponent approves or an administrator decides.</p>
            <label className="mt-5 block text-sm font-black">What is wrong?</label>
            <select value={disputeReason} onChange={(event) => {const reason=event.target.value as typeof disputeReason;setDisputeReason(reason);if(reason==='match_never_happened')setDisputeResolution('void');}} className="mt-2 h-12 w-full rounded-xl border-2 border-accent-gray-200 px-3">
              <option value="incorrect_score">Incorrect score</option>
              <option value="incorrect_winner">Incorrect winner</option>
              <option value="match_never_happened">Match never happened</option>
              <option value="other">Other</option>
            </select>
            <div className="mt-4 grid grid-cols-2 gap-3">
              <button onClick={() => setDisputeResolution('correction')} disabled={disputeReason==='match_never_happened'} className={`min-h-12 rounded-xl border-2 font-black disabled:opacity-40 ${disputeResolution==='correction'?'border-primary-purple bg-primary-purple/10 text-primary-purple':'border-accent-gray-200'}`}>Correct result</button>
              <button onClick={() => setDisputeResolution('void')} className={`min-h-12 rounded-xl border-2 font-black ${disputeResolution==='void'?'border-red-400 bg-red-50 text-red-700':'border-accent-gray-200'}`}>Void match</button>
            </div>
            {disputeResolution === 'correction' && (
              <>
                <div className="mt-4 grid grid-cols-2 gap-3">
                  <button onClick={() => setCorrectionWinnerId(currentUserId)} className={`min-h-12 rounded-xl border-2 font-black ${correctionWinnerId===currentUserId?'border-primary-purple bg-primary-purple/10 text-primary-purple':'border-accent-gray-200'}`}>I won</button>
                  <button onClick={() => setCorrectionWinnerId(opponent?.id || '')} className={`min-h-12 rounded-xl border-2 font-black ${correctionWinnerId===opponent?.id?'border-primary-purple bg-primary-purple/10 text-primary-purple':'border-accent-gray-200'}`}>{opponent?.display_name} won</button>
                </div>
                <div className="mt-4 grid gap-3 sm:grid-cols-2">
                  <ScoreStepper label="You" value={correctionMyScore} onChange={setCorrectionMyScore} />
                  <ScoreStepper label={opponent?.display_name || 'Opponent'} value={correctionTheirScore} onChange={setCorrectionTheirScore} />
                </div>
              </>
            )}
            <div className="mt-5 grid grid-cols-2 gap-3">
              <button onClick={() => setShowDisputeForm(false)} className="min-h-12 rounded-xl border-2 border-accent-gray-200 font-bold">Cancel</button>
              <button disabled={loading !== null} onClick={submitDispute} className="min-h-12 rounded-xl bg-amber-600 font-black text-white disabled:opacity-50">{loading==='dispute-create'?'Sending…':'Send request'}</button>
            </div>
            <p className="mt-3 text-center text-xs text-accent-gray-500">Disputes must be opened within 48 hours of finalization.</p>
          </section>
        )}

        {match.status === 'ready' && !overdue && (
          <div className="space-y-6">
            {match.verification_mode === 'dual' && (
              <section className="rounded-2xl border-2 border-blue-300 bg-blue-50 p-5">
                <p className="font-black text-blue-900">Independent reporting enabled</p>
                <p className="mt-1 text-sm text-blue-800">
                  Each player submits privately. Ratings update only when both reports match; conflicting reports close the match without changing ratings and alert an administrator.
                </p>
                {mySubmission && (
                  <p className="mt-3 rounded-xl bg-white p-3 text-sm font-black text-blue-900">
                    Your report is saved. Waiting for {opponent?.display_name} to report independently.
                  </p>
                )}
              </section>
            )}
            {cancellationRequest && (
              <section className="rounded-2xl border-2 border-amber-300 bg-amber-50 p-5">
                {cancellationRequest.requested_by === currentUserId ? (
                  <>
                    <p className="font-black text-amber-800">Cancellation requested</p>
                    <p className="mt-1 text-sm text-amber-700">Waiting for {opponent?.display_name}. The match deadline is unchanged.</p>
                  </>
                ) : (
                  <>
                    <p className="font-black text-amber-800">Cancellation requested by {opponent?.display_name}</p>
                    <p className="mt-1 text-sm text-amber-700">Approve to cancel with no rating changes, or decline to keep playing.</p>
                    <div className="mt-4 grid grid-cols-2 gap-3">
                      <button disabled={loading !== null} onClick={() => cancellationAction('decline')} className="min-h-12 rounded-xl border-2 border-amber-400 bg-white font-bold text-amber-800 disabled:opacity-50">Decline</button>
                      <button disabled={loading !== null} onClick={() => cancellationAction('approve')} className="min-h-12 rounded-xl bg-amber-600 font-bold text-white disabled:opacity-50">Approve</button>
                    </div>
                  </>
                )}
              </section>
            )}

            <section className="rounded-3xl bg-white p-6 shadow-lg">
              <h2 className="text-2xl font-black">Report the result</h2>
              <p className="mt-1 text-sm text-accent-gray-600">
                {match.verification_mode === 'dual'
                  ? 'Your report stays private and ratings remain unchanged until both independent reports match.'
                  : 'The first valid submission finalizes the score and ratings immediately.'}
              </p>
              {baselineWin != null && baselineLoss != null && (
                <div className="mt-4 grid grid-cols-2 gap-3 rounded-2xl bg-blue-50 p-4 text-center">
                  <div><p className="text-xs font-bold uppercase text-blue-600">If you win</p><p className="text-2xl font-black text-green-600">+{baselineWin}</p></div>
                  <div><p className="text-xs font-bold uppercase text-blue-600">If you lose</p><p className="text-2xl font-black text-red-600">{baselineLoss}</p></div>
                  <p className="col-span-2 text-xs text-blue-700">Close-score estimate. The submitted margin can adjust the transfer by up to 10%.</p>
                </div>
              )}
              <div className="mt-5 grid grid-cols-2 gap-3">
                {[
                  { id: currentUserId, label: 'I won' },
                  { id: opponent?.id || '', label: `${opponent?.display_name} won` },
                ].map((choice) => (
                  <button key={choice.id} onClick={() => setWinnerId(choice.id)} className={`min-h-14 rounded-2xl border-2 font-black ${winnerId === choice.id ? 'border-primary-purple bg-primary-purple/10 text-primary-purple' : 'border-accent-gray-200 bg-white'}`}>
                    {choice.label}
                  </button>
                ))}
              </div>
              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                <ScoreStepper label="You" value={myScore} onChange={setMyScore} />
                <ScoreStepper label={opponent?.display_name || 'Opponent'} value={theirScore} onChange={setTheirScore} />
              </div>
              {projectedChange != null && (
                <p className="mt-4 rounded-xl bg-primary-purple/5 p-3 text-center font-bold text-primary-purple">
                  Selected score estimate: {projectedChange >= 0 ? '+' : ''}{projectedChange} ELO
                </p>
              )}
              <button onClick={prepareReport} disabled={loading !== null || Boolean(mySubmission)} className="mt-5 min-h-14 w-full rounded-2xl gradient-purple text-lg font-black text-white disabled:opacity-50">
                {mySubmission ? 'Report submitted — awaiting opponent' : 'Review Final Result'}
              </button>
            </section>

            {!cancellationRequest && (
              <button onClick={() => cancellationAction('request')} disabled={loading !== null} className="min-h-12 w-full rounded-2xl border-2 border-red-200 bg-white font-bold text-red-600 disabled:opacity-50">
                {loading === 'cancel-request' ? 'Requesting…' : 'Request Cancellation'}
              </button>
            )}
          </div>
        )}

        {(['expired', 'voided', 'canceled'].includes(match.status) || overdue) && (
          <section className="rounded-3xl bg-white p-7 text-center shadow">
            <p className="text-4xl">{match.status === 'canceled' ? '🤝' : match.status === 'voided' ? '↩️' : '⌛'}</p>
            <h2 className="mt-3 text-2xl font-black">{match.status === 'canceled' ? 'Match canceled' : match.status === 'voided' ? 'Match voided' : 'Match expired'}</h2>
            <p className="mt-2 text-accent-gray-500">{match.status === 'voided' ? 'The result was removed and affected ratings were replayed.' : 'No rating or record changes were applied.'}</p>
          </section>
        )}

        {showReportConfirmation && (
          <div role="dialog" aria-modal="true" className="fixed inset-0 z-[80] flex items-end bg-black/55 p-4 sm:items-center sm:justify-center">
            <section className="w-full max-w-md rounded-3xl bg-white p-6 shadow-2xl">
              <p className="text-sm font-black uppercase text-primary-purple">Final ranked result</p>
              <h2 className="mt-1 text-2xl font-black">Confirm before submitting</h2>
              <p className="mt-2 text-sm text-accent-gray-600">
                {match.verification_mode === 'dual'
                  ? 'This report is private. Ratings update only if your opponent independently submits the same result.'
                  : 'The first valid submission updates both players immediately. Corrections require mutual approval.'}
              </p>
              <div className="mt-5"><Score one={isPlayerOne ? myScore : theirScore} two={isPlayerOne ? theirScore : myScore} /></div>
              <p className="mt-4 text-center text-lg font-black">Winner: {winnerId === currentUserId ? 'You' : opponent?.display_name}</p>
              {projectedChange != null && <p className={`mt-2 text-center font-black ${projectedChange >= 0 ? 'text-green-600' : 'text-red-600'}`}>Estimated change: {projectedChange >= 0 ? '+' : ''}{projectedChange} ELO</p>}
              <div className="mt-6 grid grid-cols-2 gap-3">
                <button disabled={loading !== null} onClick={() => setShowReportConfirmation(false)} className="min-h-12 rounded-xl border-2 border-accent-gray-200 font-bold">Go back</button>
                <button disabled={loading !== null} onClick={submitReport} className="min-h-12 rounded-xl bg-green-600 font-black text-white disabled:opacity-50">{loading === 'report' ? 'Finalizing…' : 'Confirm result'}</button>
              </div>
            </section>
          </div>
        )}

        {resultSummary && (
          <div role="dialog" aria-modal="true" className="fixed inset-0 z-[90] flex items-center justify-center bg-accent-gray-950/80 p-4">
            <section className={`w-full max-w-md rounded-3xl p-7 text-center text-white shadow-2xl ${resultSummary.won ? 'bg-gradient-to-br from-green-600 to-emerald-800' : 'bg-gradient-to-br from-slate-700 to-slate-950'}`}>
              <p className="text-6xl">{resultSummary.won ? '🏆' : '🏓'}</p>
              <p className="mt-4 text-sm font-black uppercase tracking-widest text-white/75">{resultSummary.won ? 'Victory' : 'Defeat'}</p>
              <h2 className="mt-1 text-4xl font-black">{resultSummary.change >= 0 ? '+' : ''}{resultSummary.change} ELO</h2>
              {resultSummary.placementAfter != null && <div className="mt-5 rounded-2xl bg-white/10 p-4"><p className="text-sm font-bold text-white/75">All-time placement</p><p className="text-3xl font-black">#{resultSummary.placementAfter}</p>{resultSummary.placementChange !== 0 && <p className="mt-1 text-sm font-black">{resultSummary.placementChange > 0 ? `↑ ${resultSummary.placementChange}` : `↓ ${Math.abs(resultSummary.placementChange)}`} place{Math.abs(resultSummary.placementChange) === 1 ? '' : 's'}</p>}</div>}
              <div className="mt-6 grid grid-cols-2 gap-3"><button onClick={() => setResultSummary(null)} className="min-h-12 rounded-xl border-2 border-white/30 font-bold">View result</button><button onClick={() => { window.location.href='/dashboard'; }} className="min-h-12 rounded-xl bg-white font-black text-accent-gray-900">Dashboard</button></div>
            </section>
          </div>
        )}
      </div>
    </main>
  );
}
