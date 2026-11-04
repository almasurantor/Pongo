'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import {
  canReportQueueOutcome,
  canRequestQueueSwap,
  queueGameSecondsRemaining,
  queueSecondsUntil,
  queueStatusLabel,
  type QueueMemberStatus,
} from '@/lib/queue';
import { isActiveQueueStatus, isQueueBackendHealthy, isRetryableQueueError, queueErrorMessage } from '@/lib/queue-client';
import styles from './QueueClient.module.css';

interface QueueMember { user_id: string; display_name: string; status: QueueMemberStatus; queue_position: number; joined_at: string; }
interface TableState { id: number; phase: 'idle' | 'called' | 'playing'; king_id: string | null; challenger_id: string | null; call_expires_at: string | null; game_id: string | null; game_started_at: string | null; solo_expires_at: string | null; afk_reporter_id: string | null; afk_target_id: string | null; afk_expires_at: string | null; }
interface QueueGame { id: string; king_id: string; challenger_id: string; king_name: string; challenger_name: string; winner_id: string; loser_id: string; completed_at: string; }
interface SwapRequest { id: string; requester_id: string; target_id: string; requester_position: number; target_position: number; status: 'pending' | 'accepted' | 'declined' | 'expired' | 'canceled'; expires_at: string; }

const formatTimer = (seconds: number) => `${Math.floor(Math.max(0, seconds) / 60)}:${String(Math.max(0, seconds) % 60).padStart(2, '0')}`;

export default function QueueClient({ currentUserId }: { currentUserId: string }) {
  const supabase = useMemo(() => createClient(), []);
  const [table, setTable] = useState<TableState | null>(null);
  const [members, setMembers] = useState<QueueMember[]>([]);
  const [games, setGames] = useState<QueueGame[]>([]);
  const [swaps, setSwaps] = useState<SwapRequest[]>([]);
  const [now, setNow] = useState(Date.now());
  const [busy, setBusy] = useState('');
  const [loading, setLoading] = useState(true);
  const [outcomeChoice, setOutcomeChoice] = useState<'won' | 'lost' | null>(null);
  const [loadError, setLoadError] = useState('');
  const [backendError, setBackendError] = useState('');
  const [actionError, setActionError] = useState('');
  const [heartbeatError, setHeartbeatError] = useState('');
  const reading = useRef(false);
  const heartbeatFailures = useRef(0);
  const me = members.find((member) => member.user_id === currentUserId);

  useEffect(() => {
    let cancelled = false;
    void supabase.rpc('beaver_queue_health_v5').then(({ data, error }) => {
      if (cancelled) return;
      if (error) setBackendError(queueErrorMessage(error, 'Unable to verify the queue database version.'));
      else if (!isQueueBackendHealthy(data)) setBackendError('The queue database is out of date. Apply migration 20261103_05, then reload this page.');
      else setBackendError('');
    });
    return () => { cancelled = true; };
  }, [supabase]);

  const refresh = useCallback(async () => {
    if (reading.current) return;
    reading.current = true;
    try {
      const [stateResponse, memberResponse, gameResponse, swapResponse] = await Promise.all([
        supabase.from('beaver_queue_table').select('*').eq('id', 1).single(),
        supabase.from('beaver_queue_members').select('*').order('queue_position'),
        supabase.from('beaver_queue_games').select('*').eq('status', 'completed').order('completed_at', { ascending: false }).limit(10),
        supabase.from('beaver_queue_swap_requests').select('*').eq('status', 'pending').order('created_at'),
      ]);
      if (stateResponse.error) throw stateResponse.error;
      if (memberResponse.error) throw memberResponse.error;
      if (gameResponse.error) throw gameResponse.error;
      if (swapResponse.error) throw swapResponse.error;
      setTable(stateResponse.data as TableState);
      setMembers((memberResponse.data ?? []) as QueueMember[]);
      setGames((gameResponse.data ?? []) as QueueGame[]);
      setSwaps((swapResponse.data ?? []) as SwapRequest[]);
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
    const channel = supabase.channel('beaver-queue-live-v3')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_table' }, focus)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_members' }, focus)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_games' }, focus)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_swap_requests' }, focus)
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

  useEffect(() => { setOutcomeChoice(null); }, [table?.game_id, table?.phase]);

  const waiting = members.filter((member) => member.status === 'waiting').sort((a, b) => a.queue_position - b.queue_position || a.user_id.localeCompare(b.user_id));
  const activeMembers = members.filter((member) => isActiveQueueStatus(member.status));
  const myWaitingIndex = waiting.findIndex((member) => member.user_id === currentUserId);
  const active = isActiveQueueStatus(me?.status);
  const king = table?.king_id ?? null;
  const challenger = table?.challenger_id ?? null;
  const isCalled = me?.status === 'called' && challenger === currentUserId;
  const amPlaying = canReportQueueOutcome(table?.phase, currentUserId, king, challenger);
  const callSeconds = queueSecondsUntil(table?.call_expires_at ?? null, now);
  const gameSeconds = queueGameSecondsRemaining(table?.game_started_at ?? null, now);
  const soloSeconds = queueSecondsUntil(table?.solo_expires_at ?? null, now);
  const afkSeconds = queueSecondsUntil(table?.afk_expires_at ?? null, now);
  const afkPending = Boolean(table?.afk_target_id && table?.afk_expires_at);
  const isAfkTarget = table?.afk_target_id === currentUserId;
  const isAfkReporter = table?.afk_reporter_id === currentUserId;
  const incomingSwap = swaps.find((swap) => swap.target_id === currentUserId);
  const outgoingSwap = swaps.find((swap) => swap.requester_id === currentUserId);
  const nameOf = (id: string | null) => members.find((member) => member.user_id === id)?.display_name ?? 'Player';
  const snapshotName = (game: QueueGame, id: string) => id === game.king_id ? game.king_name : game.challenger_name;

  const confirmOutcome = async () => {
    if (!table?.game_id || !outcomeChoice) return;
    const outcome = outcomeChoice;
    await action(`outcome-${outcome}`, 'beaver_queue_report_outcome_v2', { p_game_id: table.game_id, p_outcome: outcome });
    setOutcomeChoice(null);
  };

  const statusLabel = queueStatusLabel(me?.status, myWaitingIndex, callSeconds);

  return (
    <main className={styles.page}>
      <div className={styles.shell}>
        <section data-queue-card="live-table" className={`${styles.hero} ${styles.queueHeaderCard}`}>
          <div className={styles.heroMain}>
            <div><h1>Live table <span>queue.</span></h1><p className={styles.heroTagline}>Winner stays. Next plays.</p></div>
            <div className={styles.statRow}><div><strong>{activeMembers.length}</strong><span>Active</span></div><div><strong>{waiting.length}</strong><span>Waiting</span></div><div><strong>{table?.phase === 'called' ? formatTimer(callSeconds) : '60s'}</strong><span>Check-in</span></div></div>
          </div>
          <div className={styles.queueControls}>
            <span className={styles.statusLabel}>{statusLabel}</span>
            {!active && <button className={styles.primaryButton} disabled={Boolean(busy)} onClick={() => void action('join', 'beaver_queue_join_v1')}>{busy === 'join' ? 'Joining…' : 'Join Queue'}</button>}
            {active && !amPlaying && <button className={`${styles.secondaryButton} ${styles.leaveButton}`} disabled={Boolean(busy)} onClick={() => void action('leave', 'beaver_queue_leave_v1')}>{busy === 'leave' ? 'Leaving…' : 'Leave Queue'}</button>}
          </div>
        </section>

        {(backendError || actionError || heartbeatError || loadError) && <div role="alert" className={styles.error}>{backendError || actionError || heartbeatError || loadError}</div>}

        <section data-queue-card="waiting-list" className={`${styles.card} ${styles.waitingListCard}`}>
          <div className={styles.sectionHeading}><h2>Waiting List</h2><span className={styles.count}>{waiting.length} waiting · Live</span></div>
          <div className={styles.waitingListBody}>
            {incomingSwap && <div className={styles.swapNotice}><strong>Incoming swap request</strong><p>{nameOf(incomingSwap.requester_id)} wants to exchange #{incomingSwap.requester_position} with your #{incomingSwap.target_position} spot.</p><small>Expires in {formatTimer(Math.max(0, Math.ceil((new Date(incomingSwap.expires_at).getTime() - now) / 1000)))}</small><div className={styles.swapActions}><button disabled={Boolean(busy)} onClick={() => void action('swap-accept', 'beaver_queue_respond_swap_v1', { p_request: incomingSwap.id, p_action: 'accept' })}>Accept</button><button disabled={Boolean(busy)} onClick={() => void action('swap-decline', 'beaver_queue_respond_swap_v1', { p_request: incomingSwap.id, p_action: 'decline' })}>Decline</button></div></div>}
            {outgoingSwap && <div className={styles.outgoingSwap}><strong>Swap requested from {nameOf(outgoingSwap.target_id)}</strong><span>{formatTimer(Math.max(0, Math.ceil((new Date(outgoingSwap.expires_at).getTime() - now) / 1000)))} remaining</span></div>}
            {waiting.length ? <ol className={styles.waitList}>{waiting.map((player, index) => {
              const canRequest = canRequestQueueSwap(me, player, Boolean(incomingSwap || outgoingSwap));
              return <li key={player.user_id}><span className={styles.queueIndex}>{index + 1}</span><span className={styles.waitingName}><strong>{player.display_name}{player.user_id === currentUserId ? ' (You)' : ''}</strong><small>{player.user_id === currentUserId ? 'Your position' : player.queue_position < (me?.queue_position ?? 0) && me?.status === 'waiting' ? 'Ahead of you' : 'Waiting'}</small></span>{canRequest && <button className={styles.swapRequestButton} disabled={Boolean(busy)} onClick={() => void action(`swap-${player.user_id}`, 'beaver_queue_request_swap_v1', { p_target: player.user_id })}>Request Swap</button>}</li>;
            })}</ol> : <p className={styles.compactEmpty}>No players waiting.</p>}
          </div>
        </section>

        <section data-queue-card="current-match" className={`${styles.card} ${styles.currentMatchCard}`}>
          <div className={styles.sectionHeading}><h2>Current Match</h2><span className={styles.pill}>{table?.phase === 'playing' ? 'GAME IN PROGRESS' : table?.phase === 'called' ? 'CHECK-IN' : 'READY'}</span></div>
          {loading && !table ? <p className={styles.muted}>Loading current table…</p> : king ? <>
            <div className={styles.tableMatch}>
              <div className={styles.playerCard}><div className={styles.seatLabel}>HOLDER</div><div className={styles.avatar}>{nameOf(king).slice(0, 1).toUpperCase()}</div><strong>{nameOf(king)}{king === currentUserId ? ' (You)' : ''}</strong></div>
              <div className={styles.vs}>VS</div>
              <div className={styles.playerCard}><div className={styles.seatLabel}>{challenger ? 'CHALLENGER' : 'OPEN SEAT'}</div><div className={styles.avatarAlt}>{challenger ? nameOf(challenger).slice(0, 1).toUpperCase() : '?'}</div><strong>{challenger ? `${nameOf(challenger)}${challenger === currentUserId ? ' (You)' : ''}` : 'Waiting…'}</strong></div>
            </div>
            {table?.phase === 'idle' && !challenger && table.solo_expires_at && <div className={styles.soloTimer}><span>Waiting for an opponent</span><strong>{formatTimer(soloSeconds)}</strong></div>}
            {table?.phase === 'called' && <div className={styles.callBanner}><span>{isCalled ? "You're up — check in now" : `Waiting for ${nameOf(challenger)}`}</span><strong className={callSeconds <= 15 ? styles.urgent : ''}>{formatTimer(callSeconds)}</strong></div>}
            {isCalled && <button className={styles.primaryButton} disabled={Boolean(busy) || callSeconds === 0} onClick={() => void action('confirm', 'beaver_queue_confirm_v1')}>{busy === 'confirm' ? 'Checking in…' : 'I’m Here'}</button>}
            {table?.phase === 'playing' && <div className={styles.gamePanel}>
              <div className={styles.gameTimer}><span>Game time remaining</span><strong className={gameSeconds <= 60 ? styles.urgent : ''}>{formatTimer(gameSeconds)}</strong></div>
              {isAfkTarget && <div className={styles.afkPrompt}><div><strong>Are you here?</strong><span>Your opponent reported you as AFK.</span></div><strong className={afkSeconds <= 15 ? styles.urgent : ''}>{formatTimer(afkSeconds)}</strong><button disabled={Boolean(busy) || afkSeconds === 0} onClick={() => void action('afk-present', 'beaver_queue_confirm_presence_v1')}>{busy === 'afk-present' ? 'Responding…' : 'I’m Here'}</button></div>}
              {isAfkReporter && <div className={styles.afkStatus}><span>Waiting for {nameOf(table?.afk_target_id ?? null)} to respond</span><strong>{formatTimer(afkSeconds)}</strong></div>}
              {amPlaying && !isAfkTarget && (outcomeChoice ? <div className={styles.outcomeConfirm}><p>Confirm you {outcomeChoice}?</p><div><button className={outcomeChoice === 'won' ? styles.winButton : styles.lossButton} disabled={Boolean(busy)} onClick={() => void confirmOutcome()}>{busy ? 'Submitting…' : outcomeChoice === 'won' ? 'Confirm Win' : 'Confirm Loss'}</button><button className={styles.cancelButton} disabled={Boolean(busy)} onClick={() => setOutcomeChoice(null)}>Cancel</button></div></div> : <><div className={styles.outcomeActions}><button className={styles.winButton} disabled={Boolean(busy)} onClick={() => setOutcomeChoice('won')}>I Won</button><button className={styles.lossButton} disabled={Boolean(busy)} onClick={() => setOutcomeChoice('lost')}>I Lost</button></div>{!afkPending && <button className={styles.afkReportButton} disabled={Boolean(busy)} onClick={() => void action('afk-report', 'beaver_queue_report_afk_v1')}>{busy === 'afk-report' ? 'Reporting…' : 'Report AFK'}</button>}</>)}
            </div>}
          </> : <p className={styles.muted}>Table open. Join the queue to become the first holder.</p>}
        </section>

        <section data-queue-card="recent-results" className={`${styles.card} ${styles.recentResultsCard}`}>
          <div className={styles.sectionHeading}><h2>Recent Results</h2><span className={styles.count}>Last 10 games</span></div>
          {games.length ? <div className={styles.resultList} tabIndex={0} aria-label="Last 10 queue results">{games.map((game) => <div key={game.id} className={styles.resultRow}><div><strong>{snapshotName(game, game.winner_id)} won</strong><div className={styles.mutedSmall}>vs. {snapshotName(game, game.loser_id)}</div></div></div>)}</div> : <p className={styles.compactEmpty}>No completed queue games yet.</p>}
        </section>
      </div>
    </main>
  );
}
