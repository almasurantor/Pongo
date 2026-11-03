-- Coordinated release: one-match ranking, queue liveness, and hot-path indexes.
BEGIN;

UPDATE public.ranking_config
SET starting_elo=500,k_factor=40,updated_at=NOW()
WHERE id;

ALTER TABLE public.profiles
  ALTER COLUMN current_elo SET DEFAULT 500,
  ALTER COLUMN highest_elo SET DEFAULT 500;

CREATE OR REPLACE FUNCTION public.get_rank_progress_v3(p_elo INTEGER,p_total_games INTEGER DEFAULT 0)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  current_tier public.competitive_rank_tiers;
  next_tier public.competitive_rank_tiers;
  progress_floor INTEGER;
  progress_percent INTEGER;
  games_played INTEGER:=GREATEST(COALESCE(p_total_games,0),0);
BEGIN
  IF p_elo IS NULL THEN RAISE EXCEPTION 'ELO is required'; END IF;
  IF games_played=0 THEN
    RETURN jsonb_build_object(
      'tier','Unranked','min_elo',NULL,'next_tier',NULL,'next_tier_elo',NULL,
      'points_to_next',0,'progress_percent',0,'is_top_tier',FALSE,
      'is_provisional',FALSE,'placement_games_remaining',0
    );
  END IF;

  SELECT * INTO current_tier FROM public.competitive_rank_tiers tier
  WHERE tier.min_elo IS NULL OR p_elo>=tier.min_elo
  ORDER BY tier.tier_order DESC LIMIT 1;
  SELECT * INTO next_tier FROM public.competitive_rank_tiers tier
  WHERE tier.tier_order=current_tier.tier_order+1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'tier',current_tier.rank_name,'min_elo',current_tier.min_elo,
      'next_tier',NULL,'next_tier_elo',NULL,'points_to_next',0,
      'progress_percent',100,'is_top_tier',TRUE,
      'is_provisional',FALSE,'placement_games_remaining',0
    );
  END IF;

  SELECT starting_elo INTO progress_floor FROM public.ranking_config WHERE id;
  progress_floor:=COALESCE(current_tier.min_elo,progress_floor,500);
  progress_percent:=ROUND(LEAST(1.0,GREATEST(0.0,
    (p_elo-progress_floor)::NUMERIC/NULLIF(next_tier.min_elo-progress_floor,0)
  ))*100);
  RETURN jsonb_build_object(
    'tier',current_tier.rank_name,'min_elo',current_tier.min_elo,
    'next_tier',next_tier.rank_name,'next_tier_elo',next_tier.min_elo,
    'points_to_next',GREATEST(next_tier.min_elo-p_elo,0),
    'progress_percent',progress_percent,'is_top_tier',FALSE,
    'is_provisional',FALSE,'placement_games_remaining',0
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_leaderboard_v3(p_scope TEXT,p_period_start DATE DEFAULT NULL)
RETURNS TABLE(
  placement BIGINT,player_id UUID,display_name TEXT,current_elo INTEGER,
  current_rank TEXT,is_provisional BOOLEAN,net_elo_change BIGINT,total_games BIGINT,
  wins BIGINT,losses BIGINT,win_rate NUMERIC,unique_opponents BIGINT,
  period_start DATE,period_end DATE
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  normalized_scope TEXT:=LOWER(COALESCE(p_scope,''));
  selected_start DATE;
  selected_end DATE;
  start_at TIMESTAMPTZ;
  end_at TIMESTAMPTZ;
BEGIN
  IF normalized_scope NOT IN ('weekly','monthly','all_time') THEN
    RAISE EXCEPTION 'Scope must be weekly, monthly, or all_time';
  END IF;
  IF normalized_scope='weekly' THEN
    selected_start:=CASE WHEN p_period_start IS NULL
      THEN public.club_leaderboard_period_start_v3('weekly')
      ELSE date_trunc('week',p_period_start::TIMESTAMP)::DATE END;
    selected_end:=selected_start+7;
  ELSIF normalized_scope='monthly' THEN
    selected_start:=CASE WHEN p_period_start IS NULL
      THEN public.club_leaderboard_period_start_v3('monthly')
      ELSE date_trunc('month',p_period_start::TIMESTAMP)::DATE END;
    selected_end:=(selected_start+INTERVAL '1 month')::DATE;
  END IF;
  IF selected_start IS NOT NULL THEN
    start_at:=selected_start::TIMESTAMP AT TIME ZONE 'America/New_York';
    end_at:=selected_end::TIMESTAMP AT TIME ZONE 'America/New_York';
  END IF;

  RETURN QUERY
  WITH filtered_matches AS (
    SELECT m.id,m.player_one_id,m.player_two_id,m.winner_id
    FROM public.matches m
    WHERE m.ranked AND m.status='confirmed'
      AND (normalized_scope='all_time' OR (m.confirmed_at>=start_at AND m.confirmed_at<end_at))
  ),player_matches AS (
    SELECT fm.id match_id,fm.player_one_id stats_player_id,fm.player_two_id opponent_id,
      fm.winner_id=fm.player_one_id won FROM filtered_matches fm
    UNION ALL
    SELECT fm.id,fm.player_two_id,fm.player_one_id,fm.winner_id=fm.player_two_id FROM filtered_matches fm
  ),period_stats AS (
    SELECT pm.stats_player_id,COUNT(*)::BIGINT games,
      COUNT(*) FILTER(WHERE pm.won)::BIGINT stat_wins,
      COUNT(*) FILTER(WHERE NOT pm.won)::BIGINT stat_losses,
      COUNT(DISTINCT pm.opponent_id)::BIGINT opponent_count
    FROM player_matches pm GROUP BY pm.stats_player_id
  ),period_rating AS (
    SELECT re.player_id rating_player_id,COALESCE(SUM(re.rating_change),0)::BIGINT net_change
    FROM public.rating_events re JOIN filtered_matches fm ON fm.id=re.match_id
    WHERE re.is_active GROUP BY re.player_id
  ),eligible AS (
    SELECT p.id,p.display_name,p.current_elo,p.total_wins,p.total_losses,
      COALESCE(ps.games,0)::BIGINT games,COALESCE(ps.stat_wins,0)::BIGINT stat_wins,
      COALESCE(ps.stat_losses,0)::BIGINT stat_losses,
      COALESCE(ps.opponent_count,0)::BIGINT opponent_count,
      COALESCE(pr.net_change,0)::BIGINT net_change
    FROM public.profiles p
    LEFT JOIN period_stats ps ON ps.stats_player_id=p.id
    LEFT JOIN period_rating pr ON pr.rating_player_id=p.id
    WHERE normalized_scope='all_time' OR ps.stats_player_id IS NOT NULL
  ),ranked AS (
    SELECT e.*,ROW_NUMBER() OVER(ORDER BY
      CASE WHEN normalized_scope='all_time' THEN e.current_elo END DESC NULLS LAST,
      CASE WHEN normalized_scope<>'all_time' THEN e.net_change END DESC NULLS LAST,
      CASE WHEN normalized_scope<>'all_time' THEN e.stat_wins END DESC NULLS LAST,
      e.current_elo DESC,e.display_name,e.id) row_placement
    FROM eligible e
  )
  SELECT r.row_placement,r.id,r.display_name,r.current_elo,
    CASE WHEN r.total_wins+r.total_losses=0 THEN 'Unranked'
      ELSE public.rank_tier_name_v3(r.current_elo) END,
    FALSE,r.net_change,r.games,r.stat_wins,r.stat_losses,
    CASE WHEN r.games=0 THEN 0::NUMERIC
      ELSE ROUND((r.stat_wins::NUMERIC/r.games)*100,1) END,
    r.opponent_count,selected_start,
    CASE WHEN selected_end IS NULL THEN NULL ELSE selected_end-1 END
  FROM ranked r ORDER BY r.row_placement;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_challenges_opponent_pending_expiry_v4
  ON public.challenges(opponent_id,expires_at DESC) WHERE status='pending';
CREATE INDEX IF NOT EXISTS idx_challenges_challenger_pending_expiry_v4
  ON public.challenges(challenger_id,expires_at DESC) WHERE status='pending';
CREATE INDEX IF NOT EXISTS idx_matches_player_one_ready_expiry_v4
  ON public.matches(player_one_id,expires_at DESC) WHERE status='ready';
CREATE INDEX IF NOT EXISTS idx_matches_player_two_ready_expiry_v4
  ON public.matches(player_two_id,expires_at DESC) WHERE status='ready';

-- Queue heartbeats let refreshes and page switches preserve a live spot while
-- closed browsers are eventually removed instead of blocking the table.
CREATE OR REPLACE FUNCTION public.beaver_queue_advance_internal_v1()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  state public.beaver_queue_table;
  next_player UUID;
  stale_king BOOLEAN:=FALSE;
BEGIN
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue table is not initialized'; END IF;

  IF state.phase<>'playing' AND state.king_id IS NOT NULL THEN
    SELECT member.updated_at<clock_timestamp()-INTERVAL '2 minutes' INTO stale_king
    FROM public.beaver_queue_members member WHERE member.user_id=state.king_id;
    IF COALESCE(stale_king,TRUE) THEN
      UPDATE public.beaver_queue_members SET status='left',updated_at=clock_timestamp()
      WHERE user_id=state.king_id AND status='king';
      UPDATE public.beaver_queue_members SET status='waiting',updated_at=clock_timestamp()
      WHERE user_id=state.challenger_id AND status='called';
      UPDATE public.beaver_queue_table SET phase='idle',king_id=NULL,challenger_id=NULL,
        call_expires_at=NULL,game_id=NULL,game_started_at=NULL,updated_at=clock_timestamp()
      WHERE id=1;
      SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
    END IF;
  END IF;

  UPDATE public.beaver_queue_members SET status='left',updated_at=clock_timestamp()
  WHERE status='waiting' AND updated_at<clock_timestamp()-INTERVAL '2 minutes';

  IF state.phase='called' AND state.call_expires_at<=clock_timestamp() THEN
    UPDATE public.beaver_queue_members SET status='no_show',updated_at=clock_timestamp()
    WHERE user_id=state.challenger_id AND status='called';
    UPDATE public.beaver_queue_table SET phase='idle',challenger_id=NULL,
      call_expires_at=NULL,updated_at=clock_timestamp() WHERE id=1;
    SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
  END IF;
  IF state.phase<>'idle' THEN RETURN; END IF;

  IF state.king_id IS NULL THEN
    SELECT user_id INTO next_player FROM public.beaver_queue_members
    WHERE status='waiting' ORDER BY queue_position,user_id LIMIT 1 FOR UPDATE;
    IF next_player IS NOT NULL THEN
      UPDATE public.beaver_queue_members SET status='king',updated_at=clock_timestamp() WHERE user_id=next_player;
      UPDATE public.beaver_queue_table SET king_id=next_player,updated_at=clock_timestamp() WHERE id=1;
      state.king_id:=next_player;
    END IF;
  END IF;
  IF state.king_id IS NOT NULL THEN
    next_player:=NULL;
    SELECT user_id INTO next_player FROM public.beaver_queue_members
    WHERE status='waiting' AND user_id<>state.king_id
    ORDER BY queue_position,user_id LIMIT 1 FOR UPDATE;
    IF next_player IS NOT NULL THEN
      UPDATE public.beaver_queue_members SET status='called',updated_at=clock_timestamp() WHERE user_id=next_player;
      UPDATE public.beaver_queue_table SET phase='called',challenger_id=next_player,
        call_expires_at=clock_timestamp()+INTERVAL '60 seconds',updated_at=clock_timestamp() WHERE id=1;
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_heartbeat_v1()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  PERFORM 1 FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  UPDATE public.beaver_queue_members SET updated_at=clock_timestamp()
  WHERE user_id=auth.uid() AND status IN ('waiting','called','king','playing');
  PERFORM public.beaver_queue_advance_internal_v1();
END;
$$;

REVOKE ALL ON FUNCTION public.beaver_queue_heartbeat_v1() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.beaver_queue_heartbeat_v1() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.beaver_queue_advance_internal_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION public.get_rank_progress_v3(INTEGER,INTEGER) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_rank_progress_v3(INTEGER,INTEGER) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_leaderboard_v3(TEXT,DATE) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_leaderboard_v3(TEXT,DATE) TO authenticated;
-- The finalizer remains authoritative; clients cannot inspect hypothetical
-- rating outcomes before a real result has been accepted.
REVOKE EXECUTE ON FUNCTION public.get_match_rating_preview_v3(UUID) FROM PUBLIC,anon,authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
