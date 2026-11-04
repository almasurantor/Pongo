# Pongo - CCNY Table Tennis Club Ladder System

A ranked 1v1 ELO-based ladder system with weekly, monthly, and all-time leaderboards for the CCNY Table Tennis Club.

## Tech Stack

- Next.js 14 (App Router)
- TypeScript
- TailwindCSS
- Framer Motion
- Supabase (Auth + PostgreSQL + Realtime)

## Setup

1. Install dependencies:
```bash
npm install
```

2. Set up environment variables:
```bash
cp env.local.template .env.local
# Add your Supabase credentials
```

3. Set up the database using the staged instructions in `SETUP.md`. Existing installations must run the expand migration, deploy this application, and only then run the contract migration.

4. Run the development server:
```bash
npm run dev
```

## Features

- ELO-based ranking system
- Challenge system with expiration
- Challenge-only ranked matches with mutual acceptance
- First-valid-score finalization with transaction-safe ELO updates
- Mutual cancellation and 24-hour match expiration without rating penalties
- Acceptance-time reservations enforcing 10 ranked games per day and 3 per opponent
- New York calendar-day usage shown on dashboards and player cards
- Asymmetric ranked ELO with K=70 wins, K=40 losses, and a hard zero floor
- ELO changes hidden until server-authoritative finalization, followed by an immutable post-match calculation breakdown
- Unranked new players use a 50-ELO first-game baseline, then seven automatic tiers from Iron through Legend
- Unified weekly, monthly, and all-time leaderboards with New York period boundaries, net-ELO ranking, full player statistics, and historical winner archives
- 48-hour result disputes with mutual corrections/voids, admin escalation, immutable revisions, and downstream rating replay
- Mobile-first score confirmation, live deadlines, victory/defeat feedback, and an ELO-free casual scorekeeper
- Least-privilege database writes, immutable rating/audit facts, automated integrity signals, and optional private dual reporting
- Real-time updates
- Match history tracking
- Disputes, admin review, rating-event history, and player trust controls

## Install on a phone

Pongo includes an App Router web manifest, branded PWA icons, standalone display metadata, safe-area layout support, and a conservative service worker. Live Supabase pages are always network-first; only the static offline explanation and app icons are cached.

On iPhone, open the deployed HTTPS site in Safari, tap **Share**, choose **Add to Home Screen**, confirm the name **Pongo**, and tap **Add**. Launching that icon opens the site in a standalone window. On supported Android browsers, use **Install App** or **Add to Home Screen** from the browser menu.

For Vercel, configure `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`, disable **Confirm email**, and add `https://YOUR_DOMAIN/auth/callback` to the Supabase Auth redirect allowlist. For Google, use the Supabase `/auth/v1/callback` URL shown in its provider panel as the Google Cloud redirect URI. Verify `/manifest.webmanifest`, `/sw.js`, `/icon.png`, and `/apple-icon.png` after deployment.
