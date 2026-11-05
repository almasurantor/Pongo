# Pongo — Full Project Documentation

## 1. Project Purpose

Pongo is a competitive table tennis club app built for the CCNY Table Tennis Club. Its purpose is to give members a structured, game-based ladder system where players can:

- create accounts and sign in
- challenge each other directly
- submit match results
- finalize the first valid score and dispute incorrect results
- see live ELO rankings
- track weekly performance
- browse profiles and match history

At a high level, this is a club ladder app: it turns casual play into a measurable ranking system with rules, stats, and real-time feedback.

---

## 2. Product Summary

The app is a Next.js web application using Supabase for authentication, relational storage, and realtime updates. The main competitive mechanic is an ELO-based rating system. A unified leaderboard ranks weekly and monthly performance by net ELO gained and the all-time ladder by permanent ELO.

The project is designed around a club competition loop:

1. Player signs in
2. Player challenges another club member
3. Challenge is accepted and a match is created with a fresh 24-hour deadline
4. Either player reports the final score
5. The first valid report atomically updates ELO and records
6. Either player may instead request mutual cancellation before a score is finalized
7. Leaderboards and profiles refresh automatically

---

## 3. Tech Stack

- Next.js 16 (App Router)
- React 19
- TypeScript
- Tailwind CSS
- Framer Motion
- Supabase Auth + Postgres + Realtime
- React Hot Toast for feedback

The project combines server-rendered Next.js pages with realtime client-side updates for a modern leaderboard feel.

### Installable web app

The App Router publishes `/manifest.webmanifest` with `/` as its standalone launch URL and Pongo icons. Server middleware resolves that launch before rendering: an authenticated session opens `/dashboard`, while a signed-out session receives the landing page. Apple web-app metadata, `viewport-fit=cover`, Dynamic Island/home-indicator safe areas, and a fixed safe-area-aware mobile navigation make the Vercel-hosted site installable from iPhone Safari. The service worker caches only content-hashed app assets and public brand artwork; it never caches authenticated match, queue, ranking, API, or auth responses, and falls back to a static reconnect screen when navigation is unavailable.

---

## 4. Core Architecture

### Frontend

The app uses Next.js App Router under the [app](app) folder:

- [app/page.tsx](app/page.tsx) — landing page
- [app/dashboard/page.tsx](app/dashboard/page.tsx) and [app/dashboard/DashboardClient.tsx](app/dashboard/DashboardClient.tsx) — main power center for challenges and active matches
- [app/leaderboard/page.tsx](app/leaderboard/page.tsx) and [app/leaderboard/LeaderboardClient.tsx](app/leaderboard/LeaderboardClient.tsx) — unified weekly, monthly, all-time, and archived leaderboards
- [app/match/[id]/page.tsx](app/match/[id]/page.tsx) and [app/match/[id]/MatchClient.tsx](app/match/[id]/MatchClient.tsx) — score submission and match-resolution flow
- [app/profile/[id]/page.tsx](app/profile/[id]/page.tsx) and [app/profile/[id]/ProfileClient.tsx](app/profile/[id]/ProfileClient.tsx) — player stats and match history
- [app/login/page.tsx](app/login/page.tsx) and [app/signup/page.tsx](app/signup/page.tsx) — auth UI

### Backend / Data layer

- [lib/supabase/server.ts](lib/supabase/server.ts) creates a server-side Supabase client
- [lib/supabase/client.ts](lib/supabase/client.ts) creates a browser client
- [lib/supabase/middleware.ts](lib/supabase/middleware.ts) protects routes and refreshes session cookies
- [proxy.ts](proxy.ts) applies session middleware across the app

### Business logic

- [lib/elo.ts](lib/elo.ts) contains ELO calculation logic
- [app/api/matches/[id]/report/route.ts](app/api/matches/[id]/report/route.ts) accepts a complete result from one participant
- [app/api/matches/[id]/cancellation/route.ts](app/api/matches/[id]/cancellation/route.ts) handles mutual cancellation
- [supabase/migrations](supabase/migrations) is the sole authoritative database schema and function history

## 5. Data Model

The primary persistent entities are defined by the ordered files in [supabase/migrations](supabase/migrations) and represented in [lib/types.ts](lib/types.ts).

### profiles

This table extends Supabase auth users and stores per-player stats.

Key fields:

- id — UUID, linked to auth.users
- display_name — user-facing name
- current_elo — total rating, initial value 50
- total_wins / total_losses — lifetime record
- weekly_wins / weekly_losses — this week’s record
- created_at / updated_at

### challenges

Players can send challenges to one another.

Fields:

- id
- challenger_id
- opponent_id
- status — pending, accepted, declined, expired, completed
- created_at
- expires_at

The schema enforces no self-challenge and a unique pending challenge pair between two players.

### matches

Matches are created when a challenge is accepted.

Fields include:

- id
- challenge_id
- player_one_id / player_two_id
- player_one_score / player_two_score
- status — ready, confirmed, expired, canceled, voided (`result_reported` is used only inside the finalization transaction)
- source / ranked / winner_id / verification_mode / request_id / season_id
- ranked_day — the `America/New_York` calendar day on which capacity was reserved at acceptance
- reported_by / reported_at — the participant who entered both scores and when
- confirmed_by — the participant whose first valid submission finalized the result
- expires_at
- player_one_elo_before / player_two_elo_before
- player_one_elo_change / player_two_elo_change
- confirmed_at
- created_at

### match_history

This is a SQL view that exposes confirmed match results for easier history queries and profile pages.

### match_cancellation_requests

Cancellation requests are stored separately with pending, approved, declined, or expired status. This preserves every request while keeping the accepted match deadline unchanged.

Accepted and confirmed matches reserve capacity through their `ranked_day`. Canceled, expired, and voided matches remain historical but no longer consume that capacity.

---

## 6. Main Business Flow

### A. Authentication

Users sign up through [app/signup/page.tsx](app/signup/page.tsx) or log in through [app/login/page.tsx](app/login/page.tsx). The app uses Supabase Auth, and [app/auth/callback/route.ts](app/auth/callback/route.ts) handles OAuth redirect completion.

Route protection is enforced via [proxy.ts](proxy.ts) + [lib/supabase/middleware.ts](lib/supabase/middleware.ts): unauthenticated users are redirected to the public root unless they are already on a public or auth route.

### B. Dashboard and challenge workflow

The dashboard in [app/dashboard/DashboardClient.tsx](app/dashboard/DashboardClient.tsx) is the center of the product.

From there, the user can:

- view all players ranking by ELO
- see pending challenges sent to or from them
- accept or decline incoming challenges
- cancel their own pending challenges
- see active matches in progress
- open any match page to submit a result

A challenge is inserted into the challenges table and the dashboard subscribes to realtime updates for challenge changes.

### C. Match submission and validation

The match screen in [app/match/[id]/MatchClient.tsx](app/match/[id]/MatchClient.tsx) allows either participant to report both players' final scores after a challenge has been accepted. Spontaneous ranked recording is disabled.

The app enforces table tennis-style rules:

- at least one player must reach 11
- if both players are 10 or below, the match is invalid
- the winner must lead by at least two points
- after 10–10, play continues until one player leads by exactly 2
- no tied scores are allowed

For normal accounts, the first valid report stores the score and immediately finalizes ratings in one database transaction. A concurrent or repeated report returns the stored result without applying ELO twice. When an administrator has placed either participant in `dual_verification`, both players report privately: matching independent reports finalize once, while a conflict expires the match without ratings and creates an administrator-visible integrity signal.

### D. Cancellation and expiration

Either player may request cancellation while the match is active. The opponent can approve or decline; approval cancels without rating changes. Pending cancellation never pauses the 24-hour match deadline and does not block score reporting.

### E. Match confirmation and ELO update

When the first participant submits a valid score, the database transaction:

1. loads both players’ profiles
2. calculates ELO gain/loss using [lib/elo.ts](lib/elo.ts)
3. stores the match result as confirmed
4. records player ELO before/after values and the actual rating delta
5. updates overall and weekly win/loss stats
6. marks the linked challenge complete, when one exists

The row and both player profiles are locked during finalization, so repeated requests cannot apply stats twice.

This is the point where the ladder actually updates.

---

## 7. ELO System

The ranking logic is implemented in [lib/elo.ts](lib/elo.ts).

### Asymmetric ranked ELO formula

The expected score for player A is:

$$
E_A = \frac{1}{1 + 10^{(R_B - R_A)/400}}
$$

Where:

- $R_A$ is player A’s current ELO
- $R_B$ is player B’s current ELO

The winner gain and loser loss are calculated independently:

$$
\Delta R_{win} = 70 \times (1 - E_{winner})
$$

$$
\Delta R_{loss} = 40 \times E_{loser}
$$

Both values are rounded to the nearest integer. Equal ratings therefore produce exactly +35 for the winner and −20 for the loser. The system is intentionally not zero-sum, score margin does not change ELO, and the loser’s result is clamped so a rating can never fall below zero.

Each new confirmed match and its two immutable rating events store the formula version, both K-factors, expected probabilities, raw and rounded changes, and whether the zero floor was applied. Older matches retain their original deltas and calculation snapshots.

### Competitive rank tiers

[lib/ranks.ts](lib/ranks.ts) derives a player's competitive tier directly from permanent `current_elo`; no administrator assigns ranks and no stale rank value is stored on a profile. The ladder is Iron 0–99, Bronze 100–199, Silver 200–324, Gold 325–474, Platinum 475–649, Diamond 650–849, and Legend at 850+. New players remain Unranked until their first confirmed ranked match, which uses a 50-ELO starting baseline.

The Phase 4 migration stores these boundaries in `competitive_rank_tiers`, exposes database-side tier/progress functions, and snapshots `rank_before` and `rank_after` on every rating event. That snapshot preserves promotion and demotion history if thresholds are adjusted later. Code-native badges and progress indicators appear on profiles, challenges, matches, player discovery, the dashboard, and the all-time leaderboard. There are no divisions or inactivity decay.

---

## 8. Unified Leaderboard Logic

The leaderboard has Weekly, Monthly, and All Time tabs. Weekly periods run Monday through Sunday and monthly periods follow calendar months, always using `America/New_York`. Weekly and monthly standings rank active players by net ELO gained, then wins and current ELO as deterministic tie breakers. All Time ranks every profile by permanent current ELO.

`get_leaderboard_v3` derives period statistics from retained confirmed ranked matches and active immutable rating events. Each row includes games, wins, losses, win rate, unique opponents, net ELO, competitive rank, and provisional status. Because rating events are joined through the match's original `confirmed_at`, an approved correction updates the proper historical week or month rather than the correction date. `get_leaderboard_archive_v3` exposes completed periods and previous winners without destructive resets. The UI shows the top ten plus the signed-in player's placement when they are outside it. `/weekly` redirects to the unified weekly tab for compatibility.

### Result disputes and historical replay

Either participant can open a dispute during the 48 hours after finalization for an incorrect score, incorrect winner, nonexistent match, or another issue. A dispute requests either a corrected score or a void. Opening the request leaves the confirmed result, ratings, statistics, and leaderboard unchanged. Only the opponent can approve the request automatically; declining it or allowing the response deadline to pass escalates it to administrators without changing ELO.

Mutually or administratively approved revisions are serialized by a global transaction lock. The original match revision and rating events remain stored, are marked inactive, and point to replacement events. PostgreSQL replays every subsequent ranked match chronologically with the asymmetric ELO formula and zero floor, then rebuilds current and peak ratings, records, current/longest streaks, weekly rows, season rows, ranks, and leaderboard inputs. Approved voids remove the disputed match from the replay. `match_revisions`, `rating_events`, and `domain_events` retain the complete audit and decision history.

### Mobile match experience

Active matches and challenges display a live second-level deadline countdown while the existing 60-second refresh and focus refresh remain as recovery paths. Ranked result entry now has an explicit review dialog showing the selected winner, exact score, and estimated ELO before submission. A successful report displays victory/defeat feedback, the final rating change, current all-time placement, and any placement movement.

The `/play/casual` scorekeeper is intentionally local-only: it supports game-to-11, win-by-two scoring and never writes a match or affects ranked limits, statistics, or ELO.

### Security, audit, and integrity reliability

Ranked writes remain inside `SECURITY DEFINER` PostgreSQL RPCs with fixed `search_path` values. Authenticated and anonymous roles cannot directly mutate matches, challenges, submissions, disputes, rating events, integrity records, configuration, or computed statistics; profile edits are limited to the caller's `display_name` under RLS. Rating-event facts, private submissions, match revisions, and domain events are append-only. Rating replay may only deactivate/supersede old rating events, and a partial unique index enforces one active event per match/player revision.

Finalization emits automated integrity signals when a pair reaches the three-game daily ceiling or a player reaches unusually high same-day ranked volume. Two administrator-confirmed violations automatically move a normal account to monitored status. Administrators can review signals, choose dual verification, or restrict ranked access. Dual reports are stored separately and are visible only to their submitter and administrators, preventing one participant from copying the other's report.

---

## 9. Realtime Behavior

Realtime is a key UX property of the app.

Interactive screens subscribe only to the Supabase `postgres_changes` tables they consume. Event bursts are debounced into one server-data refresh, and returning to a sleeping phone tab performs one freshness check without a permanent polling loop. This makes the app feel live while avoiding unrelated full-page refreshes:

- new challenge appears immediately
- accepted challenge updates the active match list
- confirmed matches trigger ELO refresh
- leaderboard standings update without a manual reload

This is implemented through [lib/use-database-refresh.ts](lib/use-database-refresh.ts) and the individual screen clients.

---

## 10. Database Functions and Rules

The ordered SQL in [supabase/migrations](supabase/migrations) includes several important rules:

- `check_daily_match_limit` — prevents overplaying between the same two players in one day
- `get_my_ranked_usage_v3` / `get_my_opponent_ranked_usage_v3` — expose authoritative reservation usage to the UI
- `create_challenge_v2` / `respond_challenge_v2` / `cancel_challenge_v2`
- `submit_match_report_v2` — stores the first score and atomically applies ELO/stats once
- `request_match_cancellation_v2` / `respond_match_cancellation_v2`
- `admin_resolve_dispute_v3` / `admin_set_player_integrity_v2` / `admin_review_integrity_flag_v3`
- `expire_mobile_ranking_items_v2` — expires unresolved work without changing stats or trust

There are also indexes and unique constraints to prevent duplicate pending challenges, enforce one ready match per unordered player pair, and query New York acceptance-day reservations efficiently.

---

## 11. Project Structure

### Root-level files

- [package.json](package.json) — app scripts and dependencies
- [README.md](README.md) — brief project intro
- [ENV_SETUP.md](ENV_SETUP.md) / [env.local.template](env.local.template) — environment config guidance
- [INSTALL_NODE.md](INSTALL_NODE.md) — installation notes
- [SETUP.md](SETUP.md) — setup steps

### App folders

- [app](app) — pages and route-driven UI
- [components](components) — shared UI pieces like navbar and animation
- [lib](lib) — shared logic and typed models
- [public](public) — static files and club branding assets
- [supabase](supabase) — schema, migrations, SQL helpers

---

## 12. Current Product Experience

The product feels like a polished club competition app rather than a generic leaderboard. It includes strong UI touches:

- big gradient design
- animated table tennis graphics
- match cards with acceptance/decline actions
- live status banners for reported, disputed, and expired matches
- profile cards and leaderboards showing total and weekly statistics

This is a member-facing experience designed for quick competition and clear status updates.

---

## 13. What the App Is Trying to Solve

The core problem this project addresses is the lack of a clean, club-specific ranked system for table tennis matches. Without something like this, results are hard to track, disputes are messy, and there is no simple ladder or leaderboard to motivate continuous play.

Pongo solves this by building a structured flow around:

- trustable match confirmation
- transparent ELO changes
- active challenge creation
- visible standings
- weekly bragging rights

---

## 14. Key Implementation Notes

A few important observations from reading the codebase:

- The app relies heavily on Supabase for both persistence and realtime behavior.
- ELO is calculated transactionally in PostgreSQL; the client calculation is used only for clearly labeled estimates.
- The database stores authoritative match and stat data; the frontend acts as a display layer plus user-triggered update layer.
- The app centers on a player challenge-and-match loop with a restricted administrator review panel.
- There is a strong emphasis on club-style game flow and quick feedback, reflected in the mobile-first match UI and live database refreshes.

---

## 15. Risks / Gaps to Be Aware Of

As a codebase summary, a few product/engineering caveats are worth noting:

- Vitest covers auth startup routing, score validation, asymmetric ELO, rank tiers, leaderboard periods, deadlines, and lifecycle helpers. Rollback-only SQL suites cover ranked finalization and defaults, including limits, replay, the zero floor, RLS, role privileges, audit immutability, and independent reporting; the multi-session checklist covers lock races.
- Some features rely on database SQL functions and cron jobs being configured correctly in Supabase.
- The app uses environment variables and expects a real Supabase project to be configured.
- A few flows depend on browser timing and states, so they should be tested in a real staging environment before production use.
- The app assumes a club environment where users are authenticated and trusted but still requires match-validation safeguards.

---

## 16. Final Overall Assessment

Pongo is a full-stack club-ranking app for table tennis match competition. It is not just a leaderboard; it is a full lifecycle management system for challenges, match submissions, validation, ELO adjustment, and profile tracking.

The project’s central concept is simple and effective:

- challenge a player
- play a match
- submit and immediately finalize a valid score
- mutually correct or void an incorrect result when needed
- update ELO and rankings

It is a strong example of a lightweight sports ladder product built with modern web tooling and realtime database features.

---

## 17. Quick File Map

- [app/page.tsx](app/page.tsx) — landing page
- [app/dashboard/DashboardClient.tsx](app/dashboard/DashboardClient.tsx) — main challenge and active-match flow
- [app/leaderboard/LeaderboardClient.tsx](app/leaderboard/LeaderboardClient.tsx) — weekly, monthly, all-time, and historical leaderboard UI
- [app/match/[id]/MatchClient.tsx](app/match/[id]/MatchClient.tsx) — match submission UI
- [app/api/matches/[id]/report/route.ts](app/api/matches/[id]/report/route.ts) — result reporting endpoint
- [app/api/matches/[id]/cancellation/route.ts](app/api/matches/[id]/cancellation/route.ts) — active-match cancellation requests and responses
- [app/api/matches/[id]/dispute/route.ts](app/api/matches/[id]/dispute/route.ts) — post-result correction and void requests
- [lib/elo.ts](lib/elo.ts) — rating algorithm
- [supabase/migrations](supabase/migrations) — authoritative data model and SQL logic
- [lib/types.ts](lib/types.ts) — TypeScript interfaces

If you want, the next step can be a more opinionated “engineering deep dive” that focuses on startup flow, data pipelines, and the exact match lifecycle from challenge creation to final ELO update.
