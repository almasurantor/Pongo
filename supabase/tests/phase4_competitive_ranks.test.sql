-- Run only against a disposable Supabase database after all migrations.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN, message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value, FALSE) THEN RAISE EXCEPTION 'Assertion failed: %', message; END IF;
END;
$$;

SELECT pg_temp.assert_true(
  (SELECT COUNT(*) = 7 FROM public.competitive_rank_tiers),
  'all seven competitive tiers must be configured'
);

SELECT pg_temp.assert_true(
  public.rank_tier_name_v3(649) = 'Iron'
  AND public.rank_tier_name_v3(650) = 'Bronze'
  AND public.rank_tier_name_v3(800) = 'Silver'
  AND public.rank_tier_name_v3(950) = 'Gold'
  AND public.rank_tier_name_v3(1100) = 'Platinum'
  AND public.rank_tier_name_v3(1250) = 'Diamond'
  AND public.rank_tier_name_v3(1400) = 'Legend',
  'rank boundaries must be inclusive at their configured floors'
);

SELECT pg_temp.assert_true(
  public.get_rank_progress_v3(1025, 2) @> jsonb_build_object(
    'tier', 'Gold',
    'next_tier', 'Platinum',
    'points_to_next', 75,
    'progress_percent', 50,
    'is_provisional', FALSE,
    'placement_games_remaining', 0
  ),
  'rank progress must not use provisional placement games'
);

SELECT pg_temp.assert_true(
  public.get_rank_progress_v3(1400, 5) @> jsonb_build_object(
    'tier', 'Legend',
    'is_top_tier', TRUE,
    'progress_percent', 100,
    'is_provisional', FALSE
  ),
  'Legend must be the official top tier'
);

INSERT INTO auth.users(id, email, raw_user_meta_data, created_at, updated_at)
VALUES(
  'f4000000-0000-0000-0000-000000000001',
  'phase4-ranks@example.test',
  jsonb_build_object('display_name', 'Phase Four Ranks'),
  NOW(), NOW()
);

INSERT INTO public.rating_events(
  player_id, event_kind, rating_before, rating_change, rating_after
) VALUES (
  'f4000000-0000-0000-0000-000000000001',
  'migration_adjustment', 940, 20, 960
);

SELECT pg_temp.assert_true(
  (SELECT rank_before = 'Silver' AND rank_after = 'Gold'
   FROM public.rating_events
   WHERE player_id = 'f4000000-0000-0000-0000-000000000001'),
  'rating events must snapshot promotion and demotion boundaries'
);

ROLLBACK;
