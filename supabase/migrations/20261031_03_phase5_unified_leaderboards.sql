-- Pongo V3 Phase 5: New York weekly/monthly/all-time leaderboards and archives.
BEGIN;

CREATE INDEX IF NOT EXISTS idx_matches_ranked_confirmed_history_v3
  ON public.matches(confirmed_at, id)
  WHERE ranked AND status = 'confirmed';
CREATE INDEX IF NOT EXISTS idx_rating_events_active_match_player_v3
  ON public.rating_events(match_id, player_id)
  WHERE is_active AND match_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.club_leaderboard_period_start_v3(
  p_scope TEXT,
  p_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS DATE
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_scope = 'weekly' THEN
    RETURN date_trunc('week', p_at AT TIME ZONE 'America/New_York')::DATE;
  ELSIF p_scope = 'monthly' THEN
    RETURN date_trunc('month', p_at AT TIME ZONE 'America/New_York')::DATE;
  END IF;
  RAISE EXCEPTION 'Scope must be weekly or monthly';
END;
$$;

CREATE OR REPLACE FUNCTION public.get_leaderboard_v3(
  p_scope TEXT,
  p_period_start DATE DEFAULT NULL
)
RETURNS TABLE(
  placement BIGINT,
  player_id UUID,
  display_name TEXT,
  current_elo INTEGER,
  current_rank TEXT,
  is_provisional BOOLEAN,
  net_elo_change BIGINT,
  total_games BIGINT,
  wins BIGINT,
  losses BIGINT,
  win_rate NUMERIC,
  unique_opponents BIGINT,
  period_start DATE,
  period_end DATE
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_scope TEXT := lower(COALESCE(p_scope, ''));
  selected_start DATE;
  selected_end DATE;
  start_at TIMESTAMPTZ;
  end_at TIMESTAMPTZ;
BEGIN
  IF normalized_scope NOT IN ('weekly', 'monthly', 'all_time') THEN
    RAISE EXCEPTION 'Scope must be weekly, monthly, or all_time';
  END IF;

  IF normalized_scope = 'weekly' THEN
    selected_start := CASE
      WHEN p_period_start IS NULL THEN public.club_leaderboard_period_start_v3('weekly')
      ELSE date_trunc('week', p_period_start::TIMESTAMP)::DATE
    END;
    selected_end := selected_start + 7;
  ELSIF normalized_scope = 'monthly' THEN
    selected_start := CASE
      WHEN p_period_start IS NULL THEN public.club_leaderboard_period_start_v3('monthly')
      ELSE date_trunc('month', p_period_start::TIMESTAMP)::DATE
    END;
    selected_end := (selected_start + INTERVAL '1 month')::DATE;
  END IF;

  IF selected_start IS NOT NULL THEN
    start_at := selected_start::TIMESTAMP AT TIME ZONE 'America/New_York';
    end_at := selected_end::TIMESTAMP AT TIME ZONE 'America/New_York';
  END IF;

  RETURN QUERY
  WITH filtered_matches AS (
    SELECT m.id, m.player_one_id, m.player_two_id, m.winner_id
    FROM public.matches m
    WHERE m.ranked
      AND m.status = 'confirmed'
      AND (
        normalized_scope = 'all_time'
        OR (m.confirmed_at >= start_at AND m.confirmed_at < end_at)
      )
  ),
  player_matches AS (
    SELECT fm.id AS match_id, fm.player_one_id AS stats_player_id,
      fm.player_two_id AS opponent_id, (fm.winner_id = fm.player_one_id) AS won
    FROM filtered_matches fm
    UNION ALL
    SELECT fm.id, fm.player_two_id, fm.player_one_id,
      (fm.winner_id = fm.player_two_id)
    FROM filtered_matches fm
  ),
  period_stats AS (
    SELECT pm.stats_player_id,
      COUNT(*)::BIGINT AS games,
      COUNT(*) FILTER (WHERE pm.won)::BIGINT AS stat_wins,
      COUNT(*) FILTER (WHERE NOT pm.won)::BIGINT AS stat_losses,
      COUNT(DISTINCT pm.opponent_id)::BIGINT AS opponent_count
    FROM player_matches pm
    GROUP BY pm.stats_player_id
  ),
  period_rating AS (
    SELECT re.player_id AS rating_player_id,
      COALESCE(SUM(re.rating_change), 0)::BIGINT AS net_change
    FROM public.rating_events re
    JOIN filtered_matches fm ON fm.id = re.match_id
    WHERE re.is_active
    GROUP BY re.player_id
  ),
  eligible AS (
    SELECT p.id, p.display_name, p.current_elo, p.total_wins, p.total_losses,
      COALESCE(ps.games, 0)::BIGINT AS games,
      COALESCE(ps.stat_wins, 0)::BIGINT AS stat_wins,
      COALESCE(ps.stat_losses, 0)::BIGINT AS stat_losses,
      COALESCE(ps.opponent_count, 0)::BIGINT AS opponent_count,
      COALESCE(pr.net_change, 0)::BIGINT AS net_change
    FROM public.profiles p
    LEFT JOIN period_stats ps ON ps.stats_player_id = p.id
    LEFT JOIN period_rating pr ON pr.rating_player_id = p.id
    WHERE normalized_scope = 'all_time' OR ps.stats_player_id IS NOT NULL
  ),
  ranked AS (
    SELECT e.*,
      ROW_NUMBER() OVER (
        ORDER BY
          CASE WHEN normalized_scope = 'all_time' THEN e.current_elo END DESC NULLS LAST,
          CASE WHEN normalized_scope <> 'all_time' THEN e.net_change END DESC NULLS LAST,
          CASE WHEN normalized_scope <> 'all_time' THEN e.stat_wins END DESC NULLS LAST,
          e.current_elo DESC,
          e.display_name ASC,
          e.id ASC
      ) AS row_placement
    FROM eligible e
  )
  SELECT
    r.row_placement,
    r.id,
    r.display_name,
    r.current_elo,
    public.rank_tier_name_v3(r.current_elo),
    (r.total_wins + r.total_losses) < 5,
    r.net_change,
    r.games,
    r.stat_wins,
    r.stat_losses,
    CASE WHEN r.games = 0 THEN 0::NUMERIC
      ELSE ROUND((r.stat_wins::NUMERIC / r.games) * 100, 1) END,
    r.opponent_count,
    selected_start,
    CASE WHEN selected_end IS NULL THEN NULL ELSE selected_end - 1 END
  FROM ranked r
  ORDER BY r.row_placement;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_leaderboard_archive_v3(
  p_scope TEXT,
  p_limit INTEGER DEFAULT 12,
  p_as_of TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TABLE(
  scope TEXT,
  period_start DATE,
  period_end DATE,
  winner_id UUID,
  winner_name TEXT,
  winner_net_elo_change BIGINT,
  winner_current_elo INTEGER,
  winner_rank TEXT,
  winner_is_provisional BOOLEAN,
  total_players BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_scope TEXT := lower(COALESCE(p_scope, ''));
  current_start DATE;
BEGIN
  IF normalized_scope NOT IN ('weekly', 'monthly') THEN
    RAISE EXCEPTION 'Archive scope must be weekly or monthly';
  END IF;
  IF p_limit < 1 OR p_limit > 52 THEN
    RAISE EXCEPTION 'Archive limit must be between 1 and 52';
  END IF;

  current_start := public.club_leaderboard_period_start_v3(normalized_scope, p_as_of);

  RETURN QUERY
  WITH requested_periods AS (
    SELECT CASE
      WHEN normalized_scope = 'weekly' THEN current_start - (series.offset_number * 7)
      ELSE (current_start - make_interval(months => series.offset_number))::DATE
    END AS requested_start
    FROM generate_series(1, p_limit) AS series(offset_number)
  ),
  archived AS (
    SELECT rp.requested_start, lb.*
    FROM requested_periods rp
    CROSS JOIN LATERAL public.get_leaderboard_v3(normalized_scope, rp.requested_start) lb
  )
  SELECT
    normalized_scope,
    a.requested_start,
    MAX(a.period_end),
    (ARRAY_AGG(a.player_id) FILTER (WHERE a.placement = 1))[1],
    MAX(a.display_name) FILTER (WHERE a.placement = 1),
    MAX(a.net_elo_change) FILTER (WHERE a.placement = 1),
    MAX(a.current_elo) FILTER (WHERE a.placement = 1),
    MAX(a.current_rank) FILTER (WHERE a.placement = 1),
    BOOL_OR(a.is_provisional) FILTER (WHERE a.placement = 1),
    COUNT(*)::BIGINT
  FROM archived a
  GROUP BY a.requested_start
  HAVING COUNT(*) > 0
  ORDER BY a.requested_start DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.club_leaderboard_period_start_v3(TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.club_leaderboard_period_start_v3(TEXT, TIMESTAMPTZ)
  TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_leaderboard_v3(TEXT, DATE)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_leaderboard_v3(TEXT, DATE)
  TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_leaderboard_archive_v3(TEXT, INTEGER, TIMESTAMPTZ)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_leaderboard_archive_v3(TEXT, INTEGER, TIMESTAMPTZ)
  TO authenticated;

COMMIT;
