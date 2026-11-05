# Live Queue setup and verification

The `/queue` feature records games as unranked by default. Its queue tables, RPCs,
recent results, and Realtime channels use the `beaver_queue_*` prefix. If both active
players agree to Ranked, the Current Match card switches to the normal ranked score
rules. A valid score removes both players and advances the line; an unanswered score
deadline voids the ranked match and removes both players.

## Apply the migration

1. Back up the project as usual and test against a disposable Supabase project first.
2. Apply all existing migrations in filename order.
3. Apply `supabase/migrations/20261101_01_live_queue.sql`,
   `supabase/migrations/20261103_01_coordinated_auth_rank_queue.sql`, and then
   `supabase/migrations/20261103_02_queue_production_repair.sql` and
   `supabase/migrations/20261103_03_queue_outcomes_swaps.sql` and
   `supabase/migrations/20261103_04_queue_forward_swaps.sql` and
   `supabase/migrations/20261103_05_queue_afk_timeouts.sql` and
   `supabase/migrations/20261104_02_queue_match_expiry_checkins.sql` and
   `supabase/migrations/20261104_03_queue_holder_presence.sql` and
   `supabase/migrations/20261104_04_queue_ranked_matches.sql`,
   `supabase/migrations/20261104_05_queue_ranked_inline_scoring.sql`, and
   `supabase/migrations/20261104_08_restore_three_ranked_games_per_opponent.sql` through the Supabase CLI
   or SQL editor. **A GitHub/Vercel deployment does not apply database migrations.**
   Test the repair against a disposable database before production.
4. Verify `beaver_queue_table`, `beaver_queue_members`, `beaver_queue_games`,
   `beaver_queue_swap_requests`, and `beaver_queue_ranked_requests` are in
   the `supabase_realtime` publication.
5. Deploy the application code together with the migration. An application deployed
   before its database migration will show a missing-RPC error at `/queue`.

For a disposable database with `psql` available, run:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/live_queue.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/queue_production_repair.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/queue_outcomes_swaps.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/queue_afk_timeouts.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/queue_match_expiry_checkins.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/queue_ranked_matches.test.sql
```

The test runs in a transaction and rolls back its users and queue state. Follow
`supabase/tests/live_queue_concurrency.md` for two-session race checks.

## Verify production deployment

Run this in the Supabase SQL editor after applying the repair:

```sql
SELECT
  to_regprocedure('public.beaver_queue_health_v9()') IS NOT NULL AS repair_installed,
  has_function_privilege('authenticated','public.beaver_queue_heartbeat_v1()','EXECUTE') AS heartbeat_granted,
  has_function_privilege('authenticated','public.beaver_queue_join_v1()','EXECUTE') AS join_granted,
  has_function_privilege('authenticated','public.beaver_queue_tick_v1()','EXECUTE') AS tick_granted,
  has_function_privilege('authenticated','public.beaver_queue_report_outcome_v2(uuid,text)','EXECUTE') AS outcome_granted,
  has_function_privilege('authenticated','public.beaver_queue_request_swap_v1(uuid)','EXECUTE') AS swap_granted,
  has_function_privilege('authenticated','public.beaver_queue_report_afk_v1()','EXECUTE') AS afk_report_granted,
  has_function_privilege('authenticated','public.beaver_queue_confirm_presence_v1()','EXECUTE') AS presence_granted,
  has_function_privilege('authenticated','public.beaver_queue_request_ranked_v1()','EXECUTE') AS ranked_request_granted,
  has_function_privilege('authenticated','public.beaver_queue_respond_ranked_v1(uuid,text)','EXECUTE') AS ranked_response_granted,
  has_function_privilege('authenticated','public.beaver_queue_submit_ranked_result_v1(uuid,uuid,integer,integer)','EXECUTE') AS ranked_score_granted,
  EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname='supabase_realtime' AND schemaname='public'
      AND tablename='beaver_queue_members'
  ) AS members_realtime;
```

All values must be `true`. From an authenticated app session,
`beaver_queue_health_v9()` must return version `20261104_05`. A `PGRST202` response means
the migration was not applied or PostgREST has not reloaded its schema. A `42501`
response for an authenticated user means the RPC grant is wrong; the same response for
the anonymous role is expected.

## Run the deadline worker

Configure a trusted server-side scheduler to call:

```sql
SELECT public.beaver_queue_advance_expired_v1();
```

every 5 seconds with the Supabase `service_role`. The reference query is also stored
in `supabase/functions/queue-tick.sql`. Keep the service-role key exclusively on the
server. The function uses database time and locks the singleton queue row, so it is safe
for overlapping worker calls and for races with a player's **I'm Here** action.

The page refetches the authoritative snapshot every four seconds and after Realtime
changes. Only active queue members send a heartbeat, at a 30-second interval; Realtime
events never trigger another heartbeat. The trusted worker is still what guarantees
advancement when every browser is closed. Connected clients additionally call the
authenticated tick RPC as soon as their displayed authoritative deadline reaches zero;
that client request is an immediate synchronization path, not a replacement for the worker.

The same worker enforces the solo-player and in-game AFK 60-second deadlines, the
10-minute game deadline, voids any accepted Ranked match without a submitted score,
stores unfinished games as `abandoned` audit rows, expires
60-second swap requests, and calls the next eligible players. AFK removals never create
a win or loss. Abandoned games are visible only in the admin Integrity
audit; they never appear in player Queue Activity.

## Test with 3–5 phones or browser sessions

1. Create three to five normal Pongo accounts. Use separate devices, browser
   profiles, or regular/incognito windows so each session has a different login.
2. Open `/queue` in each session.
3. Join as A. A should become the table holder.
4. Join as B, C, D, and optionally E. B should be called for 60 seconds; later players
   should remain in FIFO order and see the same state on every screen.
5. B, as the incoming challenger, should receive the **You're Up!** pop-up. A is already
   present as the table holder and should not have to check in again. The original
   60-second deadline must not reset; after B confirms, A and B should see **I Won** and
   **I Lost** controls. A should receive a presence pop-up only if B reports A as AFK.
6. Submit an outcome from A or B. Confirm that the winner stays, the loser can rejoin
   at the back, and C is called next.
7. Let one call expire without its browser open. The worker should mark that player as a
   no-show and call the next player shortly after the displayed deadline.
8. Try joining twice, leaving while waiting, leaving while called, refreshing during a
   game, and submitting from a nonparticipant. The queue should remain consistent and
   unauthorized reporting should fail.
9. For an Unranked game, confirm that no row was added to `matches` or
   `rating_events`, and no ranked ELO, win/loss record, limit, leaderboard, or
   dispute changed.
10. While two or more players are waiting, request a swap from a player ahead to one
    behind. Accept it from the target session and verify both positions exchange for all
    clients. Decline and 60-second expiry must leave positions unchanged.
11. Join alone and verify the holder is removed after the subtle 60-second countdown.
12. During a game, report the opponent AFK. Verify **I'm Here** cancels the check; then
    let a second check expire and verify the reporter stays while the next player is called.
13. Let a game timer reach `0:00`. Both players should be removed, an abandoned queue
    audit row should contain no winner or loser, and the next waiting player should advance.
14. After the same pair has completed three Ranked games that New York calendar day,
    start another game and request **Ranked Game**. The request must show the inline
    three-game-limit message while leaving **I Won** and **I Lost** available for an
    Unranked result.
15. Start another game and request **Ranked Game**. Declining must leave **I Won** and
    **I Lost** available. Accepting must hide them and show the score controls inside
    **Current Match**, without navigating away from `/queue`.
16. Submit a valid Ranked score. Confirm that the normal ranked match is finalized,
    both players leave the queue, ELO/rank data updates once, no completed unranked
    queue result is stored, and the next waiting player advances.
17. Accept Ranked in another game but submit no score. At the original `0:00` deadline,
    both players must be removed, the ranked match must be `voided` with no rating
    events, and the next waiting player must advance.

## Outcome corrections

The first valid participant outcome atomically finalizes a queue game. Identical retries
are idempotent; conflicting late reports are rejected. An administrator can change the
recorded winner from **Integrity → Queue history audit** only with a reason. Every change
creates an immutable correction row and updates history only—it never rewinds the current
holder, later queue games, ranked matches, ratings, challenges, or limits. Abandoned games
cannot be converted to completed games.
