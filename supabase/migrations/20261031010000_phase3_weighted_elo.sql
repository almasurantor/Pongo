-- Pongo V3 Phase 3: K=40 weighted, exactly zero-sum ELO.
BEGIN;

ALTER TABLE public.ranking_config
  ADD COLUMN IF NOT EXISTS score_margin_cap NUMERIC(5,4) NOT NULL DEFAULT 0.1000
    CHECK (score_margin_cap >= 0 AND score_margin_cap <= 0.2500),
  ADD COLUMN IF NOT EXISTS elo_formula_version TEXT NOT NULL DEFAULT 'weighted_elo_v1';

UPDATE public.ranking_config
SET k_factor = 40,
    score_margin_cap = 0.1000,
    elo_formula_version = 'weighted_elo_v1',
    updated_at = NOW()
WHERE id;

ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS rating_calculation JSONB;
ALTER TABLE public.rating_events ADD COLUMN IF NOT EXISTS calculation JSONB;

CREATE OR REPLACE FUNCTION public.calculate_weighted_elo_v3(
  p_winner_rating INTEGER,
  p_loser_rating INTEGER,
  p_winner_score INTEGER,
  p_loser_score INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  cfg public.ranking_config;
  winner_expected NUMERIC;
  base_delta_raw NUMERIC;
  base_delta INTEGER;
  score_margin INTEGER;
  margin_progress NUMERIC;
  margin_multiplier NUMERIC;
  final_delta INTEGER;
BEGIN
  IF p_winner_rating IS NULL OR p_loser_rating IS NULL
     OR p_winner_score IS NULL OR p_loser_score IS NULL
     OR p_winner_score <= p_loser_score
     OR NOT public.is_valid_match_score_v2(p_winner_score, p_loser_score) THEN
    RAISE EXCEPTION 'Invalid weighted ELO input';
  END IF;

  SELECT * INTO cfg FROM public.ranking_config WHERE id;
  winner_expected := 1.0 / (1.0 + POWER(10.0, (p_loser_rating - p_winner_rating) / 400.0));
  base_delta_raw := cfg.k_factor * (1.0 - winner_expected);
  base_delta := ROUND(base_delta_raw);
  score_margin := p_winner_score - p_loser_score;

  -- A two-point win receives standard ELO. The bonus grows linearly until an
  -- 11-point margin, where it reaches the configured 10% cap.
  margin_progress := LEAST(1.0, GREATEST(0.0, (score_margin - 2) / 9.0));
  margin_multiplier := 1.0 + (cfg.score_margin_cap * margin_progress);
  final_delta := ROUND(base_delta_raw * margin_multiplier);

  RETURN jsonb_build_object(
    'formula_version', cfg.elo_formula_version,
    'k_factor', cfg.k_factor,
    'score_margin_cap', cfg.score_margin_cap,
    'winner_expected', winner_expected,
    'base_delta_raw', base_delta_raw,
    'base_delta', base_delta,
    'score_margin', score_margin,
    'margin_multiplier', margin_multiplier,
    'margin_bonus', final_delta - base_delta,
    'final_delta', final_delta
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_match_rating_preview_v3(p_match UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m public.matches;
  p1 public.profiles;
  p2 public.profiles;
  p1_win JSONB;
  p2_win JSONB;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id = p_match;
  IF NOT FOUND OR auth.uid() NOT IN (m.player_one_id, m.player_two_id) THEN
    RAISE EXCEPTION 'Match not found';
  END IF;
  SELECT * INTO p1 FROM public.profiles WHERE id = m.player_one_id;
  SELECT * INTO p2 FROM public.profiles WHERE id = m.player_two_id;
  p1_win := public.calculate_weighted_elo_v3(p1.current_elo, p2.current_elo, 11, 9);
  p2_win := public.calculate_weighted_elo_v3(p2.current_elo, p1.current_elo, 11, 9);

  RETURN jsonb_build_object(
    'player_one_rating', p1.current_elo,
    'player_two_rating', p2.current_elo,
    'player_one_win_change', (p1_win->>'final_delta')::INTEGER,
    'player_one_loss_change', -((p2_win->>'final_delta')::INTEGER),
    'player_two_win_change', (p2_win->>'final_delta')::INTEGER,
    'player_two_loss_change', -((p1_win->>'final_delta')::INTEGER),
    'player_one_expected', 1.0 / (1.0 + POWER(10.0, (p2.current_elo - p1.current_elo) / 400.0)),
    'score_margin_cap', (SELECT score_margin_cap FROM public.ranking_config WHERE id)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_match_v2(p_match_id UUID, p_actor UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m public.matches;
  winner public.profiles;
  loser public.profiles;
  p1_delta INTEGER;
  p2_delta INTEGER;
  delta INTEGER;
  week DATE;
  v_event UUID;
  calculation JSONB;
  winner_before INTEGER;
  loser_before INTEGER;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF m.status = 'confirmed' THEN
    RETURN jsonb_build_object(
      'match_id', m.id,
      'already_finalized', TRUE,
      'player_one_change', m.player_one_elo_change,
      'player_two_change', m.player_two_elo_change,
      'player_one_new', m.player_one_elo_before + m.player_one_elo_change,
      'player_two_new', m.player_two_elo_before + m.player_two_elo_change,
      'rating_calculation', m.rating_calculation
    );
  END IF;
  IF m.status <> 'result_reported' THEN
    RAISE EXCEPTION 'Match is not eligible for finalization';
  END IF;
  IF m.winner_id NOT IN (m.player_one_id, m.player_two_id)
     OR NOT public.is_valid_match_score_v2(m.player_one_score, m.player_two_score) THEN
    RAISE EXCEPTION 'Invalid final result';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    LEAST(m.player_one_id::TEXT, m.player_two_id::TEXT) || ':' ||
    GREATEST(m.player_one_id::TEXT, m.player_two_id::TEXT) || ':' ||
    COALESCE(m.ranked_day::TEXT, public.club_ranked_day_v3()::TEXT), 0
  ));
  PERFORM id FROM public.profiles
    WHERE id IN (m.player_one_id, m.player_two_id)
    ORDER BY id FOR UPDATE;

  SELECT * INTO winner FROM public.profiles WHERE id = m.winner_id;
  SELECT * INTO loser FROM public.profiles
    WHERE id = CASE WHEN m.winner_id = m.player_one_id THEN m.player_two_id ELSE m.player_one_id END;
  winner_before := winner.current_elo;
  loser_before := loser.current_elo;
  calculation := public.calculate_weighted_elo_v3(
    winner.current_elo,
    loser.current_elo,
    GREATEST(m.player_one_score, m.player_two_score),
    LEAST(m.player_one_score, m.player_two_score)
  ) || jsonb_build_object(
    'winner_id', winner.id,
    'loser_id', loser.id,
    'winner_rating_before', winner.current_elo,
    'loser_rating_before', loser.current_elo
  );
  delta := (calculation->>'final_delta')::INTEGER;
  p1_delta := CASE WHEN m.player_one_id = winner.id THEN delta ELSE -delta END;
  p2_delta := -p1_delta;
  week := (date_trunc('week', NOW() AT TIME ZONE 'America/New_York'))::DATE;

  UPDATE public.profiles SET
    current_elo = current_elo + p1_delta,
    highest_elo = GREATEST(highest_elo, current_elo + p1_delta),
    total_wins = total_wins + CASE WHEN id = winner.id THEN 1 ELSE 0 END,
    total_losses = total_losses + CASE WHEN id = loser.id THEN 1 ELSE 0 END,
    weekly_wins = weekly_wins + CASE WHEN id = winner.id THEN 1 ELSE 0 END,
    weekly_losses = weekly_losses + CASE WHEN id = loser.id THEN 1 ELSE 0 END,
    current_streak = CASE WHEN id = winner.id THEN GREATEST(current_streak, 0) + 1 ELSE LEAST(current_streak, 0) - 1 END,
    longest_streak = CASE WHEN id = winner.id THEN GREATEST(longest_streak, GREATEST(current_streak, 0) + 1) ELSE longest_streak END,
    updated_at = NOW()
  WHERE id = m.player_one_id;

  UPDATE public.profiles SET
    current_elo = current_elo + p2_delta,
    highest_elo = GREATEST(highest_elo, current_elo + p2_delta),
    total_wins = total_wins + CASE WHEN id = winner.id THEN 1 ELSE 0 END,
    total_losses = total_losses + CASE WHEN id = loser.id THEN 1 ELSE 0 END,
    weekly_wins = weekly_wins + CASE WHEN id = winner.id THEN 1 ELSE 0 END,
    weekly_losses = weekly_losses + CASE WHEN id = loser.id THEN 1 ELSE 0 END,
    current_streak = CASE WHEN id = winner.id THEN GREATEST(current_streak, 0) + 1 ELSE LEAST(current_streak, 0) - 1 END,
    longest_streak = CASE WHEN id = winner.id THEN GREATEST(longest_streak, GREATEST(current_streak, 0) + 1) ELSE longest_streak END,
    updated_at = NOW()
  WHERE id = m.player_two_id;

  INSERT INTO public.rating_events(
    match_id, player_id, event_kind, rating_before, rating_change,
    rating_after, revision, calculation
  ) VALUES (
    m.id, m.player_one_id, 'match_result',
    CASE WHEN m.player_one_id = winner.id THEN winner_before ELSE loser_before END,
    p1_delta,
    CASE WHEN m.player_one_id = winner.id THEN winner_before ELSE loser_before END + p1_delta,
    m.revision, calculation
  );
  INSERT INTO public.rating_events(
    match_id, player_id, event_kind, rating_before, rating_change,
    rating_after, revision, calculation
  ) VALUES (
    m.id, m.player_two_id, 'match_result',
    CASE WHEN m.player_two_id = winner.id THEN winner_before ELSE loser_before END,
    p2_delta,
    CASE WHEN m.player_two_id = winner.id THEN winner_before ELSE loser_before END + p2_delta,
    m.revision, calculation
  );

  INSERT INTO public.weekly_player_stats(player_id, week_start, wins, losses)
  VALUES(m.player_one_id, week,
    CASE WHEN m.player_one_id = winner.id THEN 1 ELSE 0 END,
    CASE WHEN m.player_one_id = loser.id THEN 1 ELSE 0 END)
  ON CONFLICT(player_id, week_start) DO UPDATE SET
    wins = weekly_player_stats.wins + EXCLUDED.wins,
    losses = weekly_player_stats.losses + EXCLUDED.losses,
    updated_at = NOW();
  INSERT INTO public.weekly_player_stats(player_id, week_start, wins, losses)
  VALUES(m.player_two_id, week,
    CASE WHEN m.player_two_id = winner.id THEN 1 ELSE 0 END,
    CASE WHEN m.player_two_id = loser.id THEN 1 ELSE 0 END)
  ON CONFLICT(player_id, week_start) DO UPDATE SET
    wins = weekly_player_stats.wins + EXCLUDED.wins,
    losses = weekly_player_stats.losses + EXCLUDED.losses,
    updated_at = NOW();

  IF m.season_id IS NOT NULL THEN
    INSERT INTO public.player_season_stats(season_id, player_id, starting_elo, high_elo, wins, losses)
    VALUES(m.season_id, m.player_one_id,
      CASE WHEN m.player_one_id = winner.id THEN winner_before ELSE loser_before END,
      CASE WHEN m.player_one_id = winner.id THEN winner_before + p1_delta ELSE loser_before + p1_delta END,
      CASE WHEN m.player_one_id = winner.id THEN 1 ELSE 0 END,
      CASE WHEN m.player_one_id = loser.id THEN 1 ELSE 0 END)
    ON CONFLICT(season_id, player_id) DO UPDATE SET
      high_elo = GREATEST(player_season_stats.high_elo, EXCLUDED.high_elo),
      wins = player_season_stats.wins + EXCLUDED.wins,
      losses = player_season_stats.losses + EXCLUDED.losses;
    INSERT INTO public.player_season_stats(season_id, player_id, starting_elo, high_elo, wins, losses)
    VALUES(m.season_id, m.player_two_id,
      CASE WHEN m.player_two_id = winner.id THEN winner_before ELSE loser_before END,
      CASE WHEN m.player_two_id = winner.id THEN winner_before + p2_delta ELSE loser_before + p2_delta END,
      CASE WHEN m.player_two_id = winner.id THEN 1 ELSE 0 END,
      CASE WHEN m.player_two_id = loser.id THEN 1 ELSE 0 END)
    ON CONFLICT(season_id, player_id) DO UPDATE SET
      high_elo = GREATEST(player_season_stats.high_elo, EXCLUDED.high_elo),
      wins = player_season_stats.wins + EXCLUDED.wins,
      losses = player_season_stats.losses + EXCLUDED.losses;
  END IF;

  UPDATE public.matches SET
    status = 'confirmed',
    confirmed_by = p_actor,
    confirmed_at = NOW(),
    finalized_at = NOW(),
    expires_at = NULL,
    player_one_elo_before = CASE WHEN m.player_one_id = winner.id THEN winner_before ELSE loser_before END,
    player_two_elo_before = CASE WHEN m.player_two_id = winner.id THEN winner_before ELSE loser_before END,
    player_one_elo_change = p1_delta,
    player_two_elo_change = p2_delta,
    rating_calculation = calculation
  WHERE id = m.id;

  IF m.challenge_id IS NOT NULL THEN
    UPDATE public.challenges SET status = 'completed' WHERE id = m.challenge_id;
  END IF;
  v_event := public.emit_domain_event(
    'match.confirmed', p_actor, m.id, m.challenge_id,
    jsonb_build_object(
      'winner_id', winner.id,
      'player_one_change', p1_delta,
      'player_two_change', p2_delta,
      'rating_calculation', calculation
    ), ARRAY[m.player_one_id, m.player_two_id]
  );
  IF (SELECT COUNT(*) FROM public.matches x
      WHERE x.status = 'confirmed' AND x.ranked
        AND x.confirmed_at > NOW() - INTERVAL '24 hours'
        AND (x.player_one_id IN (m.player_one_id, m.player_two_id)
          OR x.player_two_id IN (m.player_one_id, m.player_two_id))) >= 15 THEN
    INSERT INTO public.integrity_flags(player_id, match_id, flag_type, details)
    VALUES(p_actor, m.id, 'high_match_volume', jsonb_build_object('window_hours', 24));
  END IF;

  RETURN jsonb_build_object(
    'match_id', m.id,
    'already_finalized', FALSE,
    'player_one_change', p1_delta,
    'player_two_change', p2_delta,
    'player_one_new', CASE WHEN m.player_one_id = winner.id THEN winner_before ELSE loser_before END + p1_delta,
    'player_two_new', CASE WHEN m.player_two_id = winner.id THEN winner_before ELSE loser_before END + p2_delta,
    'rating_calculation', calculation
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.calculate_weighted_elo_v3(INTEGER, INTEGER, INTEGER, INTEGER)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_match_rating_preview_v3(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_match_rating_preview_v3(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.finalize_match_v2(UUID, UUID) FROM PUBLIC, anon, authenticated;

COMMIT;
