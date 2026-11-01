-- Run only against a disposable Supabase database after all migrations.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN, message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value, FALSE) THEN RAISE EXCEPTION 'Assertion failed: %', message; END IF;
END;
$$;

INSERT INTO auth.users(id, email, raw_user_meta_data, created_at, updated_at)
SELECT id, email, jsonb_build_object('display_name', name), NOW(), NOW()
FROM (VALUES
  ('f5000000-0000-0000-0000-000000000001'::UUID, 'phase5-a@example.test', 'Phase Five A'),
  ('f5000000-0000-0000-0000-000000000002'::UUID, 'phase5-b@example.test', 'Phase Five B'),
  ('f5000000-0000-0000-0000-000000000003'::UUID, 'phase5-c@example.test', 'Phase Five C')
) AS fixtures(id, email, name);

-- 03:59:59 UTC is Sunday 11:59:59 PM in New York; 04:00 UTC is Monday midnight.
INSERT INTO public.matches(
  id, player_one_id, player_two_id, status, source, ranked, ranked_day,
  winner_id, player_one_score, player_two_score, confirmed_at, finalized_at
) VALUES
  ('f5100000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000002', 'confirmed', 'legacy', TRUE, '2026-10-25', 'f5000000-0000-0000-0000-000000000001', 11, 9, '2026-10-26 03:59:59+00', '2026-10-26 03:59:59+00'),
  ('f5100000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000002', 'confirmed', 'legacy', TRUE, '2026-10-26', 'f5000000-0000-0000-0000-000000000001', 11, 9, '2026-10-26 04:00:00+00', '2026-10-26 04:00:00+00'),
  ('f5100000-0000-0000-0000-000000000003', 'f5000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000003', 'confirmed', 'legacy', TRUE, '2026-10-31', 'f5000000-0000-0000-0000-000000000003', 9, 11, '2026-11-01 03:59:59+00', '2026-11-01 03:59:59+00'),
  ('f5100000-0000-0000-0000-000000000004', 'f5000000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-000000000003', 'confirmed', 'legacy', TRUE, '2026-11-01', 'f5000000-0000-0000-0000-000000000002', 11, 9, '2026-11-01 04:00:00+00', '2026-11-01 04:00:00+00');

INSERT INTO public.rating_events(match_id, player_id, event_kind, rating_before, rating_change, rating_after)
VALUES
  ('f5100000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001', 'legacy_match', 1000, 8, 1008),
  ('f5100000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000002', 'legacy_match', 1000, -8, 992),
  ('f5100000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-000000000001', 'legacy_match', 1008, 20, 1028),
  ('f5100000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-000000000002', 'legacy_match', 992, -20, 972),
  ('f5100000-0000-0000-0000-000000000003', 'f5000000-0000-0000-0000-000000000001', 'legacy_match', 1028, -25, 1003),
  ('f5100000-0000-0000-0000-000000000003', 'f5000000-0000-0000-0000-000000000003', 'legacy_match', 1000, 25, 1025),
  ('f5100000-0000-0000-0000-000000000004', 'f5000000-0000-0000-0000-000000000002', 'legacy_match', 972, 10, 982),
  ('f5100000-0000-0000-0000-000000000004', 'f5000000-0000-0000-0000-000000000003', 'legacy_match', 1025, -10, 1015);

UPDATE public.profiles SET current_elo=1003, total_wins=2, total_losses=1 WHERE id='f5000000-0000-0000-0000-000000000001';
UPDATE public.profiles SET current_elo=982, total_wins=1, total_losses=2 WHERE id='f5000000-0000-0000-0000-000000000002';
UPDATE public.profiles SET current_elo=1015, total_wins=1, total_losses=1 WHERE id='f5000000-0000-0000-0000-000000000003';

SELECT pg_temp.assert_true(
  public.club_leaderboard_period_start_v3('weekly', '2026-10-26 03:59:59+00') = '2026-10-19'
  AND public.club_leaderboard_period_start_v3('weekly', '2026-10-26 04:00:00+00') = '2026-10-26',
  'weekly periods must change at Monday midnight in New York'
);

SELECT pg_temp.assert_true(
  (SELECT player_id='f5000000-0000-0000-0000-000000000003' AND net_elo_change=15
   FROM public.get_leaderboard_v3('weekly', '2026-10-26') WHERE placement=1),
  'weekly standings must rank by net ELO gained'
);
SELECT pg_temp.assert_true(
  (SELECT total_games=2 AND wins=1 AND losses=1 AND win_rate=50.0 AND unique_opponents=2
   FROM public.get_leaderboard_v3('weekly', '2026-10-26')
   WHERE player_id='f5000000-0000-0000-0000-000000000001'),
  'period standings must include games, record, win rate, and unique opponents'
);

SELECT pg_temp.assert_true(
  (SELECT player_id='f5000000-0000-0000-0000-000000000003' AND net_elo_change=25
   FROM public.get_leaderboard_v3('monthly', '2026-10-01') WHERE placement=1)
  AND
  (SELECT player_id='f5000000-0000-0000-0000-000000000002' AND net_elo_change=10
   FROM public.get_leaderboard_v3('monthly', '2026-11-01') WHERE placement=1),
  'monthly standings must use New York calendar-month boundaries'
);

SELECT pg_temp.assert_true(
  (SELECT player_id='f5000000-0000-0000-0000-000000000003'
   FROM public.get_leaderboard_v3('all_time') WHERE placement=1),
  'all-time standings must rank by permanent current ELO'
);

SELECT pg_temp.assert_true(
  EXISTS(
    SELECT 1 FROM public.get_leaderboard_archive_v3('weekly', 3, '2026-11-15 12:00:00+00')
    WHERE period_start='2026-10-26' AND winner_id='f5000000-0000-0000-0000-000000000003'
  )
  AND EXISTS(
    SELECT 1 FROM public.get_leaderboard_archive_v3('monthly', 2, '2026-12-15 12:00:00+00')
    WHERE period_start='2026-10-01' AND winner_id='f5000000-0000-0000-0000-000000000003'
  ),
  'completed weekly and monthly winners must remain available in archives'
);

-- Inactivating a superseded event immediately corrects the original period.
UPDATE public.rating_events SET is_active=FALSE
WHERE match_id='f5100000-0000-0000-0000-000000000003'
  AND player_id='f5000000-0000-0000-0000-000000000003';
SELECT pg_temp.assert_true(
  (SELECT net_elo_change=-10
   FROM public.get_leaderboard_v3('weekly', '2026-10-26')
   WHERE player_id='f5000000-0000-0000-0000-000000000003'),
  'superseded rating events must be removed from the original historical period'
);

ROLLBACK;
