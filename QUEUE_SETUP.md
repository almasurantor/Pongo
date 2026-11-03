# Live Queue setup and verification

The experimental `/queue` feature is intentionally separate from ranked BeaverSmash
matches. Its tables, RPCs, recent results, and Realtime channels all use the
`beaver_queue_*` prefix.

## Apply the migration

1. Back up the project as usual and test against a disposable Supabase project first.
2. Apply all existing migrations in filename order.
3. Apply `supabase/migrations/20261101_01_live_queue.sql`, then
   `supabase/migrations/20261103_01_coordinated_auth_rank_queue.sql`, through the Supabase
   CLI or SQL editor. Do not paste them into a production project before testing them.
4. Verify `beaver_queue_table`, `beaver_queue_members`, and `beaver_queue_games` are in
   the `supabase_realtime` publication.
5. Deploy the application code together with the migration. An application deployed
   before its database migration will show a missing-RPC error at `/queue`.

For a disposable database with `psql` available, run:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/live_queue.test.sql
```

The test runs in a transaction and rolls back its users and queue state. Follow
`supabase/tests/live_queue_concurrency.md` for two-session race checks.

## Run the deadline worker

Configure a trusted server-side scheduler to call:

```sql
SELECT public.beaver_queue_advance_expired_v1();
```

every 5–15 seconds with the Supabase `service_role`. The reference query is also stored
in `supabase/functions/queue-tick.sql`. Keep the service-role key exclusively on the
server. The function uses database time and locks the singleton queue row, so it is safe
for overlapping worker calls and for races with a player's **I'm Here** action.

The page also calls the authenticated heartbeat RPC every four seconds, after Realtime
changes, and when the window regains focus. That makes active screens responsive, but the
trusted worker is what guarantees advancement when every browser is closed.

## Test with 3–5 phones or browser sessions

1. Create three to five normal BeaverSmash accounts. Use separate devices, browser
   profiles, or regular/incognito windows so each session has a different login.
2. Open `/queue` in each session.
3. Join as A. A should become the table holder.
4. Join as B, C, D, and optionally E. B should be called for 60 seconds; later players
   should remain in FIFO order and see the same state on every screen.
5. Confirm as B. Only A and B should see score controls.
6. Submit a valid score from A or B. Confirm that the winner stays, the loser can rejoin
   at the back, and C is called next.
7. Let one call expire without its browser open. The worker should mark that player as a
   no-show and call the next player shortly after the displayed deadline.
8. Try joining twice, leaving while waiting, leaving while called, refreshing during a
   game, and submitting from a nonparticipant. The queue should remain consistent and
   unauthorized reporting should fail.
9. Confirm that no row was added to `matches` or `rating_events`, and no ranked ELO,
   win/loss record, limit, leaderboard, or dispute changed.

## Operational limitation

There is deliberately no game-duration timeout. A participant cannot leave while a game
is active; either participant must submit the real final score. If both abandon an
unfinished game, a trusted operator must inspect the physical-table situation and repair
the queue state directly in PostgreSQL. An explicit mutual-abandonment workflow can be
added later without coupling queue games to ranked matches.
