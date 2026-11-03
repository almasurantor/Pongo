-- BeaverSmash V4: 500 starting ELO and recalibrated competitive tiers.
-- Existing player ratings are deliberately preserved.
BEGIN;

UPDATE public.ranking_config
SET starting_elo = 500,
    k_factor = 40,
    updated_at = NOW()
WHERE id;

ALTER TABLE public.profiles
  ALTER COLUMN current_elo SET DEFAULT 500,
  ALTER COLUMN highest_elo SET DEFAULT 500;

INSERT INTO public.competitive_rank_tiers(rank_name, tier_order, min_elo)
VALUES
  ('Iron', 1, NULL),
  ('Bronze', 2, 650),
  ('Silver', 3, 800),
  ('Gold', 4, 950),
  ('Platinum', 5, 1100),
  ('Diamond', 6, 1250),
  ('Legend', 7, 1400)
ON CONFLICT (rank_name) DO UPDATE SET
  tier_order = EXCLUDED.tier_order,
  min_elo = EXCLUDED.min_elo,
  updated_at = NOW();

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
  ORDER BY tier.tier_order DESC LIMIT 1;

  SELECT * INTO next_tier
  FROM public.competitive_rank_tiers tier
  WHERE tier.tier_order = current_tier.tier_order + 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'tier', current_tier.rank_name, 'min_elo', current_tier.min_elo,
      'next_tier', NULL, 'next_tier_elo', NULL, 'points_to_next', 0,
      'progress_percent', 100, 'is_top_tier', TRUE,
      'is_provisional', games_played < 5,
      'placement_games_remaining', GREATEST(5 - games_played, 0)
    );
  END IF;

  SELECT starting_elo INTO progress_floor FROM public.ranking_config WHERE id;
  progress_floor := COALESCE(current_tier.min_elo, progress_floor, 500);
  progress_percent := ROUND(
    LEAST(1.0, GREATEST(0.0,
      (p_elo - progress_floor)::NUMERIC / NULLIF(next_tier.min_elo - progress_floor, 0)
    )) * 100
  );

  RETURN jsonb_build_object(
    'tier', current_tier.rank_name, 'min_elo', current_tier.min_elo,
    'next_tier', next_tier.rank_name, 'next_tier_elo', next_tier.min_elo,
    'points_to_next', GREATEST(next_tier.min_elo - p_elo, 0),
    'progress_percent', progress_percent, 'is_top_tier', FALSE,
    'is_provisional', games_played < 5,
    'placement_games_remaining', GREATEST(5 - games_played, 0)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles(
    id, display_name, current_elo, highest_elo, total_wins, total_losses,
    weekly_wins, weekly_losses, current_streak, longest_streak
  ) VALUES(
    NEW.id,
    COALESCE(
      NULLIF(NEW.raw_user_meta_data->>'display_name', ''),
      NULLIF(NEW.raw_user_meta_data->>'full_name', ''),
      SPLIT_PART(NEW.email, '@', 1), 'Player'
    ),
    500, 500, 0, 0, 0, 0, 0, 0
  ) ON CONFLICT(id) DO NOTHING;

  INSERT INTO public.player_integrity(player_id)
  VALUES(NEW.id) ON CONFLICT(player_id) DO NOTHING;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_rank_progress_v3(INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_rank_progress_v3(INTEGER, INTEGER) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
