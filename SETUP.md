# Pongo Setup Guide

## Prerequisites

- Node.js 18+ installed
- Supabase account and project

## Step 1: Install Dependencies

```bash
npm install
```

## Step 2: Set Up Supabase

1. Create a new Supabase project at https://supabase.com
2. Go to Project Settings > API to get your credentials
3. Copy `.env.local.example` to `.env.local` and fill in:
   ```
   NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
   NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key
   SUPABASE_SERVICE_ROLE_KEY=your_server_only_service_role_key
   ```

## Step 3: Database Setup and Rollout

For a new or disposable local project, the migration chain is self-contained:

```bash
npx supabase start
npx supabase db reset
npm run test:db:local
npm run test:load:queue
```

`20260930000000_baseline_schema.sql` is the complete baseline. Apply every file
in `supabase/migrations` in filename order; do not create or apply a separate schema dump.

For an existing hosted project, first take a restorable database backup and
export the migration history. The historical files now use unique 14-digit
Supabase versions, so reconcile the remote migration ledger against the renamed
files before `supabase db push`. Review the generated plan in a disposable linked
project. Do not apply migrations through a Vercel/GitHub deployment.

Enable the Supabase Cron integration before applying
`20261104100000_queue_maintenance_worker.sql`. The migration creates the queue,
ranked-expiration, and Cron-history-retention jobs only when `pg_cron` is present.

## Step 4: Set Up Authentication

1. In Supabase Dashboard, go to Authentication > Providers
2. Enable Email provider
3. Under Authentication > Providers > Email, turn **Confirm email** off. This makes signup return a session immediately, matching `supabase/config.toml` for local projects.
4. Under Authentication > URL Configuration, set the production Site URL to `https://playpongo.vercel.app` and add both `http://localhost:3000/auth/callback` and `https://playpongo.vercel.app/auth/callback` to Redirect URLs.

## Step 5: Schedule Expiration

Migration `20261104100000` schedules `run_pongo_queue_maintenance_v1()` every
10 seconds and `run_pongo_ranked_maintenance_v1()` every five minutes. The first
advances every expired queue deadline without a browser; the second expires stale
challenges/matches/cancellations and escalates overdue disputes. A daily job keeps
seven days of Cron run history. Verify the jobs and both health RPCs using
`supabase/functions/queue-tick.sql`.

Active queue members heartbeat every 30 seconds. Realtime changes refetch state
but never create a heartbeat loop. The database workers remain authoritative when
all browsers are closed.

Weekly records do not need a reset job. `weekly_player_stats` stores one row per player and New York club week.

To verify the Phase 1 database rules against a disposable project, apply every migration and run:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase1_ranked_match_lifecycle.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase2_ranked_game_limits.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase3_weighted_elo.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase4_competitive_ranks.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase5_unified_leaderboards.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase6_disputes_corrections.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase7_mobile_experience.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/phase8_security_reliability.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/live_queue.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/queue_production_repair.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/queue_outcomes_swaps.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/queue_afk_timeouts.test.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/profile_settings_queue_alerts.test.sql
```

The scripts create fixed test users inside transactions and always roll back. Use `supabase/tests/phase1_concurrency.md` for ranked races and `supabase/tests/live_queue_concurrency.md` for queue races.

## Step 6: Run Development Server

```bash
npm run dev
```

Visit http://localhost:3000

## Step 7: Create Your First User

1. Go to `/login`
2. Sign up with email/password
3. Your profile will be automatically created

## Features

- ✅ ELO-based ranking system
- ✅ Challenge system with 24-hour expiration
- ✅ First-valid-score finalization after mutual challenge acceptance
- ✅ Three active ranked matches maximum and one unfinished match per opponent
- ✅ Mutual cancellation with complete request history
- ✅ Acceptance-time reservations with 10 ranked games per player per day
- ✅ Three ranked games per opponent per New York calendar day
- ✅ Asymmetric ranked ELO with K=70 wins, K=40 losses, and a hard zero floor
- ✅ Server-authoritative post-match calculation breakdowns without pre-match ELO disclosure
- ✅ Unranked first-time players and Iron-to-Legend competitive ranks after the first completed match
- ✅ Unified weekly, monthly, and all-time leaderboards with previous-winner archives
- ✅ Mutual post-result corrections and voids with admin escalation and downstream rating replay
- ✅ Mobile score confirmation, result feedback, live countdowns, and casual scorekeeping
- ✅ Immutable rating audit, least-privilege writes, match-farming signals, and optional independent reporting
- ✅ Real-time updates via Supabase Realtime
- ✅ Experimental one-table live queue with FIFO rotation, server-timed check-in, and winner-stays play
- ✅ Match history tracking

## Notes

- First-game ELO baseline: 50
- Win K-factor: 70; loss K-factor: 40
- Equal ratings produce +35 for the winner and −20 for the loser; score margin does not alter ELO
- Ranked ELO is intentionally non-zero-sum and cannot fall below 0
- Competitive tiers: Iron 0–99, Bronze 100–199, Silver 200–324, Gold 325–474, Platinum 475–649, Diamond 650–849, and Legend 850+
- A new player is Unranked until their first confirmed ranked match
- Challenges and accepted matches expire after 24 hours
- Ranked matches cannot be recorded without an accepted challenge
- Daily limits use the New York date when the challenge is accepted; crossing midnight does not move the match to a new day
- Weekly leaderboard periods run Monday through Sunday in `America/New_York`; monthly periods use New York calendar months
- Confirmed results may be disputed for 48 hours. Opening or declining a dispute never changes ratings; only mutual approval or an administrator decision can revise history
- Approved historical revisions serialize on a global replay lock, supersede rather than delete rating events, and rebuild downstream ratings and statistics
- Casual scorekeeping is local-only and never creates matches, consumes ranked limits, or changes ELO
- `domain_events` and internal recipient rows remain server-side audit/delivery infrastructure used by match and dispute workflows; there is no user-facing notification center
- Accounts placed in `dual_verification` by an administrator submit privately; only matching independent reports finalize, while conflicts expire without rating changes and enter the integrity queue
- Two administrator-confirmed reporting violations automatically place a normal account in monitored status; administrators still decide whether to require dual verification or restrict ranked play
- Queue outcomes are stored only in `beaver_queue_games`; they never affect ranked ELO, limits, records, disputes, or leaderboards
- Queue games use participant-only **I Won** / **I Lost** reporting. The first valid report wins atomically; the trusted worker records unfinished 10-minute games as abandoned audit rows and advances the queue
- Waiting players can request a 60-second mutual position swap only with someone ahead; both players must remain waiting and the target must accept
