# Live Queue setup and verification

The experimental `/queue` feature is intentionally separate from ranked BeaverSmash
matches. Its tables, RPCs, recent results, and Realtime channels all use the
`beaver_queue_*` prefix.

## Apply the migration

1. Back up the project as usual and test against a disposable Supabase project first.
2. Apply all existing migrations in filename order.
3. Apply `supabase/migrations/20261101_01_live_queue.sql`,
   `supabase/migrations/20261103_01_coordinated_auth_rank_queue.sql`, and then
   `supabase/migrations/20261103_02_queue_production_repair.sql` and
   `supabase/migrations/20261103_03_queue_outcomes_swaps.sql` and
   `supabase/migrations/20261103_04_queue_forward_swaps.sql` and
   `supabase/migrations/20261103_05_queue_afk_timeouts.sql` through the Supabase CLI
   or SQL editor. **A GitHub/Vercel deployment does not apply database migrations.**
   Test the repair against a disposable database before production.
4. Verify `beaver_queue_table`, `beaver_queue_members`, `beaver_queue_games`, and
   `beaver_queue_swap_requests` are in
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
```

The test runs in a transaction and rolls back its users and queue state. Follow
`supabase/tests/live_queue_concurrency.md` for two-session race checks.

## Verify production deployment

Run this in the Supabase SQL editor after applying the repair:

```sql
SELECT
  to_regprocedure('public.beaver_queue_health_v5()') IS NOT NULL AS repair_installed,
  has_function_privilege('authenticated','public.beaver_queue_heartbeat_v1()','EXECUTE') AS heartbeat_granted,
  has_function_privilege('authenticated','public.beaver_queue_join_v1()','EXECUTE') AS join_granted,
  has_function_privilege('authenticated','public.beaver_queue_report_outcome_v2(uuid,text)','EXECUTE') AS outcome_granted,
  has_function_privilege('authenticated','public.beaver_queue_request_swap_v1(uuid)','EXECUTE') AS swap_granted,
  has_function_privilege('authenticated','public.beaver_queue_report_afk_v1()','EXECUTE') AS afk_report_granted,
  has_function_privilege('authenticated','public.beaver_queue_confirm_presence_v1()','EXECUTE') AS presence_granted,
  EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname='supabase_realtime' AND schemaname='public'
      AND tablename='beaver_queue_members'
  ) AS members_realtime;
```

All values must be `true`. From an authenticated app session,
`beaver_queue_health_v5()` must return version `20261103_05`. A `PGRST202` response means
the migration was not applied or PostgREST has not reloaded its schema. A `42501`
response for an authenticated user means the RPC grant is wrong; the same response for
the anonymous role is expected.

## Run the deadline worker

Configure a trusted server-side scheduler to call:

```sql
SELECT public.beaver_queue_advance_expired_v1();
```

every 5–15 seconds with the Supabase `service_role`. The reference query is also stored
in `supabase/functions/queue-tick.sql`. Keep the service-role key exclusively on the
server. The function uses database time and locks the singleton queue row, so it is safe
for overlapping worker calls and for races with a player's **I'm Here** action.

The page refetches the authoritative snapshot every four seconds and after Realtime
changes. Only active queue members send a heartbeat, at a 30-second interval; Realtime
events never trigger another heartbeat. The trusted worker is still what guarantees
advancement when every browser is closed.

The same worker enforces the solo-player and in-game AFK 60-second deadlines, the
10-minute game deadline, stores unfinished games as `abandoned` audit rows, expires
60-second swap requests, and calls the next eligible players. AFK removals never create
a win or loss. Abandoned games are visible only in the admin Integrity
audit; they never appear in player Queue Activity.

## Test with 3–5 phones or browser sessions

1. Create three to five normal BeaverSmash accounts. Use separate devices, browser
   profiles, or regular/incognito windows so each session has a different login.
2. Open `/queue` in each session.
3. Join as A. A should become the table holder.
4. Join as B, C, D, and optionally E. B should be called for 60 seconds; later players
   should remain in FIFO order and see the same state on every screen.
5. Confirm as B. Only A and B should see **I Won** and **I Lost** controls.
6. Submit an outcome from A or B. Confirm that the winner stays, the loser can rejoin
   at the back, and C is called next.
7. Let one call expire without its browser open. The worker should mark that player as a
   no-show and call the next player shortly after the displayed deadline.
8. Try joining twice, leaving while waiting, leaving while called, refreshing during a
   game, and submitting from a nonparticipant. The queue should remain consistent and
   unauthorized reporting should fail.
9. Confirm that no row was added to `matches` or `rating_events`, and no ranked ELO,
   win/loss record, limit, leaderboard, or dispute changed.
10. While two or more players are waiting, request a swap from a player ahead to one
    behind. Accept it from the target session and verify both positions exchange for all
    clients. Decline and 60-second expiry must leave positions unchanged.
11. Join alone and verify the holder is removed after the subtle 60-second countdown.
12. During a game, report the opponent AFK. Verify **I'm Here** cancels the check; then
    let a second check expire and verify the reporter stays while the next player is called.

## Outcome corrections

The first valid participant outcome atomically finalizes a queue game. Identical retries
are idempotent; conflicting late reports are rejected. An administrator can change the
recorded winner from **Integrity → Queue history audit** only with a reason. Every change
creates an immutable correction row and updates history only—it never rewinds the current
holder, later queue games, ranked matches, ratings, challenges, or limits. Abandoned games
cannot be converted to completed games.
