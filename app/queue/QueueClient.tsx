'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import ScoreStepper from '@/components/ScoreStepper';
import RankedDecisionModal, { type RankedDecisionPlayer } from '@/components/RankedDecisionModal';
import { defaultMatchScores, validateMatchScore } from '@/lib/match-result';
import {
  canReportQueueOutcome,
  canRequestQueueSwap,
  needsQueueCheckIn,
  queueGameSecondsRemaining,
  queueSecondsUntil,
  type QueueMemberStatus,
} from '@/lib/queue';
import { isActiveQueueStatus, isQueueBackendHealthy, isRetryableQueueError, queueErrorMessage } from '@/lib/queue-client';
import styles from './QueueClient.module.css';
import BeaverAvatar from '@/components/BeaverAvatar';
import type { AvatarConfig } from '@/lib/avatar';

interface QueueMember { user_id: string; display_name: string; status: QueueMemberStatus; queue_position: number; joined_at: string; }
interface TableState { id: number; phase: 'idle' | 'called' | 'playing'; king_id: string | null; challenger_id: string | null; call_expires_at: string | null; game_id: string | null; game_started_at: string | null; game_expires_at: string | null; king_confirmed_at: string | null; challenger_confirmed_at: string | null; solo_expires_at: string | null; afk_reporter_id: string | null; afk_target_id: string | null; afk_expires_at: string | null; }
interface QueueGame { id: string; king_id: string; challenger_id: string; king_name: string; challenger_name: string; winner_id: string; loser_id: string; completed_at: string; }
interface SwapRequest { id: string; requester_id: string; target_id: string; requester_position: number; target_position: number; status: 'pending' | 'accepted' | 'declined' | 'expired' | 'canceled'; expires_at: string; }
interface RankedRequest { id: string; queue_game_id: string; requester_id: string; opponent_id: string; status: 'pending' | 'accepted' | 'declined' | 'canceled'; match_id: string | null; created_at: string; responded_at: string | null; }
interface QueueProfile extends RankedDecisionPlayer { id: string; avatar_config?: AvatarConfig | null; }

const formatTimer = (seconds: number) => `${Math.floor(Math.max(0, seconds) / 60)}:${String(Math.max(0, seconds) % 60).padStart(2, '0')}`;

export default function QueueClient({ currentUserId }: { currentUserId: string }) {
  const supabase = useMemo(() => createClient(), []);
  const [table, setTable] = useState<TableState | null>(null);
  const [members, setMembers] = useState<QueueMember[]>([]);
  const [games, setGames] = useState<QueueGame[]>([]);
  const [swaps, setSwaps] = useState<SwapRequest[]>([]);
  const [rankedRequests, setRankedRequests] = useState<RankedRequest[]>([]);
  const [queueProfiles, setQueueProfiles] = useState<QueueProfile[]>([]);
  const [now, setNow] = useState(Date.now());
  const [busy, setBusy] = useState('');
  const [loading, setLoading] = useState(true);
  const [outcomeChoice, setOutcomeChoice] = useState<'won' | 'lost' | null>(null);
  const [rankedWinnerId, setRankedWinnerId] = useState(currentUserId);
  const [rankedMyScore, setRankedMyScore] = useState(11);
  const [rankedTheirScore, setRankedTheirScore] = useState(9);
  const [rankedStatus, setRankedStatus] = useState('');
  const [dismissedRankedRequestId, setDismissedRankedRequestId] = useState<string | null>(null);
  const [loadError, setLoadError] = useState('');
  const [backendError, setBackendError] = useState('');
  const [actionError, setActionError] = useState('');
  const [rankedError, setRankedError] = useState('');
  const [heartbeatError, setHeartbeatError] = useState('');
  const reading = useRef(false);
  const heartbeatFailures = useRef(0);
  const syncedExpiration = useRef('');
  const me = members.find((member) => member.user_id === currentUserId);

  useEffect(() => {
    let cancelled = false;
    void supabase.rpc('beaver_queue_health_v9').then(({ data, error }) => {
      if (cancelled) return;
      if (error) setBackendError(queueErrorMessage(error, 'Unable to verify the queue database version.'));
      else if (!isQueueBackendHealthy(data)) setBackendError('The queue database is out of date. Apply migration 20261104_05, then reload this page.');
      else setBackendError('');
    });
    return () => { cancelled = true; };
  }, [supabase]);

  const refresh = useCallback(async () => {
    if (reading.current) return;
    reading.current = true;
    try {
      const [stateResponse, memberResponse, gameResponse, swapResponse, rankedResponse, profileResponse, avatarResponse] = await Promise.all([
        supabase.from('beaver_queue_table').select('*').eq('id', 1).single(),
        supabase.from('beaver_queue_members').select('*').order('queue_position'),
        supabase.from('beaver_queue_games').select('*').eq('status', 'completed').order('completed_at', { ascending: false }).limit(10),
        supabase.from('beaver_queue_swap_requests').select('*').eq('status', 'pending').order('created_at'),
        supabase.from('beaver_queue_ranked_requests').select('*').order('created_at', { ascending: false }).limit(10),
        supabase.from('profiles').select('id,display_name,current_elo,total_wins,total_losses'),
        supabase.from('profiles').select('id,avatar_config'),
      ]);
      if (stateResponse.error) throw stateResponse.error;
      if (memberResponse.error) throw memberResponse.error;
      if (gameResponse.error) throw gameResponse.error;
      if (swapResponse.error) throw swapResponse.error;
      if (rankedResponse.error) throw rankedResponse.error;
      if (profileResponse.error) throw profileResponse.error;
      setTable(stateResponse.data as TableState);
      setMembers((memberResponse.data ?? []) as QueueMember[]);
      setGames((gameResponse.data ?? []) as QueueGame[]);
      setSwaps((swapResponse.data ?? []) as SwapRequest[]);
      setRankedRequests((rankedResponse.data ?? []) as RankedRequest[]);
      const avatars = new Map((avatarResponse.data ?? []).map((profile) => [profile.id, profile.avatar_config]));
      setQueueProfiles(((profileResponse.data ?? []) as QueueProfile[]).map((profile) => ({ ...profile, avatar_config: avatars.get(profile.id) ?? null })));
      setLoadError('');
    } catch (caught) { setLoadError(queueErrorMessage(caught, 'Unable to load the queue.')); }
    finally { reading.current = false; setLoading(false); }
  }, [supabase]);

  useEffect(() => {
    void refresh();
    const poll = window.setInterval(() => void refresh(), 4000);
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    const focus = () => void refresh();
    window.addEventListener('focus', focus);
    const channel = supabase.channel('beaver-queue-live-v4')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_table' }, focus)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_members' }, focus)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_games' }, focus)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_swap_requests' }, focus)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_ranked_requests' }, focus)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'profiles' }, focus)
      .subscribe();
    return () => { window.clearInterval(poll); window.clearInterval(timer); window.removeEventListener('focus', focus); void supabase.removeChannel(channel); };
  }, [refresh, supabase]);

  useEffect(() => {
    if (!isActiveQueueStatus(me?.status)) { heartbeatFailures.current = 0; setHeartbeatError(''); return; }
    let cancelled = false;
    const heartbeat = async () => {
      if (heartbeatFailures.current >= 3) return;
      const result = await supabase.rpc('beaver_queue_heartbeat_v1');
      if (cancelled) return;
      if (result.error) {
        heartbeatFailures.current = isRetryableQueueError(result.error) ? heartbeatFailures.current + 1 : 3;
        const paused = heartbeatFailures.current >= 3 ? ' Automatic heartbeats are paused until this page is reloaded.' : '';
        setHeartbeatError(`${queueErrorMessage(result.error, 'Unable to keep your queue spot active.')}${paused}`);
      } else { heartbeatFailures.current = 0; setHeartbeatError(''); }
    };
    void heartbeat();
    const interval = window.setInterval(() => void heartbeat(), 30_000);
    return () => { cancelled = true; window.clearInterval(interval); };
  }, [me?.status, supabase]);

  const action = async (key: string, name: string, args: Record<string, unknown> = {}) => {
    if (busy) return;
    if (backendError) { setActionError(backendError); return; }
    setBusy(key); setActionError('');
    try {
      const result = await supabase.rpc(name, args);
      if (result.error) throw result.error;
      await refresh();
    } catch (caught) { setActionError(queueErrorMessage(caught, 'Something went wrong.')); await refresh(); }
    finally { setBusy(''); }
  };

  const rankedAction = async (key: string, name: string, args: Record<string, unknown> = {}) => {
    if (busy) return;
    if (backendError) { setRankedError(backendError); return; }
    setBusy(key); setRankedError('');
    try {
      const result = await supabase.rpc(name, args);
      if (result.error) throw result.error;
      await refresh();
    } catch (caught) {
      setRankedError(queueErrorMessage(caught, 'Unable to update the Ranked request.'));
      await refresh();
    } finally { setBusy(''); }
  };

  useEffect(() => {
    setOutcomeChoice(null);
    setRankedError('');
    setRankedStatus('');
    setRankedWinnerId(currentUserId);
    setRankedMyScore(11);
    setRankedTheirScore(9);
    setDismissedRankedRequestId(null);
  }, [currentUserId, table?.game_id, table?.phase]);

  const waiting = members.filter((member) => member.status === 'waiting').sort((a, b) => a.queue_position - b.queue_position || a.user_id.localeCompare(b.user_id));
  const activeMembers = members
    .filter((member) => isActiveQueueStatus(member.status))
    .sort((a, b) => a.queue_position - b.queue_position || a.user_id.localeCompare(b.user_id));
  const myActiveIndex = activeMembers.findIndex((member) => member.user_id === currentUserId);
  const activePosition = (userId: string) => activeMembers.findIndex((member) => member.user_id === userId) + 1;
  const active = isActiveQueueStatus(me?.status);
  const king = table?.king_id ?? null;
  const challenger = table?.challenger_id ?? null;
  const opponentId = currentUserId === king ? challenger : king;
  const amPlaying = canReportQueueOutcome(table?.phase, currentUserId, king, challenger);
  const callSeconds = queueSecondsUntil(table?.call_expires_at ?? null, now);
  const gameSeconds = queueGameSecondsRemaining(table?.game_expires_at ?? null, now);
  const soloSeconds = queueSecondsUntil(table?.solo_expires_at ?? null, now);
  const afkSeconds = queueSecondsUntil(table?.afk_expires_at ?? null, now);
  const afkPending = Boolean(table?.afk_target_id && table?.afk_expires_at);
  const isAfkTarget = table?.afk_target_id === currentUserId;
  const incomingSwap = swaps.find((swap) => swap.target_id === currentUserId);
  const outgoingSwap = swaps.find((swap) => swap.requester_id === currentUserId);
  const rankedRequest = rankedRequests.find((request) => request.queue_game_id === table?.game_id);
  const incomingRankedRequest = rankedRequest?.status === 'pending' && rankedRequest.opponent_id === currentUserId;
  const showRankedRequestPopup = incomingRankedRequest && rankedRequest.id !== dismissedRankedRequestId;
  const rankedRequester = queueProfiles.find((profile) => profile.id === rankedRequest?.requester_id);
  const outgoingRankedRequest = rankedRequest?.status === 'pending' && rankedRequest.requester_id === currentUserId;
  const acceptedRankedRequest = rankedRequest?.status === 'accepted' && Boolean(rankedRequest.match_id);
  const checkInPending = needsQueueCheckIn(
    table?.phase,
    currentUserId,
    challenger,
    table?.challenger_confirmed_at ?? null,
  );
  const matchActionsAvailable = amPlaying && gameSeconds > 0;
  const nameOf = (id: string | null) => members.find((member) => member.user_id === id)?.display_name ?? 'Player';
  const avatarOf = (id: string | null) => queueProfiles.find((profile) => profile.id === id)?.avatar_config;
  const snapshotName = (game: QueueGame, id: string) => id === game.king_id ? game.king_name : game.challenger_name;

  useEffect(() => {
    const expirationKey = table?.phase === 'playing' && table.game_id && gameSeconds === 0
      ? `game:${table.game_id}`
      : table?.phase === 'playing' && table.afk_expires_at && afkSeconds === 0
        ? `afk:${table.afk_expires_at}`
      : table?.phase === 'called' && table.call_expires_at && callSeconds === 0
        ? `call:${table.call_expires_at}`
        : '';
    if (!expirationKey || syncedExpiration.current === expirationKey) return;
    syncedExpiration.current = expirationKey;
    let cancelled = false;
    void (async () => {
      const result = await supabase.rpc('beaver_queue_tick_v1');
      if (cancelled) return;
      if (result.error) setActionError(queueErrorMessage(result.error, 'Unable to synchronize the expired queue timer.'));
      await refresh();
    })();
    return () => { cancelled = true; };
  }, [afkSeconds, callSeconds, gameSeconds, refresh, supabase, table?.afk_expires_at, table?.call_expires_at, table?.game_id, table?.phase]);

  const confirmOutcome = async () => {
    if (!table?.game_id || !outcomeChoice || gameSeconds === 0) return;
    const outcome = outcomeChoice;
    await action(`outcome-${outcome}`, 'beaver_queue_report_outcome_v2', { p_game_id: table.game_id, p_outcome: outcome });
    setOutcomeChoice(null);
  };

  const chooseRankedWinner = (nextWinnerId: string) => {
    const scores = defaultMatchScores(nextWinnerId === currentUserId);
    setRankedWinnerId(nextWinnerId);
    setRankedMyScore(scores.myScore);
    setRankedTheirScore(scores.theirScore);
  };

  const submitRankedScore = async () => {
    if (!rankedRequest?.match_id || !acceptedRankedRequest || !challenger || !matchActionsAvailable || busy) return;
    const scoreError = validateMatchScore(rankedMyScore, rankedTheirScore);
    const winnerScore = rankedWinnerId === currentUserId ? rankedMyScore : rankedTheirScore;
    const loserScore = rankedWinnerId === currentUserId ? rankedTheirScore : rankedMyScore;
    if (scoreError || winnerScore <= loserScore) {
      setRankedError(scoreError || 'The selected winner must have the higher score');
      return;
    }
    setBusy('ranked-score');
    setRankedError('');
    setRankedStatus('');
    try {
      const result = await supabase.rpc('beaver_queue_submit_ranked_result_v1', {
        p_match: rankedRequest.match_id,
        p_winner: rankedWinnerId,
        p_winner_score: winnerScore,
        p_loser_score: loserScore,
      });
      if (result.error) throw result.error;
      if (result.data?.status === 'awaiting_independent_report') {
        setRankedStatus(`Score submitted. Waiting for ${nameOf(opponentId)}.`);
      }
      await refresh();
    } catch (caught) {
      setRankedError(queueErrorMessage(caught, 'Unable to submit the Ranked score.'));
      await refresh();
    } finally { setBusy(''); }
  };

  return (
    <main className={styles.page}>
      {checkInPending && callSeconds > 0 && <div className={styles.checkInBackdrop}>
        <section className={styles.checkInModal} role="dialog" aria-modal="true" aria-labelledby="queue-check-in-title" aria-describedby="queue-check-in-description">
          <p className={styles.checkInEyebrow}>Match ready</p>
          <h2 id="queue-check-in-title">You&apos;re Up!</h2>
          <p id="queue-check-in-description">Your match is ready. Confirm you&apos;re here to play.</p>
          <strong className={`${styles.checkInCountdown} ${callSeconds <= 15 ? styles.urgent : ''}`} aria-label={`${callSeconds} seconds remaining`}>{formatTimer(callSeconds)}</strong>
          <button autoFocus className={styles.checkInConfirm} disabled={Boolean(busy) || callSeconds === 0} onClick={() => void action('confirm', 'beaver_queue_confirm_v1')}>{busy === 'confirm' ? 'Confirming…' : "I'm Here"}</button>
          <button className={styles.checkInLeave} disabled={Boolean(busy)} onClick={() => void action('modal-leave', 'beaver_queue_leave_v1')}>{busy === 'modal-leave' ? 'Leaving…' : 'Leave Queue'}</button>
        </section>
      </div>}
      {isAfkTarget && afkSeconds > 0 && gameSeconds > 0 && <div className={styles.checkInBackdrop}>
        <section className={styles.checkInModal} role="dialog" aria-modal="true" aria-labelledby="afk-check-in-title" aria-describedby="afk-check-in-description">
          <p className={styles.checkInEyebrow}>Presence check</p>
          <h2 id="afk-check-in-title">Are You Here?</h2>
          <p id="afk-check-in-description">Your opponent reported you as AFK. Confirm you&apos;re still at the table.</p>
          <strong className={`${styles.checkInCountdown} ${afkSeconds <= 15 ? styles.urgent : ''}`} aria-label={`${afkSeconds} seconds remaining`}>{formatTimer(afkSeconds)}</strong>
          <button autoFocus className={styles.checkInConfirm} disabled={Boolean(busy) || afkSeconds === 0 || !matchActionsAvailable} onClick={() => void action('afk-present', 'beaver_queue_confirm_presence_v1')}>{busy === 'afk-present' ? 'Confirming…' : "I'm Here"}</button>
        </section>
      </div>}
      {showRankedRequestPopup && matchActionsAvailable && !isAfkTarget && <RankedDecisionModal
        challenger={rankedRequester}
        busy={Boolean(busy)}
        onDismiss={() => setDismissedRankedRequestId(rankedRequest.id)}
        onDecline={() => void rankedAction('ranked-decline', 'beaver_queue_respond_ranked_v1', { p_request: rankedRequest.id, p_action: 'decline' })}
        onAccept={() => void rankedAction('ranked-accept', 'beaver_queue_respond_ranked_v1', { p_request: rankedRequest.id, p_action: 'accept' })}
      />}
      <div className={styles.shell}>
        <section data-queue-card="live-table" className={`${styles.hero} ${styles.queueHeaderCard}`}>
          <div className={styles.heroMain}>
            <div><h1>Live table <span>queue.</span></h1><p className={styles.heroTagline}>Winner stays. Next plays.</p></div>
            <div className={styles.statRow}><div><strong>{activeMembers.length}</strong><span>At table / active</span></div><div><strong>{waiting.length}</strong><span>Waiting</span></div></div>
          </div>
          <div className={styles.queueControls}>
            {!active && <button className={styles.primaryButton} disabled={Boolean(busy)} onClick={() => void action('join', 'beaver_queue_join_v1')}>{busy === 'join' ? 'Joining…' : 'Join Queue'}</button>}
            {active && <span role="status" className={`${styles.queueState} ${amPlaying ? styles.playingState : styles.queuedState}`}>{amPlaying ? 'Playing' : `#${Math.max(1, myActiveIndex + 1)} in queue`}</span>}
            {active && !amPlaying && <button className={`${styles.secondaryButton} ${styles.leaveButton}`} disabled={Boolean(busy)} onClick={() => void action('leave', 'beaver_queue_leave_v1')}>{busy === 'leave' ? 'Leaving…' : 'Leave Queue'}</button>}
          </div>
        </section>

        {(backendError || actionError || heartbeatError || loadError) && <div role="alert" className={styles.error}>{backendError || actionError || heartbeatError || loadError}</div>}

        <section data-queue-card="current-match" className={`${styles.card} ${styles.currentMatchCard}`}>
          <div className={styles.sectionHeading}><h2>Current Match</h2><span className={styles.pill}>{acceptedRankedRequest ? 'RANKED' : table?.phase === 'playing' ? 'PLAYING' : table?.phase === 'called' ? 'CHECK-IN' : 'READY'}</span></div>
          {loading && !table ? <p className={styles.muted}>Loading current table…</p> : king ? <>
            <div className={styles.tableMatch}>
              <div className={styles.matchPlayer}><BeaverAvatar config={avatarOf(king)} className={styles.beaverAvatar} label={`${nameOf(king)}'s avatar`} /><div className={styles.playerName}><strong>{nameOf(king)}</strong>{king === currentUserId && <span className={styles.youTag}>You</span>}</div><div className={styles.seatLabel}>Holder</div></div>
              <div className={styles.vs}>VS</div>
              <div className={styles.matchPlayer}><BeaverAvatar config={avatarOf(challenger)} className={styles.beaverAvatar} label={`${challenger ? nameOf(challenger) : 'Next player'} avatar`} /><div className={styles.playerName}><strong>{challenger ? nameOf(challenger) : 'Waiting…'}</strong>{challenger === currentUserId && <span className={styles.youTag}>You</span>}</div><div className={styles.seatLabel}>{challenger ? 'Opponent' : 'Next player'}</div></div>
            </div>
            {table?.phase === 'idle' && !challenger && table.solo_expires_at && <div className={styles.soloTimer}><span>Waiting for an opponent</span><strong>{formatTimer(soloSeconds)}</strong></div>}
            {table?.phase === 'called' && <div className={styles.callBanner}><span>{checkInPending ? "You're up — check in now" : 'Waiting for the other player'}</span><strong className={callSeconds <= 15 ? styles.urgent : ''}>{formatTimer(callSeconds)}</strong></div>}
            {checkInPending && <button className={styles.primaryButton} disabled={Boolean(busy) || callSeconds === 0} onClick={() => void action('confirm', 'beaver_queue_confirm_v1')}>{busy === 'confirm' ? 'Checking in…' : 'I’m Here'}</button>}
            {table?.phase === 'playing' && <div className={styles.gamePanel}>
              <div className={styles.gameTimer}><span>Time remaining</span><strong className={gameSeconds <= 60 ? styles.urgent : ''}>{formatTimer(gameSeconds)}</strong></div>
              {isAfkTarget && <div className={styles.afkPrompt}><div><strong>Are you here?</strong><span>Your opponent reported you as AFK.</span></div><strong className={afkSeconds <= 15 ? styles.urgent : ''}>{formatTimer(afkSeconds)}</strong><button disabled={Boolean(busy) || afkSeconds === 0 || !matchActionsAvailable} onClick={() => void action('afk-present', 'beaver_queue_confirm_presence_v1')}>{busy === 'afk-present' ? 'Responding…' : 'I’m Here'}</button></div>}
              {afkPending && !isAfkTarget && <div className={styles.afkStatus}><span>Waiting for {nameOf(table?.afk_target_id ?? null)} to respond to an AFK check</span><strong className={afkSeconds <= 15 ? styles.urgent : ''}>{formatTimer(afkSeconds)}</strong></div>}
              {incomingRankedRequest && dismissedRankedRequestId === rankedRequest.id && <div className={`${styles.rankedStatus} ${styles.rankedReviewStatus}`}><span>{nameOf(rankedRequest.requester_id)} requested a Ranked match.</span><button type="button" disabled={Boolean(busy) || !matchActionsAvailable} onClick={() => setDismissedRankedRequestId(null)}>Review Ranked Request</button></div>}
              {outgoingRankedRequest && <div className={styles.rankedStatus}>Ranked requested. Waiting for {nameOf(rankedRequest.opponent_id)}.</div>}
              {rankedRequest?.status === 'declined' && <div className={styles.rankedStatus}>Ranked request declined. Continue this match as Unranked.</div>}
              {acceptedRankedRequest && <div className={styles.rankedStatus}>Ranked accepted. Submit a valid score before the table timer reaches zero.</div>}
              {rankedStatus && <div className={styles.rankedStatus}>{rankedStatus}</div>}
              {rankedError && <p role="alert" className={styles.rankedError}>{rankedError}</p>}
              {acceptedRankedRequest && amPlaying && !isAfkTarget && <div className={styles.rankedScorePanel}><div className={styles.rankedWinnerActions}><button className={rankedWinnerId === currentUserId ? styles.rankedWinnerSelected : ''} disabled={Boolean(busy)} onClick={() => chooseRankedWinner(currentUserId)}>I won</button><button className={rankedWinnerId === opponentId ? styles.rankedWinnerSelected : ''} disabled={Boolean(busy) || !opponentId} onClick={() => opponentId && chooseRankedWinner(opponentId)}>{nameOf(opponentId)} won</button></div><div className={styles.rankedScoreFields}><ScoreStepper label="You" value={rankedMyScore} onChange={setRankedMyScore} /><ScoreStepper label={nameOf(opponentId)} value={rankedTheirScore} onChange={setRankedTheirScore} /></div><button className={styles.rankedSubmitButton} disabled={Boolean(busy) || !matchActionsAvailable} onClick={() => void submitRankedScore()}>{busy === 'ranked-score' ? 'Finalizing…' : 'Submit Ranked Score'}</button><div className={styles.matchSecondaryActions}>{!afkPending && <button className={styles.afkReportButton} disabled={Boolean(busy) || !matchActionsAvailable} onClick={() => void action('afk-report', 'beaver_queue_report_afk_v1')}>{busy === 'afk-report' ? 'Reporting…' : 'Report AFK'}</button>}</div></div>}
              {!acceptedRankedRequest && amPlaying && !isAfkTarget && (outcomeChoice ? <div className={styles.outcomeConfirm}><p>Confirm you {outcomeChoice}?</p><div><button className={outcomeChoice === 'won' ? styles.winButton : styles.lossButton} disabled={Boolean(busy) || !matchActionsAvailable} onClick={() => void confirmOutcome()}>{busy ? 'Submitting…' : outcomeChoice === 'won' ? 'Confirm Win' : 'Confirm Loss'}</button><button className={styles.cancelButton} disabled={Boolean(busy)} onClick={() => setOutcomeChoice(null)}>Cancel</button></div></div> : <><div className={styles.outcomeActions}><button className={styles.winButton} disabled={Boolean(busy) || !matchActionsAvailable} onClick={() => setOutcomeChoice('won')}>I Won</button><button className={styles.lossButton} disabled={Boolean(busy) || !matchActionsAvailable} onClick={() => setOutcomeChoice('lost')}>I Lost</button></div><div className={styles.matchSecondaryActions}>{!rankedRequest && <button className={styles.rankedGameButton} disabled={Boolean(busy) || !matchActionsAvailable} onClick={() => void rankedAction('ranked-request', 'beaver_queue_request_ranked_v1')}>{busy === 'ranked-request' ? 'Requesting…' : 'Ranked Game'}</button>}{!afkPending && <button className={styles.afkReportButton} disabled={Boolean(busy) || !matchActionsAvailable} onClick={() => void action('afk-report', 'beaver_queue_report_afk_v1')}>{busy === 'afk-report' ? 'Reporting…' : 'Report AFK'}</button>}</div></>)}
            </div>}
          </> : <p className={styles.muted}>Table open. Join the queue to become the first holder.</p>}
        </section>

        <section data-queue-card="waiting-list" className={`${styles.card} ${styles.waitingListCard}`}>
          <div className={styles.sectionHeading}><h2>Waiting List</h2></div>
          <div className={styles.waitingListBody}>
            {incomingSwap && <div className={styles.swapNotice}><strong>Incoming swap request</strong><p>{nameOf(incomingSwap.requester_id)} wants to exchange #{activePosition(incomingSwap.requester_id)} with your #{activePosition(incomingSwap.target_id)} spot.</p><small>Expires in {formatTimer(Math.max(0, Math.ceil((new Date(incomingSwap.expires_at).getTime() - now) / 1000)))}</small><div className={styles.swapActions}><button disabled={Boolean(busy)} onClick={() => void action('swap-accept', 'beaver_queue_respond_swap_v1', { p_request: incomingSwap.id, p_action: 'accept' })}>Accept</button><button disabled={Boolean(busy)} onClick={() => void action('swap-decline', 'beaver_queue_respond_swap_v1', { p_request: incomingSwap.id, p_action: 'decline' })}>Decline</button></div></div>}
            {outgoingSwap && <div className={styles.outgoingSwap}><strong>Swap requested from {nameOf(outgoingSwap.target_id)}</strong><span>{formatTimer(Math.max(0, Math.ceil((new Date(outgoingSwap.expires_at).getTime() - now) / 1000)))} remaining</span></div>}
            {waiting.length ? <ol className={styles.waitList}>{waiting.map((player) => {
              const canRequest = canRequestQueueSwap(me, player, Boolean(incomingSwap || outgoingSwap));
              return <li key={player.user_id}><span className={styles.queueIndex}>#{activePosition(player.user_id)}</span><BeaverAvatar config={avatarOf(player.user_id)} className={styles.queueListAvatar} label={`${player.display_name}'s avatar`} /><span className={styles.waitingName}><strong>{player.display_name}</strong>{player.user_id === currentUserId && <span className={styles.youTag}>You</span>}</span>{canRequest && <button className={styles.swapRequestButton} disabled={Boolean(busy)} onClick={() => void action(`swap-${player.user_id}`, 'beaver_queue_request_swap_v1', { p_target: player.user_id })}>Request Swap</button>}</li>;
            })}</ol> : <p className={styles.compactEmpty}>No players waiting.</p>}
          </div>
        </section>

        <section data-queue-card="recent-results" className={`${styles.card} ${styles.recentResultsCard}`}>
          <div className={styles.sectionHeading}><h2>Recent Results</h2><span className={styles.count}>Last 10 games</span></div>
          {games.length ? <div className={styles.resultList} tabIndex={0} aria-label="Last 10 queue results">{games.map((game) => <div key={game.id} className={styles.resultRow}><BeaverAvatar config={avatarOf(game.winner_id)} className={styles.queueListAvatar} label={`${snapshotName(game, game.winner_id)}'s avatar`} /><div><strong>{snapshotName(game, game.winner_id)} won</strong><div className={styles.mutedSmall}>vs. {snapshotName(game, game.loser_id)}</div></div></div>)}</div> : <p className={styles.compactEmpty}>No completed queue games yet.</p>}
        </section>
      </div>
    </main>
  );
}
