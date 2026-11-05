# Pongo test data

[`seed.testing.sql`](./seed.testing.sql) creates a large, repeatable fixture set for development and UI testing. It is intentionally not named `seed.sql`, so Supabase will not load it automatically.

Run it only after all migrations have been applied to a disposable or development database. In the hosted Supabase SQL editor:

1. Run every file in `supabase/migrations` in filename order, beginning with the
   complete `20260930000000_baseline_schema.sql` migration.
2. Confirm the chain reaches `20261104100000_queue_maintenance_worker.sql` before
   loading fixtures. The final ranking configuration uses a 50-ELO first-game
   baseline and the final queue RPC set.
3. Paste and run the entire `seed.testing.sql` file.

If the seed stops, its error now lists each missing migration by filename. The current repository has no local Supabase instance or authenticated CLI connection, so the fixture data is not applied automatically.

All fixture accounts use this password:

```text
PongoTest123!
```

Useful accounts:

| Email | Scenario |
| --- | --- |
| `iron.iris@pongo.test` | Iron rank |
| `bronze.ben@pongo.test` | Bronze rank and outgoing challenge |
| `silver.sam@pongo.test` | Silver rank and active match |
| `gold.gia@pongo.test` | Gold rank, incoming/outgoing challenges, active matches, cancellation, dispute, live game |
| `platinum.priya@pongo.test` | Platinum rank and pending challenge |
| `diamond.diego@pongo.test` | Diamond rank and cancellation response |
| `legend.luna@pongo.test` | Legend rank |
| `provisional.pixel@pongo.test` | Unranked player and open dispute |
| `monitored.morgan@pongo.test` | Monitored integrity state |
| `dual.dana@pongo.test` | Dual-verification match flow |
| `restricted.riley@pongo.test` | Ranked restriction |
| `queue.quinn@pongo.test` | Waiting queue member |
| `admin.avery@pongo.test` | Admin dispute and integrity views |
| `newcomer.nico@pongo.test` | New account with no history |

The script uses deterministic UUIDs and conflict-safe inserts, so it can be run again. Re-running resets profile fixture values and replaces only the transient live-queue state. It does not delete real profiles, ranked matches, or rating history.
