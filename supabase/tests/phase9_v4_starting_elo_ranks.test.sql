-- Run only against a disposable Supabase database after all migrations.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN, message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value, FALSE) THEN RAISE EXCEPTION 'Assertion failed: %', message; END IF;
END;
$$;

SELECT pg_temp.assert_true(
  (SELECT starting_elo = 500 AND k_factor = 40 FROM public.ranking_config WHERE id),
  'new players must use 500 starting ELO while weighted ELO keeps K=40'
);

SELECT pg_temp.assert_true(
  public.rank_tier_name_v3(500) = 'Iron'
  AND public.rank_tier_name_v3(649) = 'Iron'
  AND public.rank_tier_name_v3(650) = 'Bronze'
  AND public.rank_tier_name_v3(800) = 'Silver'
  AND public.rank_tier_name_v3(950) = 'Gold'
  AND public.rank_tier_name_v3(1100) = 'Platinum'
  AND public.rank_tier_name_v3(1250) = 'Diamond'
  AND public.rank_tier_name_v3(1400) = 'Legend',
  'V4 competitive tier floors must be inclusive'
);

SELECT pg_temp.assert_true(
  public.get_rank_progress_v3(500, 0) @> jsonb_build_object(
    'tier', 'Unranked', 'next_tier', NULL, 'progress_percent', 0,
    'is_provisional', FALSE, 'placement_games_remaining', 0
  ),
  'a new player must remain Unranked until one completed ranked match'
);

INSERT INTO auth.users(id, email, raw_user_meta_data, created_at, updated_at)
VALUES(
  'f9000000-0000-0000-0000-000000000001',
  'phase9-v4@example.test',
  jsonb_build_object('display_name', 'Phase Nine V4'),
  NOW(), NOW()
);

SELECT pg_temp.assert_true(
  (SELECT current_elo = 500 AND highest_elo = 500
   FROM public.profiles WHERE id = 'f9000000-0000-0000-0000-000000000001'),
  'the auth signup trigger must create a 500-ELO profile'
);

ROLLBACK;
