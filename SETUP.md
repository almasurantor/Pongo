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
   ```

## Step 3: Database Setup and Rollout

For an existing Pongo project:

1. Export `profiles`, `matches`, and `challenges` before changing the schema.
2. Run `supabase/migrations/20261001_01_expand_mobile_ranking.sql` in the Supabase SQL Editor.
3. Verify profile ratings/records and the confirmed-match count are unchanged.
4. Deploy this compatible application and smoke-test reporting, confirmation, leaderboard, profile, and admin reads.
5. Run `supabase/migrations/20261001_02_contract_mobile_ranking.sql` only after the compatible deployment is live.
6. Run `supabase/migrations/20261001_03_fix_signup_and_mobile_scroll.sql` to install the current signup trigger.
7. Run `supabase/migrations/20261025_01_repair_stale_challenges.sql` so expired challenge rows cannot block or break future challenge actions.
8. Run `supabase/migrations/20261030_01_phase1_ranked_match_lifecycle.sql` immediately before deploying the Phase 1 application. This intentionally expires every unfinished legacy match without changing ratings.
9. Run `supabase/migrations/20261030_02_phase2_ranked_game_limits.sql` before deploying the Phase 2 application. It backfills each ranked match’s New York acceptance day and changes the daily pair cap from 20 to 3.
10. Run `supabase/migrations/20261031_01_phase3_weighted_elo.sql` before deploying the Phase 3 application. It changes only future finalizations to K=40 weighted ELO; historical match and rating-event deltas remain unchanged.
11. Run `supabase/migrations/20261031_02_phase4_competitive_ranks.sql` before deploying the Phase 4 application. It installs the seven automatic rank tiers and backfills rank labels onto rating events without changing any ELO value.
12. Run `supabase/migrations/20261031_03_phase5_unified_leaderboards.sql` before deploying the Phase 5 application. It installs New York-aware weekly/monthly/all-time leaderboard and archive RPCs over the immutable match and rating-event history.
13. Run `supabase/migrations/20261031_04_phase6_disputes_corrections.sql` before deploying the Phase 6 application. It installs the 48-hour mutual dispute workflow and serialized downstream rating replay. Take a fresh backup of profiles, matches, rating events, and statistics before applying it.
14. Run `supabase/migrations/20261031_05_phase7_mobile_experience.sql` before deploying the Phase 7 application. Phase 7 is application-only, so this migration intentionally records the rollout boundary without changing the database.
15. Run `supabase/migrations/20261031_06_phase8_security_reliability.sql` immediately before deploying the Phase 8 application. It hardens write privileges and audit immutability, activates administrator-controlled independent reporting, adds integrity signals, and expands the Realtime publication. Back up matches, rating events, submissions, integrity records, and domain events first.
16. Run `supabase/migrations/20261101_01_live_queue.sql` immediately before exposing `/queue`. It creates an isolated one-table live queue, server-authoritative 60-second calls, queue-only game history, least-privilege RPCs, and Realtime publication entries. It does not alter ranked matches, ratings, challenges, disputes, or leaderboards.
17. Run `supabase/migrations/20261101_02_v4_starting_elo_and_ranks.sql` to set new accounts to 500 ELO, recalibrate the Iron-to-Legend thresholds, and keep K=40. It does not reset existing profile ratings.
18. Run `supabase/migrations/20261102_01_profile_settings_queue_alerts.sql` to enforce unique public display names and add the opt-in queue sound and device-reminder preferences.
19. Run `supabase/migrations/20261103_01_coordinated_auth_rank_queue.sql` to remove placement ranks, add queue liveness cleanup, preserve K=40/500 starting ELO, and install challenge/match query indexes.

The expand migration is retry-safe, keeps the legacy columns/statuses during rollout, creates audited opening-balance events, and bootstraps `almasurantor` using profile UUID `494357c8-607e-4605-980b-19260c8a2cfc` as the first administrator. The old `migration_single_reporter_match_flow.sql` is superseded and must not be applied.

For a brand-new project, provision the legacy base schema from `supabase/schema.sql`, then apply all files in `supabase/migrations` in filename order before exposing the app to users.

## Step 4: Set Up Authentication

1. In Supabase Dashboard, go to Authentication > Providers
2. Enable Email provider
3. Under Authentication > Providers > Email, turn **Confirm email** off. This makes signup return a session immediately, matching `supabase/config.toml` for local projects.
4. Under Authentication > URL Configuration, set the Site URL and add `http://localhost:3000/auth/callback` plus `https://YOUR_DOMAIN/auth/callback` to Redirect URLs.
5. Enable Google OAuth and add your Google client ID and secret. In Google Cloud, set the authorized redirect URI to the Supabase callback shown by the provider panel (normally `https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback`), not the app callback URL.

## Step 5: Schedule Expiration

Call `expire_mobile_ranking_items_v2()` from a trusted scheduled worker or Supabase Edge Function every five minutes. It expires stale challenges, accepted matches, and their pending cancellation requests, and escalates unanswered result disputes to administrators without changing ratings or trust. The live project does not currently have `pg_cron`, so scheduling is intentionally external.

Call `beaver_queue_advance_expired_v1()` from a service-role worker every 5–15 seconds. This is the browser-independent path that removes a called player after 60 seconds and immediately calls the next player. `supabase/functions/queue-tick.sql` contains the worker query. Never expose the service-role key to the browser. The `/queue` client also performs authenticated ticks while open, but that is only a responsive fallback and not a replacement for the trusted worker.

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
2. Sign up with email/password or Google
3. Your profile will be automatically created

## Features

- ✅ ELO-based ranking system
- ✅ Challenge system with 24-hour expiration
- ✅ First-valid-score finalization after mutual challenge acceptance
- ✅ Three active ranked matches maximum and one unfinished match per opponent
- ✅ Mutual cancellation with complete request history
- ✅ Acceptance-time reservations with 10 ranked games per player per day
- ✅ Three ranked games per opponent per New York calendar day
- ✅ K=40 weighted, zero-sum ELO with a 10% maximum score adjustment
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

- Default ELO: 500
- K-factor: 40
- Score margin scales the base winner gain by 0–10%; a two-point win has no bonus and an 11-point margin reaches the cap
- The final winner gain is rounded once and applied as the loser’s exact inverse
- Competitive tiers: Iron below 650, Bronze 650, Silver 800, Gold 950, Platinum 1100, Diamond 1250, and Legend 1400+
- A new player is Unranked at 500 ELO; their threshold-based rank appears after the first confirmed ranked match
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
- Queue results are stored only in `beaver_queue_games`; they never affect ranked ELO, limits, records, disputes, or leaderboards
- Queue games deliberately have no duration timeout. If both participants abandon an active game without reporting it, a trusted operator must inspect the physical table and repair that queue state in the database; automatic abandonment rules can be added later without coupling the queue to ranked matches
