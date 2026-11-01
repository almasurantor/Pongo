-- Beaver Smash V3 Phase 4: automatic competitive tiers and immutable rank snapshots.
BEGIN;

CREATE TABLE IF NOT EXISTS public.competitive_rank_tiers (
  rank_name TEXT PRIMARY KEY CHECK (rank_name IN (
    'Iron', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Legend'
  )),
  tier_order SMALLINT NOT NULL UNIQUE CHECK (tier_order BETWEEN 1 AND 7),
  min_elo INTEGER UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT iron_has_no_floor CHECK (
    (rank_name = 'Iron' AND min_elo IS NULL)
    OR (rank_name <> 'Iron' AND min_elo IS NOT NULL)
  )
);

INSERT INTO public.competitive_rank_tiers(rank_name, tier_order, min_elo)
VALUES
  ('Iron', 1, NULL),
  ('Bronze', 2, 850),
  ('Silver', 3, 950),
  ('Gold', 4, 1050),
  ('Platinum', 5, 1150),
  ('Diamond', 6, 1250),
  ('Legend', 7, 1400)
ON CONFLICT (rank_name) DO UPDATE SET
  tier_order = EXCLUDED.tier_order,
  min_elo = EXCLUDED.min_elo,
  updated_at = NOW();

ALTER TABLE public.competitive_rank_tiers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Competitive ranks are readable" ON public.competitive_rank_tiers;
CREATE POLICY "Competitive ranks are readable"
  ON public.competitive_rank_tiers FOR SELECT TO authenticated USING (TRUE);

REVOKE ALL ON TABLE public.competitive_rank_tiers FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.competitive_rank_tiers FROM authenticated;
GRANT SELECT ON TABLE public.competitive_rank_tiers TO authenticated;

CREATE OR REPLACE FUNCTION public.rank_tier_name_v3(p_elo INTEGER)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT tier.rank_name
  FROM public.competitive_rank_tiers tier
  WHERE tier.min_elo IS NULL OR p_elo >= tier.min_elo
  ORDER BY tier.tier_order DESC
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.get_rank_progress_v3(p_elo INTEGER, p_total_games INTEGER DEFAULT 0)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_tier public.competitive_rank_tiers;
  next_tier public.competitive_rank_tiers;
  progress_floor INTEGER;
  progress_percent INTEGER;
  games_played INTEGER := GREATEST(COALESCE(p_total_games, 0), 0);
BEGIN
  IF p_elo IS NULL THEN RAISE EXCEPTION 'ELO is required'; END IF;

  SELECT * INTO current_tier
  FROM public.competitive_rank_tiers tier
  WHERE tier.min_elo IS NULL OR p_elo >= tier.min_elo
  ORDER BY tier.tier_order DESC
  LIMIT 1;

  SELECT * INTO next_tier
  FROM public.competitive_rank_tiers tier
  WHERE tier.tier_order = current_tier.tier_order + 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'tier', current_tier.rank_name,
      'min_elo', current_tier.min_elo,
      'next_tier', NULL,
      'next_tier_elo', NULL,
      'points_to_next', 0,
      'progress_percent', 100,
      'is_top_tier', TRUE,
      'is_provisional', games_played < 5,
      'placement_games_remaining', GREATEST(5 - games_played, 0)
    );
  END IF;

  progress_floor := COALESCE(current_tier.min_elo, next_tier.min_elo - 100);
  progress_percent := ROUND(
    LEAST(1.0, GREATEST(0.0,
      (p_elo - progress_floor)::NUMERIC / (next_tier.min_elo - progress_floor)
    )) * 100
  );

  RETURN jsonb_build_object(
    'tier', current_tier.rank_name,
    'min_elo', current_tier.min_elo,
    'next_tier', next_tier.rank_name,
    'next_tier_elo', next_tier.min_elo,
    'points_to_next', GREATEST(next_tier.min_elo - p_elo, 0),
    'progress_percent', progress_percent,
    'is_top_tier', FALSE,
    'is_provisional', games_played < 5,
    'placement_games_remaining', GREATEST(5 - games_played, 0)
  );
END;
$$;

ALTER TABLE public.rating_events
  ADD COLUMN IF NOT EXISTS rank_before TEXT,
  ADD COLUMN IF NOT EXISTS rank_after TEXT;

CREATE OR REPLACE FUNCTION public.snapshot_rating_event_ranks_v3()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.rank_before := public.rank_tier_name_v3(NEW.rating_before);
  NEW.rank_after := public.rank_tier_name_v3(NEW.rating_after);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS snapshot_rating_event_ranks_v3 ON public.rating_events;
CREATE TRIGGER snapshot_rating_event_ranks_v3
BEFORE INSERT OR UPDATE OF rating_before, rating_after ON public.rating_events
FOR EACH ROW EXECUTE FUNCTION public.snapshot_rating_event_ranks_v3();

-- Backfill only rank labels. Historical ELO values and events remain unchanged.
UPDATE public.rating_events
SET rank_before = public.rank_tier_name_v3(rating_before),
    rank_after = public.rank_tier_name_v3(rating_after)
WHERE rank_before IS NULL OR rank_after IS NULL;

REVOKE EXECUTE ON FUNCTION public.rank_tier_name_v3(INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rank_tier_name_v3(INTEGER) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_rank_progress_v3(INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_rank_progress_v3(INTEGER, INTEGER) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.snapshot_rating_event_ranks_v3() FROM PUBLIC, anon, authenticated;

COMMIT;
