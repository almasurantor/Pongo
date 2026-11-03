-- BeaverSmash development fixtures.
--
-- TEST DATABASES ONLY. This script creates fake login accounts and replaces
-- the current live-queue state. Run it after every migration, including
-- 20261102_01_profile_settings_queue_alerts.sql.
-- All accounts use the password: BeaverTest123!
-- All fixture emails end in: @beaversmash.test

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $migration_check$
DECLARE
  missing TEXT[] := ARRAY[]::TEXT[];
BEGIN
  IF to_regclass('public.ranking_config') IS NULL THEN
    missing := array_append(missing, '20261001_01_expand_mobile_ranking.sql');
    missing := array_append(missing, '20261001_02_contract_mobile_ranking.sql');
    missing := array_append(missing, '20261001_03_fix_signup_and_mobile_scroll.sql');
    missing := array_append(missing, '20261025_01_repair_stale_challenges.sql');
  ELSIF to_regprocedure('public.create_challenge_v2(uuid)') IS NULL THEN
    missing := array_append(missing, '20261025_01_repair_stale_challenges.sql');
  END IF;
  IF to_regclass('public.match_cancellation_requests') IS NULL THEN
    missing := array_append(missing, '20261030_01_phase1_ranked_match_lifecycle.sql');
  END IF;
  IF to_regprocedure('public.club_ranked_day_v3(timestamp with time zone)') IS NULL THEN
    missing := array_append(missing, '20261030_02_phase2_ranked_game_limits.sql');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'rating_events'
      AND column_name = 'calculation'
  ) THEN
    missing := array_append(missing, '20261031_01_phase3_weighted_elo.sql');
  END IF;
  IF to_regclass('public.competitive_rank_tiers') IS NULL THEN
    missing := array_append(missing, '20261031_02_phase4_competitive_ranks.sql');
  END IF;
  IF to_regprocedure('public.get_leaderboard_v3(text,date)') IS NULL THEN
    missing := array_append(missing, '20261031_03_phase5_unified_leaderboards.sql');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'disputes'
      AND column_name = 'requested_resolution'
  ) THEN
    missing := array_append(missing, '20261031_04_phase6_disputes_corrections.sql');
  END IF;
  IF to_regprocedure('public.protect_rating_event_ledger_v3()') IS NULL THEN
    missing := array_append(missing, '20261031_06_phase8_security_reliability.sql');
  END IF;
  IF to_regclass('public.ranking_config') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.ranking_config WHERE id AND starting_elo = 500 AND k_factor = 40
  ) THEN
    missing := array_append(missing, '20261101_02_v4_starting_elo_and_ranks.sql');
  END IF;
  IF to_regclass('public.beaver_queue_members') IS NULL
     OR to_regprocedure('public.beaver_queue_tick_v1()') IS NULL THEN
    missing := array_append(missing, '20261101_01_live_queue.sql');
  END IF;
  IF to_regprocedure('public.update_my_profile_settings_v4(text,boolean,boolean)') IS NULL THEN
    missing := array_append(missing, '20261102_01_profile_settings_queue_alerts.sql');
  END IF;

  IF cardinality(missing) > 0 THEN
    RAISE EXCEPTION 'Missing migrations: %', array_to_string(missing, ', ');
  END IF;
END;
$migration_check$;

-- Login accounts -----------------------------------------------------------

WITH fixture_users(id, email, display_name) AS (
  VALUES
    ('d0000000-0000-4000-8000-000000000001'::UUID, 'iron.iris@beaversmash.test', 'Iron Iris'),
    ('d0000000-0000-4000-8000-000000000002'::UUID, 'bronze.ben@beaversmash.test', 'Bronze Ben'),
    ('d0000000-0000-4000-8000-000000000003'::UUID, 'silver.sam@beaversmash.test', 'Silver Sam'),
    ('d0000000-0000-4000-8000-000000000004'::UUID, 'gold.gia@beaversmash.test', 'Gold Gia'),
    ('d0000000-0000-4000-8000-000000000005'::UUID, 'platinum.priya@beaversmash.test', 'Platinum Priya'),
    ('d0000000-0000-4000-8000-000000000006'::UUID, 'diamond.diego@beaversmash.test', 'Diamond Diego'),
    ('d0000000-0000-4000-8000-000000000007'::UUID, 'legend.luna@beaversmash.test', 'Legend Luna'),
    ('d0000000-0000-4000-8000-000000000008'::UUID, 'provisional.pixel@beaversmash.test', 'Provisional Pixel'),
    ('d0000000-0000-4000-8000-000000000009'::UUID, 'monitored.morgan@beaversmash.test', 'Monitored Morgan'),
    ('d0000000-0000-4000-8000-000000000010'::UUID, 'dual.dana@beaversmash.test', 'Dual Dana'),
    ('d0000000-0000-4000-8000-000000000011'::UUID, 'restricted.riley@beaversmash.test', 'Restricted Riley'),
    ('d0000000-0000-4000-8000-000000000012'::UUID, 'queue.quinn@beaversmash.test', 'Queue Quinn'),
    ('d0000000-0000-4000-8000-000000000013'::UUID, 'admin.avery@beaversmash.test', 'Admin Avery'),
    ('d0000000-0000-4000-8000-000000000014'::UUID, 'newcomer.nico@beaversmash.test', 'Newcomer Nico')
)
INSERT INTO auth.users(
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, recovery_token,
  email_change_token_new, email_change
)
SELECT
  '00000000-0000-0000-0000-000000000000'::UUID,
  fixture.id,
  'authenticated',
  'authenticated',
  fixture.email,
  crypt('BeaverTest123!', gen_salt('bf')),
  NOW(),
  jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
  jsonb_build_object('display_name', fixture.display_name, 'fixture', TRUE),
  NOW() - INTERVAL '90 days',
  NOW(),
  '', '', '', ''
FROM fixture_users fixture
ON CONFLICT (id) DO UPDATE SET
  email = EXCLUDED.email,
  encrypted_password = EXCLUDED.encrypted_password,
  email_confirmed_at = EXCLUDED.email_confirmed_at,
  raw_app_meta_data = EXCLUDED.raw_app_meta_data,
  raw_user_meta_data = EXCLUDED.raw_user_meta_data,
  updated_at = NOW();

-- auth.identities changed its key name across GoTrue versions. Support both
-- layouts so this seed works with current hosted projects and older local DBs.
DO $identity_seed$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'auth' AND table_name = 'identities'
      AND column_name = 'provider_id'
  ) THEN
    EXECUTE $sql$
      INSERT INTO auth.identities(
        provider_id, user_id, identity_data, provider,
        last_sign_in_at, created_at, updated_at
      )
      SELECT id::TEXT, id,
        jsonb_build_object('sub', id::TEXT, 'email', email),
        'email', NOW(), created_at, NOW()
      FROM auth.users
      WHERE email LIKE '%@beaversmash.test'
      ON CONFLICT DO NOTHING
    $sql$;
  ELSE
    EXECUTE $sql$
      INSERT INTO auth.identities(
        id, user_id, identity_data, provider,
        last_sign_in_at, created_at, updated_at
      )
      SELECT id, id,
        jsonb_build_object('sub', id::TEXT, 'email', email),
        'email', NOW(), created_at, NOW()
      FROM auth.users
      WHERE email LIKE '%@beaversmash.test'
      ON CONFLICT DO NOTHING
    $sql$;
  END IF;
END;
$identity_seed$;

-- Rank, record, and account-state variety -------------------------------

WITH fixture_profiles(
  id, display_name, elo, high_elo, wins, losses,
  weekly_wins, weekly_losses, streak, longest_streak
) AS (
  VALUES
    ('d0000000-0000-4000-8000-000000000001'::UUID, 'Iron Iris',        500,  590,  3, 16, 0, 2, -4,  2),
    ('d0000000-0000-4000-8000-000000000002'::UUID, 'Bronze Ben',       700,  760,  8, 13, 1, 2, -1,  4),
    ('d0000000-0000-4000-8000-000000000003'::UUID, 'Silver Sam',       850,  920, 14, 12, 2, 1,  2,  5),
    ('d0000000-0000-4000-8000-000000000004'::UUID, 'Gold Gia',        1079, 1120, 20, 14, 1, 1,  1,  6),
    ('d0000000-0000-4000-8000-000000000005'::UUID, 'Platinum Priya',  1179, 1210, 27, 12, 1, 1,  1,  8),
    ('d0000000-0000-4000-8000-000000000006'::UUID, 'Diamond Diego',   1292, 1330, 35, 11, 1, 2, -1, 11),
    ('d0000000-0000-4000-8000-000000000007'::UUID, 'Legend Luna',     1432, 1465, 44,  8, 2, 1,  1, 14),
    ('d0000000-0000-4000-8000-000000000008'::UUID, 'Provisional Pixel',1008, 1029,  1,  1, 0, 1, -1,  1),
    ('d0000000-0000-4000-8000-000000000009'::UUID, 'Monitored Morgan',1101, 1140, 17, 17, 0, 1, -1,  5),
    ('d0000000-0000-4000-8000-000000000010'::UUID, 'Dual Dana',       1239, 1239, 26, 10, 2, 0,  3,  7),
    ('d0000000-0000-4000-8000-000000000011'::UUID, 'Restricted Riley', 980, 1060, 10, 19, 0, 1, -3,  3),
    ('d0000000-0000-4000-8000-000000000012'::UUID, 'Queue Quinn',     1053, 1090, 15, 15, 1, 1, -1,  4),
    ('d0000000-0000-4000-8000-000000000013'::UUID, 'Admin Avery',     1200, 1200,  0,  0, 0, 0,  0,  0),
    ('d0000000-0000-4000-8000-000000000014'::UUID, 'Newcomer Nico',   1000, 1000,  0,  0, 0, 0,  0,  0)
)
INSERT INTO public.profiles(
  id, display_name, current_elo, highest_elo, total_wins, total_losses,
  weekly_wins, weekly_losses, current_streak, longest_streak, updated_at
)
SELECT
  fixture.id, fixture.display_name, fixture.elo, fixture.high_elo,
  fixture.wins, fixture.losses, fixture.weekly_wins, fixture.weekly_losses,
  fixture.streak, fixture.longest_streak, NOW()
FROM fixture_profiles fixture
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  current_elo = EXCLUDED.current_elo,
  highest_elo = EXCLUDED.highest_elo,
  total_wins = EXCLUDED.total_wins,
  total_losses = EXCLUDED.total_losses,
  weekly_wins = EXCLUDED.weekly_wins,
  weekly_losses = EXCLUDED.weekly_losses,
  current_streak = EXCLUDED.current_streak,
  longest_streak = EXCLUDED.longest_streak,
  updated_at = NOW();

INSERT INTO public.player_integrity(
  player_id, verification_level, confirmed_violations, restriction_reason
)
VALUES
  ('d0000000-0000-4000-8000-000000000009', 'monitored', 2, 'Fixture: monitored account'),
  ('d0000000-0000-4000-8000-000000000010', 'dual_verification', 1, 'Fixture: both reports must match'),
  ('d0000000-0000-4000-8000-000000000011', 'ranked_restricted', 3, 'Fixture: ranked play restricted')
ON CONFLICT (player_id) DO UPDATE SET
  verification_level = EXCLUDED.verification_level,
  confirmed_violations = EXCLUDED.confirmed_violations,
  restriction_reason = EXCLUDED.restriction_reason,
  updated_at = NOW();

INSERT INTO public.user_roles(user_id, role)
VALUES ('d0000000-0000-4000-8000-000000000013', 'admin')
ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role;

-- Historical ranked matches. Dates are relative so weekly and monthly tabs
-- always contain useful data whenever the seed is run.
WITH fixture_matches(
  id, player_one, player_two, winner, one_score, two_score,
  one_before, one_change, two_before, two_change, age
) AS (
  VALUES
    ('d1000000-0000-4000-8000-000000000001'::UUID, 'd0000000-0000-4000-8000-000000000002'::UUID, 'd0000000-0000-4000-8000-000000000001'::UUID, 'd0000000-0000-4000-8000-000000000002'::UUID, 11,  7,  900,  18,  840, -18, INTERVAL '24 days'),
    ('d1000000-0000-4000-8000-000000000002'::UUID, 'd0000000-0000-4000-8000-000000000003'::UUID, 'd0000000-0000-4000-8000-000000000002'::UUID, 'd0000000-0000-4000-8000-000000000003'::UUID, 11,  9,  950,  23,  918, -23, INTERVAL '20 days'),
    ('d1000000-0000-4000-8000-000000000003'::UUID, 'd0000000-0000-4000-8000-000000000004'::UUID, 'd0000000-0000-4000-8000-000000000003'::UUID, 'd0000000-0000-4000-8000-000000000004'::UUID, 11,  8, 1080,  24,  973, -24, INTERVAL '15 days'),
    ('d1000000-0000-4000-8000-000000000004'::UUID, 'd0000000-0000-4000-8000-000000000005'::UUID, 'd0000000-0000-4000-8000-000000000004'::UUID, 'd0000000-0000-4000-8000-000000000005'::UUID, 12, 10, 1180,  24, 1104, -24, INTERVAL '12 days'),
    ('d1000000-0000-4000-8000-000000000005'::UUID, 'd0000000-0000-4000-8000-000000000006'::UUID, 'd0000000-0000-4000-8000-000000000005'::UUID, 'd0000000-0000-4000-8000-000000000006'::UUID, 11,  9, 1280,  24, 1204, -24, INTERVAL '10 days'),
    ('d1000000-0000-4000-8000-000000000006'::UUID, 'd0000000-0000-4000-8000-000000000007'::UUID, 'd0000000-0000-4000-8000-000000000006'::UUID, 'd0000000-0000-4000-8000-000000000007'::UUID, 11,  6, 1420,  24, 1304, -24, INTERVAL '8 days'),
    ('d1000000-0000-4000-8000-000000000007'::UUID, 'd0000000-0000-4000-8000-000000000008'::UUID, 'd0000000-0000-4000-8000-000000000001'::UUID, 'd0000000-0000-4000-8000-000000000008'::UUID, 11,  4, 1000,  29,  822, -29, INTERVAL '6 days'),
    ('d1000000-0000-4000-8000-000000000008'::UUID, 'd0000000-0000-4000-8000-000000000009'::UUID, 'd0000000-0000-4000-8000-000000000004'::UUID, 'd0000000-0000-4000-8000-000000000009'::UUID, 11,  9, 1100,  22, 1080, -22, INTERVAL '5 days'),
    ('d1000000-0000-4000-8000-000000000009'::UUID, 'd0000000-0000-4000-8000-000000000010'::UUID, 'd0000000-0000-4000-8000-000000000005'::UUID, 'd0000000-0000-4000-8000-000000000010'::UUID, 11,  8, 1200,  22, 1180, -22, INTERVAL '4 days'),
    ('d1000000-0000-4000-8000-000000000010'::UUID, 'd0000000-0000-4000-8000-000000000012'::UUID, 'd0000000-0000-4000-8000-000000000011'::UUID, 'd0000000-0000-4000-8000-000000000012'::UUID, 11,  5, 1050,  20, 1000, -20, INTERVAL '3 days'),
    ('d1000000-0000-4000-8000-000000000011'::UUID, 'd0000000-0000-4000-8000-000000000006'::UUID, 'd0000000-0000-4000-8000-000000000007'::UUID, 'd0000000-0000-4000-8000-000000000006'::UUID, 13, 11, 1280,  31, 1444, -31, INTERVAL '2 days'),
    ('d1000000-0000-4000-8000-000000000012'::UUID, 'd0000000-0000-4000-8000-000000000004'::UUID, 'd0000000-0000-4000-8000-000000000008'::UUID, 'd0000000-0000-4000-8000-000000000004'::UUID, 11,  9, 1058,  21, 1029, -21, INTERVAL '1 day'),
    ('d1000000-0000-4000-8000-000000000013'::UUID, 'd0000000-0000-4000-8000-000000000005'::UUID, 'd0000000-0000-4000-8000-000000000009'::UUID, 'd0000000-0000-4000-8000-000000000005'::UUID, 11,  7, 1158,  21, 1122, -21, INTERVAL '12 hours'),
    ('d1000000-0000-4000-8000-000000000014'::UUID, 'd0000000-0000-4000-8000-000000000010'::UUID, 'd0000000-0000-4000-8000-000000000012'::UUID, 'd0000000-0000-4000-8000-000000000010'::UUID, 11,  8, 1222,  17, 1070, -17, INTERVAL '6 hours'),
    ('d1000000-0000-4000-8000-000000000015'::UUID, 'd0000000-0000-4000-8000-000000000003'::UUID, 'd0000000-0000-4000-8000-000000000002'::UUID, 'd0000000-0000-4000-8000-000000000003'::UUID, 11,  9,  949,  16,  895, -16, INTERVAL '3 hours'),
    ('d1000000-0000-4000-8000-000000000016'::UUID, 'd0000000-0000-4000-8000-000000000007'::UUID, 'd0000000-0000-4000-8000-000000000006'::UUID, 'd0000000-0000-4000-8000-000000000007'::UUID, 11,  8, 1413,  19, 1311, -19, INTERVAL '1 hour')
)
INSERT INTO public.matches(
  id, player_one_id, player_two_id, status, source, ranked, ranked_day,
  winner_id, player_one_score, player_two_score, reported_by, reported_at,
  confirmed_by, confirmed_at, finalized_at,
  player_one_elo_before, player_two_elo_before,
  player_one_elo_change, player_two_elo_change,
  verification_mode, revision, created_at
)
SELECT
  fixture.id, fixture.player_one, fixture.player_two, 'confirmed', 'legacy', TRUE,
  public.club_ranked_day_v3(NOW() - fixture.age),
  fixture.winner, fixture.one_score, fixture.two_score,
  fixture.player_one, NOW() - fixture.age,
  fixture.player_two, NOW() - fixture.age, NOW() - fixture.age,
  fixture.one_before, fixture.two_before, fixture.one_change, fixture.two_change,
  'normal', 0, NOW() - fixture.age - INTERVAL '5 minutes'
FROM fixture_matches fixture
ON CONFLICT (id) DO NOTHING;

-- Active rating ledger entries make history, ranks, and period leaderboards
-- behave exactly like real finalized matches.
INSERT INTO public.rating_events(
  match_id, player_id, event_kind, rating_before, rating_change,
  rating_after, revision, is_active, calculation, created_at
)
SELECT match.id, match.player_one_id, 'match_result',
  match.player_one_elo_before, match.player_one_elo_change,
  match.player_one_elo_before + match.player_one_elo_change,
  0, TRUE, jsonb_build_object('formula_version', 'fixture_v1'), match.confirmed_at
FROM public.matches match
WHERE match.id::TEXT LIKE 'd1000000-0000-4000-8000-%'
UNION ALL
SELECT match.id, match.player_two_id, 'match_result',
  match.player_two_elo_before, match.player_two_elo_change,
  match.player_two_elo_before + match.player_two_elo_change,
  0, TRUE, jsonb_build_object('formula_version', 'fixture_v1'), match.confirmed_at
FROM public.matches match
WHERE match.id::TEXT LIKE 'd1000000-0000-4000-8000-%'
ON CONFLICT DO NOTHING;

-- Challenge lifecycle and active-match cases -----------------------------

INSERT INTO public.challenges(id, challenger_id, opponent_id, status, created_at, expires_at)
VALUES
  ('d3000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000004', 'pending',   NOW() - INTERVAL '20 minutes', NOW() + INTERVAL '20 hours'),
  ('d3000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000005', 'pending',   NOW() - INTERVAL '10 minutes', NOW() + INTERVAL '22 hours'),
  ('d3000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000014', 'expired',   NOW() - INTERVAL '3 days',     NOW() - INTERVAL '2 days'),
  ('d3000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-000000000007', 'declined',  NOW() - INTERVAL '2 days',     NOW() - INTERVAL '1 day'),
  ('d3000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000004', 'accepted',  NOW() - INTERVAL '1 hour',     NOW() + INTERVAL '23 hours'),
  ('d3000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-000000000010', 'd0000000-0000-4000-8000-000000000007', 'accepted',  NOW() - INTERVAL '45 minutes',  NOW() + INTERVAL '23 hours'),
  ('d3000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000006', 'accepted',  NOW() - INTERVAL '30 minutes',  NOW() + INTERVAL '23 hours')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.matches(
  id, challenge_id, player_one_id, player_two_id, status, source, ranked,
  ranked_day, expires_at, created_at
)
VALUES
  ('d2000000-0000-4000-8000-000000000001', 'd3000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000004', 'ready', 'challenge', TRUE, public.club_ranked_day_v3(), NOW() + INTERVAL '23 hours', NOW() - INTERVAL '1 hour'),
  ('d2000000-0000-4000-8000-000000000002', 'd3000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-000000000010', 'd0000000-0000-4000-8000-000000000007', 'ready', 'challenge', TRUE, public.club_ranked_day_v3(), NOW() + INTERVAL '23 hours', NOW() - INTERVAL '45 minutes'),
  ('d2000000-0000-4000-8000-000000000003', 'd3000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000006', 'ready', 'challenge', TRUE, public.club_ranked_day_v3(), NOW() + INTERVAL '23 hours', NOW() - INTERVAL '30 minutes')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.match_cancellation_requests(
  id, match_id, requested_by, status, created_at
)
VALUES (
  'd4000000-0000-4000-8000-000000000001',
  'd2000000-0000-4000-8000-000000000003',
  'd0000000-0000-4000-8000-000000000004',
  'pending', NOW() - INTERVAL '5 minutes'
)
ON CONFLICT (id) DO NOTHING;

-- Dispute cases: opponent approval, admin review, and resolved history.
INSERT INTO public.disputes(
  id, match_id, opened_by, reason, requested_resolution,
  original_winner_id, original_player_one_score, original_player_two_score,
  proposed_winner_id, proposed_player_one_score, proposed_player_two_score,
  status, responded_by, response, responded_at, expires_at, escalated_at,
  resolved_by, resolution, admin_notes, created_at, resolved_at
)
VALUES
  (
    'd5000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000012',
    'd0000000-0000-4000-8000-000000000008',
    'incorrect_winner', 'correction',
    'd0000000-0000-4000-8000-000000000004', 11, 9,
    'd0000000-0000-4000-8000-000000000008', 9, 11,
    'pending', NULL, NULL, NULL, NOW() + INTERVAL '36 hours', NULL,
    NULL, NULL, NULL, NOW() - INTERVAL '12 hours', NULL
  ),
  (
    'd5000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000014',
    'd0000000-0000-4000-8000-000000000012',
    'match_never_happened', 'void',
    'd0000000-0000-4000-8000-000000000010', 11, 8,
    'd0000000-0000-4000-8000-000000000010', 11, 8,
    'admin_review', 'd0000000-0000-4000-8000-000000000010', 'declined', NOW() - INTERVAL '2 hours',
    NOW() + INTERVAL '40 hours', NOW() - INTERVAL '2 hours',
    NULL, NULL, NULL, NOW() - INTERVAL '6 hours', NULL
  ),
  (
    'd5000000-0000-4000-8000-000000000003',
    'd1000000-0000-4000-8000-000000000004',
    'd0000000-0000-4000-8000-000000000004',
    'incorrect_score', 'correction',
    'd0000000-0000-4000-8000-000000000005', 12, 10,
    'd0000000-0000-4000-8000-000000000005', 11, 9,
    'resolved', 'd0000000-0000-4000-8000-000000000005', 'approved', NOW() - INTERVAL '9 days',
    NOW() - INTERVAL '9 days', NULL,
    'd0000000-0000-4000-8000-000000000013', 'original', 'Fixture resolved dispute',
    NOW() - INTERVAL '10 days', NOW() - INTERVAL '9 days'
  )
ON CONFLICT (id) DO NOTHING;

-- Live queue --------------------------------------------------------------
-- The queue is intentionally replaced because it is transient by design.

DELETE FROM public.beaver_queue_games;
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET
  phase = 'idle', king_id = NULL, challenger_id = NULL,
  call_expires_at = NULL, game_id = NULL, game_started_at = NULL,
  updated_at = NOW()
WHERE id = 1;

INSERT INTO public.beaver_queue_members(
  user_id, display_name, status, queue_position, joined_at, updated_at
)
VALUES
  ('d0000000-0000-4000-8000-000000000004', 'Gold Gia',       'playing', 1, NOW() - INTERVAL '35 minutes', NOW()),
  ('d0000000-0000-4000-8000-000000000002', 'Bronze Ben',     'playing', 2, NOW() - INTERVAL '31 minutes', NOW()),
  ('d0000000-0000-4000-8000-000000000005', 'Platinum Priya', 'waiting', 3, NOW() - INTERVAL '25 minutes', NOW()),
  ('d0000000-0000-4000-8000-000000000003', 'Silver Sam',     'waiting', 4, NOW() - INTERVAL '20 minutes', NOW()),
  ('d0000000-0000-4000-8000-000000000001', 'Iron Iris',      'waiting', 5, NOW() - INTERVAL '15 minutes', NOW()),
  ('d0000000-0000-4000-8000-000000000010', 'Dual Dana',      'waiting', 6, NOW() - INTERVAL '10 minutes', NOW()),
  ('d0000000-0000-4000-8000-000000000012', 'Queue Quinn',    'waiting', 7, NOW() - INTERVAL '5 minutes', NOW()),
  ('d0000000-0000-4000-8000-000000000007', 'Legend Luna',    'waiting', 8, NOW() - INTERVAL '2 minutes', NOW());

SELECT setval(
  'public.beaver_queue_position_seq',
  GREATEST((SELECT MAX(queue_position) FROM public.beaver_queue_members), 1),
  TRUE
);

UPDATE public.beaver_queue_table SET
  phase = 'playing',
  king_id = 'd0000000-0000-4000-8000-000000000004',
  challenger_id = 'd0000000-0000-4000-8000-000000000002',
  call_expires_at = NULL,
  game_id = 'd6000000-0000-4000-8000-000000000099',
  game_started_at = NOW() - INTERVAL '4 minutes',
  updated_at = NOW()
WHERE id = 1;

INSERT INTO public.beaver_queue_games(
  id, king_id, challenger_id, king_name, challenger_name,
  king_score, challenger_score, winner_id, reported_by, completed_at
)
VALUES
  ('d6000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-000000000006', 'Legend Luna', 'Diamond Diego', 11, 8, 'd0000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-000000000007', NOW() - INTERVAL '45 minutes'),
  ('d6000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-000000000010', 'Legend Luna', 'Dual Dana', 9, 11, 'd0000000-0000-4000-8000-000000000010', 'd0000000-0000-4000-8000-000000000010', NOW() - INTERVAL '35 minutes'),
  ('d6000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000010', 'd0000000-0000-4000-8000-000000000004', 'Dual Dana', 'Gold Gia', 7, 11, 'd0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000004', NOW() - INTERVAL '20 minutes');

COMMIT;

-- Quick verification:
-- SELECT display_name, current_elo, public.rank_tier_name_v3(current_elo)
-- FROM public.profiles WHERE id::TEXT LIKE 'd0000000-0000-4000-8000-%'
-- ORDER BY current_elo DESC;
