'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { validateMatchScore } from '@/lib/match-result';
import { orderedQueueLine, queuePlaceFor, QueueMemberStatus } from '@/lib/queue';
import { isActiveQueueStatus, isQueueBackendHealthy, isRetryableQueueError, queueErrorMessage } from '@/lib/queue-client';
import styles from './QueueClient.module.css';

interface QueueMember {
  user_id: string;
  display_name: string;
  status: QueueMemberStatus;
  queue_position: number;
  joined_at: string;
}

interface TableState {
  id: number;
  phase: 'idle' | 'called' | 'playing';
  king_id: string | null;
  challenger_id: string | null;
  call_expires_at: string | null;
  game_id: string | null;
  game_started_at: string | null;
}

interface QueueGame {
  id: string;
  king_id: string;
  challenger_id: string;
  king_name: string;
  challenger_name: string;
  king_score: number;
  challenger_score: number;
  winner_id: string;
  completed_at: string;
}

const formatTimer = (seconds: number) => `0:${String(seconds).padStart(2, '0')}`;

export default function QueueClient({ currentUserId }: { currentUserId: string }) {
  const supabase = useMemo(() => createClient(), []);
  const [table, setTable] = useState<TableState | null>(null);
  const [members, setMembers] = useState<QueueMember[]>([]);
  const [games, setGames] = useState<QueueGame[]>([]);
  const [now, setNow] = useState(Date.now());
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [loadError, setLoadError] = useState('');
  const [backendError, setBackendError] = useState('');
  const [actionError, setActionError] = useState('');
  const [heartbeatError, setHeartbeatError] = useState('');
  const [kingScore, setKingScore] = useState('11');
  const [challengerScore, setChallengerScore] = useState('9');
  const reading = useRef(false);
  const heartbeatFailures = useRef(0);
  const me = members.find((member) => member.user_id === currentUserId);

  useEffect(() => {
    let cancelled = false;
    void supabase.rpc('beaver_queue_health_v2').then(({ data, error: healthCheckError }) => {
      if (cancelled) return;
      if (healthCheckError) {
        setBackendError(queueErrorMessage(healthCheckError, 'Unable to verify the queue database version.'));
        return;
      }
      if (!isQueueBackendHealthy(data)) {
        setBackendError('The queue database is out of date. Apply migration 20261103_02, then reload this page.');
        return;
      }
      setBackendError('');
    });
    return () => { cancelled = true; };
  }, [supabase]);

  const refresh = useCallback(async () => {
    if (reading.current) return;
    reading.current = true;
    try {
      const [stateResponse, memberResponse, gameResponse] = await Promise.all([
        supabase.from('beaver_queue_table').select('*').eq('id', 1).single(),
        supabase.from('beaver_queue_members').select('*').order('queue_position'),
        supabase.from('beaver_queue_games').select('*').order('completed_at', { ascending: false }).limit(6),
      ]);
      if (stateResponse.error) throw stateResponse.error;
      if (memberResponse.error) throw memberResponse.error;
      if (gameResponse.error) throw gameResponse.error;
      setTable(stateResponse.data as TableState);
      setMembers((memberResponse.data ?? []) as QueueMember[]);
      setGames((gameResponse.data ?? []) as QueueGame[]);
      setLoadError('');
    } catch (caught) {
      setLoadError(queueErrorMessage(caught, 'Unable to load the queue.'));
    } finally {
      reading.current = false;
      setLoading(false);
    }
  }, [supabase]);

  useEffect(() => {
    void refresh();
    const poll = window.setInterval(() => void refresh(), 4000);
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    const focus = () => void refresh();
    window.addEventListener('focus', focus);
    const channel = supabase
      .channel('beaver-queue-live-v1')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_table' }, focus)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_members' }, focus)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_games' }, focus)
      .subscribe();
    return () => {
      window.clearInterval(poll);
      window.clearInterval(timer);
      window.removeEventListener('focus', focus);
      void supabase.removeChannel(channel);
    };
  }, [refresh, supabase]);

  useEffect(() => {
    if (!isActiveQueueStatus(me?.status)) {
      heartbeatFailures.current = 0;
      setHeartbeatError('');
      return;
    }

    let cancelled = false;
    const heartbeat = async () => {
      if (heartbeatFailures.current >= 3) return;
      const result = await supabase.rpc('beaver_queue_heartbeat_v1');
      if (cancelled) return;
      if (result.error) {
        heartbeatFailures.current = isRetryableQueueError(result.error)
          ? heartbeatFailures.current + 1
          : 3;
        const paused = heartbeatFailures.current >= 3 ? ' Automatic heartbeats are paused until this page is reloaded.' : '';
        setHeartbeatError(`${queueErrorMessage(result.error, 'Unable to keep your queue spot active.')}${paused}`);
        return;
      }
      heartbeatFailures.current = 0;
      setHeartbeatError('');
    };

    void heartbeat();
    const interval = window.setInterval(() => void heartbeat(), 30_000);
    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, [me?.status, supabase]);

  useEffect(() => {
    setKingScore('11');
    setChallengerScore('9');
  }, [table?.game_id]);

  const action = async (name: string, args: Record<string, unknown> = {}) => {
    if (busy) return;
    if (backendError) {
      setActionError(backendError);
      return;
    }
    setBusy(true);
    setActionError('');
    setMessage('');
    try {
      const result = await supabase.rpc(name, args);
      if (result.error) throw result.error;
      setMessage(
        name === 'beaver_queue_join_v1' ? 'You joined the queue.'
          : name === 'beaver_queue_leave_v1' ? 'You left the queue.'
            : name === 'beaver_queue_confirm_v1' ? "You're checked in. Have a great game!"
              : name === 'beaver_queue_report_v1' ? 'Score submitted. Winner stays!'
                : 'Queue updated.',
      );
      await refresh();
    } catch (caught) {
      setActionError(queueErrorMessage(caught, 'Something went wrong.'));
      await refresh();
    } finally {
      setBusy(false);
    }
  };

  const activeMembers = members.filter((member) =>
    ['waiting', 'called', 'king', 'playing'].includes(member.status));
  const waiting = members.filter((member) => member.status === 'waiting');
  const line = orderedQueueLine(members);
  const myPlace = queuePlaceFor(members, currentUserId);
  const nameOf = (id: string | null) =>
    members.find((member) => member.user_id === id)?.display_name ?? 'Player';
  const gameNameOf = (id: string, snapshot: string) =>
    members.find((member) => member.user_id === id)?.display_name ?? snapshot;
  const king = table?.king_id ?? null;
  const challenger = table?.challenger_id ?? null;
  const isCalled = me?.status === 'called' && challenger === currentUserId;
  const amPlaying = Boolean(table && table.phase === 'playing'
    && (king === currentUserId || challenger === currentUserId));
  const active = isActiveQueueStatus(me?.status);
  const secondsLeft = table?.call_expires_at
    ? Math.max(0, Math.ceil((new Date(table.call_expires_at).getTime() - now) / 1000))
    : 0;
  const holderScore = Number(kingScore);
  const nextScore = Number(challengerScore);
  const scoreError = kingScore.trim() && challengerScore.trim()
    ? validateMatchScore(holderScore, nextScore)
    : 'Both scores are required';
  const scoreValid = scoreError === null;
  const proposedWinner = scoreValid ? nameOf(holderScore > nextScore ? king : challenger) : null;

  const submitScore = () => {
    if (!table?.game_id || !scoreValid) return;
    if (!window.confirm(
      `Finalize ${nameOf(king)} ${holderScore} – ${nextScore} ${nameOf(challenger)}?\n\nThe first valid score submitted ends the game.`,
    )) return;
    void action('beaver_queue_report_v1', {
      p_game_id: table.game_id,
      p_king_score: holderScore,
      p_challenger_score: nextScore,
    });
  };

  return (
    <main className={styles.page}>
      {isCalled && (
        <section
          role="alertdialog"
          aria-modal="true"
          aria-labelledby="queue-turn-title"
          aria-describedby="queue-turn-description"
          className={styles.turnOverlay}
        >
          <div className={`${styles.turnCard} ${secondsLeft <= 15 ? styles.turnCardUrgent : ''}`}>
            <div className={styles.turnPulse} aria-hidden="true"><span /></div>
            <p className={styles.turnEyebrow}>Table ready</p>
            <h1 id="queue-turn-title">YOU’RE UP!</h1>
            <p className={styles.turnOpponent}>vs. <strong>{nameOf(king)}</strong></p>
            <div className={styles.turnTimer} aria-label={`${secondsLeft} seconds remaining`}>
              {formatTimer(secondsLeft)}
            </div>
            <p id="queue-turn-description" className={styles.turnDescription}>
              Check in now or your spot moves to the next player.
            </p>
            <button
              className={styles.turnButton}
              disabled={busy || secondsLeft === 0}
              onClick={() => void action('beaver_queue_confirm_v1')}
            >
              {busy ? 'Checking in…' : 'I’m Here'}
            </button>
          </div>
        </section>
      )}
      <div className={styles.shell}>
        <section className={styles.hero}>
          <h1>Live table <span>queue.</span></h1>
          <div className={styles.statRow}>
            <div><strong>{activeMembers.length}</strong><span>Active</span></div>
            <div><strong>{waiting.length}</strong><span>Waiting</span></div>
            <div><strong>60s</strong><span>Check-in</span></div>
          </div>
        </section>

        {(backendError || actionError || heartbeatError || loadError) && <div role="alert" className={styles.error}>{backendError || actionError || heartbeatError || loadError}</div>}
        {message && <div role="status" className={styles.success}>{message}</div>}
        <div className={styles.widgets} aria-label="Queue sections">
        {loading && !table ? <div className={styles.card}>Loading live queue…</div> : (
          <>
            <section className={`${styles.card} ${styles.currentMatchCard}`}>
              <div className={styles.sectionHeading}>
                <h2>Current match</h2>
                <span className={styles.pill}>{table?.phase === 'playing' ? 'GAME IN PROGRESS' : table?.phase === 'called' ? 'CHECK-IN' : 'READY'}</span>
              </div>
              {king ? (
                <div className={styles.tableMatch}>
                  <div className={styles.playerCard}>
                    <div className={styles.seatLabel}>TABLE HOLDER</div>
                    <div className={styles.avatar}>{nameOf(king).slice(0, 1).toUpperCase()}</div>
                    <strong>{nameOf(king)}{king === currentUserId ? ' (You)' : ''}</strong>
                  </div>
                  <div className={styles.vs}>VS</div>
                  <div className={styles.playerCard}>
                    <div className={styles.seatLabel}>{challenger ? 'CHALLENGER' : 'OPEN SEAT'}</div>
                    <div className={styles.avatarAlt}>{challenger ? nameOf(challenger).slice(0, 1).toUpperCase() : '?'}</div>
                    <strong>{challenger ? `${nameOf(challenger)}${challenger === currentUserId ? ' (You)' : ''}` : 'Waiting…'}</strong>
                  </div>
                </div>
              ) : <p className={styles.muted}>Table open.</p>}

              {table?.phase === 'called' && (
                <div className={styles.callBanner}>
                  <span>{isCalled ? "You're up! Check in now." : `Waiting for ${nameOf(challenger)} to arrive`}</span>
                  <strong className={secondsLeft <= 15 ? styles.urgent : ''}>{formatTimer(secondsLeft)}</strong>
                </div>
              )}
              {isCalled && (
                <button className={styles.primaryButton} disabled={busy || secondsLeft === 0}
                  onClick={() => void action('beaver_queue_confirm_v1')}>
                  I’m Here · Start Game
                </button>
              )}
            </section>

            {amPlaying && (
              <section className={styles.card}>
                <div className={styles.sectionHeading}><h2>Report the result</h2><span className={styles.pill}>FIRST SUBMISSION WINS</span></div>
                <div className={styles.scoreFields}>
                  <label className={styles.scoreField}>
                    <span>{nameOf(king)}</span>
                    <input aria-label={`${nameOf(king)} score`} type="number" inputMode="numeric" min="0" max="99"
                      value={kingScore} onChange={(event) => setKingScore(event.target.value)} />
                  </label>
                  <span className={styles.scoreDash}>–</span>
                  <label className={styles.scoreField}>
                    <span>{nameOf(challenger)}</span>
                    <input aria-label={`${nameOf(challenger)} score`} type="number" inputMode="numeric" min="0" max="99"
                      value={challengerScore} onChange={(event) => setChallengerScore(event.target.value)} />
                  </label>
                </div>
                <p className={scoreValid ? styles.outcome : styles.invalidOutcome}>
                  {scoreValid ? `${proposedWinner} stays on the table` : scoreError}
                </p>
                <button className={styles.primaryButton} disabled={!scoreValid || busy} onClick={submitScore}>
                  {busy ? 'Submitting…' : 'Submit Final Score'}
                </button>
              </section>
            )}

            <section className={styles.card}>
              <div className={styles.sectionHeading}><h2>Your queue status</h2><span className={styles.pill}>{active ? (me?.status ?? '') : 'NOT IN QUEUE'}</span></div>
              {!active && (
                <>
                  {(me?.status === 'no_show' || me?.status === 'left') && <p className={styles.muted}>{me?.status === 'no_show' ? 'Check-in expired.' : 'You left the queue.'}</p>}
                  <button className={styles.primaryButton} disabled={busy} onClick={() => void action('beaver_queue_join_v1')}>Join the Queue</button>
                </>
              )}
              {me?.status === 'waiting' && myPlace && (
                <div className={styles.positionCard}>
                  <span>Your position</span>
                  <strong>#{myPlace.position}</strong>
                  <small>{myPlace.playersAhead} {myPlace.playersAhead === 1 ? 'player' : 'players'} ahead</small>
                </div>
              )}
              {me?.status === 'king' && <p className={styles.muted}>You hold the table.</p>}
              {me?.status === 'called' && <p className={styles.muted}>Check in within one minute.</p>}
              {me?.status === 'playing' && <p className={styles.muted}>Game in progress.</p>}
              {active && !amPlaying && (
                <button className={`${styles.secondaryButton} ${styles.leaveButton}`} disabled={busy} onClick={() => void action('beaver_queue_leave_v1')}>Leave Queue</button>
              )}
            </section>

            <section className={styles.card}>
              <div className={styles.sectionHeading}><h2>Live queue</h2><span className={styles.count}>{line.length} in line</span></div>
              {line.length ? (
                <ol className={styles.waitList}>
                  {line.map((player, index) => (
                    <li key={player.user_id} className={player.status === 'called' ? styles.nextPlayer : ''}>
                      <span className={styles.queueIndex}>{index + 1}</span>
                      <span><strong>{player.display_name}{player.user_id === currentUserId ? ' (You)' : ''}</strong>{player.status === 'called' && <small>UP NEXT · CHECKING IN</small>}</span>
                    </li>
                  ))}
                </ol>
              ) : <p className={styles.muted}>Queue empty.</p>}
            </section>

            <section className={styles.card}>
              <div className={styles.sectionHeading}><h2>Recent results</h2><span className={styles.count}>Queue only</span></div>
              {games.length ? (
                <div className={styles.resultList} tabIndex={0} aria-label="Recent queue results">
                  {games.map((game) => (
                    <div key={game.id} className={styles.resultRow}>
                      <div>
                        <strong>{game.winner_id === game.king_id
                          ? gameNameOf(game.king_id, game.king_name)
                          : gameNameOf(game.challenger_id, game.challenger_name)} won</strong>
                        <div className={styles.mutedSmall}>
                          {gameNameOf(game.king_id, game.king_name)} vs. {gameNameOf(game.challenger_id, game.challenger_name)}
                        </div>
                      </div>
                      <strong className={styles.finalScore}>{game.king_score}–{game.challenger_score}</strong>
                    </div>
                  ))}
                  </div>
              ) : <p className={styles.muted}>No games yet.</p>}
            </section>
          </>
        )}
        </div>
      </div>
    </main>
  );
}
