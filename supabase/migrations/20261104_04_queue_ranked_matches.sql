-- Queue V8: mutually convert an active unranked queue game into the existing
-- ranked-match lifecycle. Apply after 20261104_03_queue_holder_presence.sql.
BEGIN;

DO $dependencies$
BEGIN
  IF to_regprocedure('public.beaver_queue_health_v7()') IS NULL
     OR to_regprocedure('public.respond_challenge_v2(uuid,text)') IS NULL
     OR to_regprocedure('public.submit_match_report_v2(uuid,uuid,integer,integer)') IS NULL
     OR to_regprocedure('public.club_ranked_day_v3(timestamptz)') IS NULL THEN
    RAISE EXCEPTION 'Missing dependency: apply the ranked migrations and 20261104_03_queue_holder_presence.sql first';
  END IF;
END;
$dependencies$;

-- Repair the shared finalizer for databases that already applied 20261104_01.
-- Its original local variable was also named week_start, which PostgreSQL
-- treats as ambiguous inside ON CONFLICT(player_id,week_start).
CREATE OR REPLACE FUNCTION public.finalize_match_v2(p_match_id UUID,p_actor UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  match_row public.matches%ROWTYPE;
  winner public.profiles%ROWTYPE;
  loser public.profiles%ROWTYPE;
  winner_before INTEGER;
  loser_before INTEGER;
  winner_gain INTEGER;
  loser_loss INTEGER;
  player_one_before INTEGER;
  player_two_before INTEGER;
  player_one_delta INTEGER;
  player_two_delta INTEGER;
  current_week_start DATE;
  domain_event UUID;
  calculation JSONB;
BEGIN
  SELECT * INTO match_row FROM public.matches WHERE id=p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF match_row.status='confirmed' THEN
    RETURN jsonb_build_object(
      'match_id',match_row.id,
      'already_finalized',TRUE,
      'player_one_change',match_row.player_one_elo_change,
      'player_two_change',match_row.player_two_elo_change,
      'player_one_new',match_row.player_one_elo_before+match_row.player_one_elo_change,
      'player_two_new',match_row.player_two_elo_before+match_row.player_two_elo_change,
      'rating_calculation',match_row.rating_calculation
    );
  END IF;
  IF match_row.status<>'result_reported' THEN
    RAISE EXCEPTION 'Match is not eligible for finalization';
  END IF;
  IF match_row.winner_id NOT IN(match_row.player_one_id,match_row.player_two_id)
     OR NOT public.is_valid_match_score_v2(match_row.player_one_score,match_row.player_two_score) THEN
    RAISE EXCEPTION 'Invalid final result';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    LEAST(match_row.player_one_id::TEXT,match_row.player_two_id::TEXT)||':'||
    GREATEST(match_row.player_one_id::TEXT,match_row.player_two_id::TEXT)||':'||
    COALESCE(match_row.ranked_day::TEXT,public.club_ranked_day_v3()::TEXT),0
  ));
  PERFORM id FROM public.profiles
  WHERE id IN(match_row.player_one_id,match_row.player_two_id)
  ORDER BY id FOR UPDATE;

  SELECT * INTO winner FROM public.profiles WHERE id=match_row.winner_id;
  SELECT * INTO loser FROM public.profiles
  WHERE id=CASE WHEN match_row.winner_id=match_row.player_one_id
    THEN match_row.player_two_id ELSE match_row.player_one_id END;

  winner_before:=CASE WHEN winner.total_wins+winner.total_losses=0 THEN 50 ELSE winner.current_elo END;
  loser_before:=CASE WHEN loser.total_wins+loser.total_losses=0 THEN 50 ELSE loser.current_elo END;
  calculation:=public.calculate_weighted_elo_v3(
    winner_before,
    loser_before,
    GREATEST(match_row.player_one_score,match_row.player_two_score),
    LEAST(match_row.player_one_score,match_row.player_two_score)
  )||jsonb_build_object(
    'winner_id',winner.id,
    'loser_id',loser.id,
    'winner_rating_before',winner_before,
    'loser_rating_before',loser_before
  );
  winner_gain:=(calculation->>'winner_gain')::INTEGER;
  loser_loss:=(calculation->>'loser_loss')::INTEGER;

  player_one_before:=CASE WHEN match_row.player_one_id=winner.id THEN winner_before ELSE loser_before END;
  player_two_before:=CASE WHEN match_row.player_two_id=winner.id THEN winner_before ELSE loser_before END;
  player_one_delta:=CASE WHEN match_row.player_one_id=winner.id THEN winner_gain ELSE -loser_loss END;
  player_two_delta:=CASE WHEN match_row.player_two_id=winner.id THEN winner_gain ELSE -loser_loss END;
  current_week_start:=(date_trunc('week',NOW() AT TIME ZONE 'America/New_York'))::DATE;

  UPDATE public.profiles SET
    current_elo=winner_before+winner_gain,
    highest_elo=GREATEST(
      CASE WHEN total_wins+total_losses=0 THEN 50 ELSE highest_elo END,
      winner_before+winner_gain
    ),
    total_wins=total_wins+1,
    weekly_wins=weekly_wins+1,
    current_streak=GREATEST(current_streak,0)+1,
    longest_streak=GREATEST(longest_streak,GREATEST(current_streak,0)+1),
    updated_at=NOW()
  WHERE id=winner.id;

  UPDATE public.profiles SET
    current_elo=GREATEST(loser_before-loser_loss,0),
    highest_elo=CASE WHEN total_wins+total_losses=0
      THEN GREATEST(50,loser_before-loser_loss)
      ELSE highest_elo END,
    total_losses=total_losses+1,
    weekly_losses=weekly_losses+1,
    current_streak=LEAST(current_streak,0)-1,
    updated_at=NOW()
  WHERE id=loser.id;

  INSERT INTO public.rating_events(
    match_id,player_id,event_kind,rating_before,rating_change,
    rating_after,revision,calculation
  ) VALUES(
    match_row.id,match_row.player_one_id,'match_result',
    player_one_before,player_one_delta,player_one_before+player_one_delta,
    match_row.revision,calculation
  );
  INSERT INTO public.rating_events(
    match_id,player_id,event_kind,rating_before,rating_change,
    rating_after,revision,calculation
  ) VALUES(
    match_row.id,match_row.player_two_id,'match_result',
    player_two_before,player_two_delta,player_two_before+player_two_delta,
    match_row.revision,calculation
  );

  INSERT INTO public.weekly_player_stats(player_id,week_start,wins,losses)
  VALUES(winner.id,current_week_start,1,0)
  ON CONFLICT(player_id,week_start) DO UPDATE SET
    wins=public.weekly_player_stats.wins+1,
    updated_at=NOW();
  INSERT INTO public.weekly_player_stats(player_id,week_start,wins,losses)
  VALUES(loser.id,current_week_start,0,1)
  ON CONFLICT(player_id,week_start) DO UPDATE SET
    losses=public.weekly_player_stats.losses+1,
    updated_at=NOW();

  IF match_row.season_id IS NOT NULL THEN
    INSERT INTO public.player_season_stats(season_id,player_id,starting_elo,high_elo,wins,losses)
    VALUES(match_row.season_id,winner.id,winner_before,winner_before+winner_gain,1,0)
    ON CONFLICT(season_id,player_id) DO UPDATE SET
      high_elo=GREATEST(public.player_season_stats.high_elo,EXCLUDED.high_elo),
      wins=public.player_season_stats.wins+1;
    INSERT INTO public.player_season_stats(season_id,player_id,starting_elo,high_elo,wins,losses)
    VALUES(match_row.season_id,loser.id,loser_before,loser_before,0,1)
    ON CONFLICT(season_id,player_id) DO UPDATE SET
      high_elo=GREATEST(public.player_season_stats.high_elo,EXCLUDED.high_elo),
      losses=public.player_season_stats.losses+1;
  END IF;

  UPDATE public.matches SET
    status='confirmed',
    confirmed_by=p_actor,
    confirmed_at=NOW(),
    finalized_at=NOW(),
    expires_at=NULL,
    player_one_elo_before=player_one_before,
    player_two_elo_before=player_two_before,
    player_one_elo_change=player_one_delta,
    player_two_elo_change=player_two_delta,
    rating_calculation=calculation
  WHERE id=match_row.id;

  IF match_row.challenge_id IS NOT NULL THEN
    UPDATE public.challenges SET status='completed' WHERE id=match_row.challenge_id;
  END IF;
  domain_event:=public.emit_domain_event(
    'match.confirmed',p_actor,match_row.id,match_row.challenge_id,
    jsonb_build_object(
      'winner_id',winner.id,
      'player_one_change',player_one_delta,
      'player_two_change',player_two_delta,
      'rating_calculation',calculation
    ),ARRAY[match_row.player_one_id,match_row.player_two_id]
  );
  IF (SELECT COUNT(*) FROM public.matches recent
      WHERE recent.status='confirmed' AND recent.ranked
        AND recent.confirmed_at>NOW()-INTERVAL '24 hours'
        AND (recent.player_one_id IN(match_row.player_one_id,match_row.player_two_id)
          OR recent.player_two_id IN(match_row.player_one_id,match_row.player_two_id)))>=15 THEN
    INSERT INTO public.integrity_flags(player_id,match_id,flag_type,details)
    VALUES(p_actor,match_row.id,'high_match_volume',jsonb_build_object('window_hours',24));
  END IF;

  RETURN jsonb_build_object(
    'match_id',match_row.id,
    'already_finalized',FALSE,
    'player_one_change',player_one_delta,
    'player_two_change',player_two_delta,
    'player_one_new',player_one_before+player_one_delta,
    'player_two_new',player_two_before+player_two_delta,
    'rating_calculation',calculation
  );
END;
$$;

-- Queue matches and regular challenges reserve the same daily allowance.
-- The product limit is ten games for a player and three for a player pair.
UPDATE public.ranking_config
SET daily_ranked_player_limit=10,
    daily_ranked_pair_limit=3,
    updated_at=clock_timestamp()
WHERE id;

-- This is the single acceptance-time eligibility gate for both normal
-- challenges and queue-created ranked matches. It deliberately reserves no
-- capacity until both players agree.
CREATE OR REPLACE FUNCTION public.assert_ranked_match_eligibility_v4(
  p_challenger UUID,
  p_opponent UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  cfg public.ranking_config%ROWTYPE;
  day DATE:=public.club_ranked_day_v3();
  usage_count INTEGER;
BEGIN
  IF p_challenger IS NULL OR p_opponent IS NULL OR p_challenger=p_opponent THEN
    RAISE EXCEPTION 'Ranked matches require two different players';
  END IF;

  PERFORM public.assert_ranked_access(p_challenger);
  PERFORM public.assert_ranked_access(p_opponent);

  -- Expired ready matches no longer consume an active or daily reservation.
  WITH expired_matches AS (
    UPDATE public.matches
    SET status='expired',finalized_at=clock_timestamp()
    WHERE status='ready'
      AND expires_at IS NOT NULL
      AND expires_at<=clock_timestamp()
      AND (player_one_id IN(p_challenger,p_opponent)
        OR player_two_id IN(p_challenger,p_opponent))
    RETURNING id
  )
  UPDATE public.match_cancellation_requests request
  SET status='expired',responded_at=clock_timestamp()
  FROM expired_matches stale
  WHERE request.match_id=stale.id AND request.status='pending';

  -- Every acceptance path takes the same stable locks before counting. This
  -- prevents a queue accept and a challenge accept from exceeding a limit.
  PERFORM id FROM public.profiles
  WHERE id IN(p_challenger,p_opponent)
  ORDER BY id
  FOR UPDATE;

  SELECT * INTO cfg FROM public.ranking_config WHERE id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ranked match configuration is missing'; END IF;

  SELECT COUNT(*) INTO usage_count
  FROM public.matches
  WHERE ranked AND status='ready'
    AND p_challenger IN(player_one_id,player_two_id);
  IF usage_count>=cfg.active_ranked_match_limit THEN
    RAISE EXCEPTION 'The challenger already has % active ranked matches',cfg.active_ranked_match_limit;
  END IF;

  SELECT COUNT(*) INTO usage_count
  FROM public.matches
  WHERE ranked AND status='ready'
    AND p_opponent IN(player_one_id,player_two_id);
  IF usage_count>=cfg.active_ranked_match_limit THEN
    RAISE EXCEPTION 'You already have % active ranked matches',cfg.active_ranked_match_limit;
  END IF;

  IF EXISTS(
    SELECT 1 FROM public.matches
    WHERE ranked AND status='ready'
      AND LEAST(player_one_id,player_two_id)=LEAST(p_challenger,p_opponent)
      AND GREATEST(player_one_id,player_two_id)=GREATEST(p_challenger,p_opponent)
  ) THEN
    RAISE EXCEPTION 'You already have an unfinished ranked match with this opponent';
  END IF;

  SELECT COUNT(*) INTO usage_count
  FROM public.matches
  WHERE ranked AND ranked_day=day
    AND status IN('ready','result_reported','confirmed')
    AND p_challenger IN(player_one_id,player_two_id);
  IF usage_count>=cfg.daily_ranked_player_limit THEN
    RAISE EXCEPTION 'The challenger has reached the % ranked games per day limit',cfg.daily_ranked_player_limit;
  END IF;

  SELECT COUNT(*) INTO usage_count
  FROM public.matches
  WHERE ranked AND ranked_day=day
    AND status IN('ready','result_reported','confirmed')
    AND p_opponent IN(player_one_id,player_two_id);
  IF usage_count>=cfg.daily_ranked_player_limit THEN
    RAISE EXCEPTION 'You have reached the % ranked games per day limit',cfg.daily_ranked_player_limit;
  END IF;

  SELECT COUNT(*) INTO usage_count
  FROM public.matches
  WHERE ranked AND ranked_day=day
    AND status IN('ready','result_reported','confirmed')
    AND LEAST(player_one_id,player_two_id)=LEAST(p_challenger,p_opponent)
    AND GREATEST(player_one_id,player_two_id)=GREATEST(p_challenger,p_opponent);
  IF usage_count>=cfg.daily_ranked_pair_limit THEN
    RAISE EXCEPTION 'You have reached the daily limit of % ranked games against this opponent',cfg.daily_ranked_pair_limit;
  END IF;
END;
$$;

-- Keep regular challenge acceptance on the same gate used by queue matches.
CREATE OR REPLACE FUNCTION public.respond_challenge_v2(p_challenge UUID,p_action TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  c public.challenges%ROWTYPE;
  m public.matches%ROWTYPE;
  cfg public.ranking_config%ROWTYPE;
  day DATE:=public.club_ranked_day_v3();
BEGIN
  SELECT * INTO c FROM public.challenges WHERE id=p_challenge FOR UPDATE;
  IF NOT FOUND OR c.opponent_id<>auth.uid() OR c.status<>'pending' THEN
    RAISE EXCEPTION 'Challenge is not actionable';
  END IF;
  IF c.expires_at<=clock_timestamp() THEN
    UPDATE public.challenges SET status='expired' WHERE id=c.id;
    RETURN jsonb_build_object('challenge_id',c.id,'status','expired');
  END IF;
  IF p_action='decline' THEN
    UPDATE public.challenges SET status='declined' WHERE id=c.id;
    PERFORM public.emit_domain_event(
      'challenge.declined',auth.uid(),NULL,c.id,'{}',ARRAY[c.challenger_id]
    );
    RETURN jsonb_build_object('challenge_id',c.id,'status','declined');
  ELSIF p_action<>'accept' THEN
    RAISE EXCEPTION 'Invalid challenge action';
  END IF;

  PERFORM public.assert_ranked_match_eligibility_v4(c.challenger_id,c.opponent_id);
  SELECT * INTO cfg FROM public.ranking_config WHERE id;

  INSERT INTO public.matches(
    challenge_id,player_one_id,player_two_id,status,source,ranked,
    verification_mode,season_id,expires_at,ranked_day
  ) VALUES(
    c.id,c.challenger_id,c.opponent_id,'ready','challenge',TRUE,
    'normal',(SELECT id FROM public.seasons WHERE is_active LIMIT 1),
    clock_timestamp()+make_interval(hours=>cfg.result_expiry_hours),day
  ) RETURNING * INTO m;

  UPDATE public.challenges SET status='accepted' WHERE id=c.id;
  PERFORM public.emit_domain_event(
    'challenge.accepted',auth.uid(),m.id,c.id,
    jsonb_build_object('expires_at',m.expires_at,'ranked_day',m.ranked_day),
    ARRAY[c.challenger_id,c.opponent_id]
  );
  RETURN jsonb_build_object(
    'challenge_id',c.id,'status','accepted','match_id',m.id,
    'expires_at',m.expires_at,'ranked_day',m.ranked_day
  );
END;
$$;

CREATE TABLE public.beaver_queue_ranked_requests(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_game_id UUID NOT NULL UNIQUE,
  requester_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  opponent_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK(status IN('pending','accepted','declined','canceled')),
  match_id UUID UNIQUE REFERENCES public.matches(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  responded_at TIMESTAMPTZ,
  CONSTRAINT beaver_queue_ranked_distinct_players CHECK(requester_id<>opponent_id),
  CONSTRAINT beaver_queue_ranked_response_consistent CHECK(
    (status='pending' AND responded_at IS NULL AND match_id IS NULL)
    OR (status='accepted' AND responded_at IS NOT NULL AND match_id IS NOT NULL)
    OR (status IN('declined','canceled') AND responded_at IS NOT NULL AND match_id IS NULL)
  )
);

CREATE INDEX beaver_queue_ranked_participants_v8
  ON public.beaver_queue_ranked_requests(requester_id,opponent_id,created_at DESC);

ALTER TABLE public.beaver_queue_ranked_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.beaver_queue_ranked_requests FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE public.beaver_queue_ranked_requests TO authenticated;
CREATE POLICY "Ranked request participants read requests"
  ON public.beaver_queue_ranked_requests FOR SELECT TO authenticated
  USING(auth.uid() IN(requester_id,opponent_id));

-- Any transition away from the exact active queue game cancels its unanswered
-- request. This covers results, deadlines, AFK removal, and administrative
-- repairs without duplicating cancellation code in every queue function.
CREATE OR REPLACE FUNCTION public.beaver_queue_cancel_ranked_request_v1()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
BEGIN
  IF OLD.phase='playing' AND OLD.game_id IS NOT NULL
     AND (NEW.phase<>'playing' OR NEW.game_id IS DISTINCT FROM OLD.game_id
       OR NEW.king_id IS DISTINCT FROM OLD.king_id
       OR NEW.challenger_id IS DISTINCT FROM OLD.challenger_id) THEN
    UPDATE public.beaver_queue_ranked_requests
    SET status='canceled',responded_at=clock_timestamp()
    WHERE queue_game_id=OLD.game_id AND status='pending';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS beaver_queue_cancel_ranked_request_v1 ON public.beaver_queue_table;
CREATE TRIGGER beaver_queue_cancel_ranked_request_v1
AFTER UPDATE OF phase,game_id,king_id,challenger_id
ON public.beaver_queue_table
FOR EACH ROW
EXECUTE FUNCTION public.beaver_queue_cancel_ranked_request_v1();

CREATE OR REPLACE FUNCTION public.beaver_queue_request_ranked_v1()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  state public.beaver_queue_table%ROWTYPE;
  request_id UUID;
  opponent UUID;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  PERFORM 1 FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  PERFORM public.beaver_queue_advance_internal_v1();
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
  IF state.phase<>'playing' OR player_id NOT IN(state.king_id,state.challenger_id) THEN
    RAISE EXCEPTION 'Only players in the current match can request Ranked';
  END IF;
  IF state.game_expires_at<=clock_timestamp()
     OR (state.afk_expires_at IS NOT NULL AND state.afk_expires_at<=clock_timestamp()) THEN
    RAISE EXCEPTION 'This queue match has expired. Refresh the queue.';
  END IF;
  IF EXISTS(SELECT 1 FROM public.beaver_queue_ranked_requests
    WHERE queue_game_id=state.game_id) THEN
    RAISE EXCEPTION 'A Ranked request was already made for this match';
  END IF;
  opponent:=CASE WHEN player_id=state.king_id THEN state.challenger_id ELSE state.king_id END;
  INSERT INTO public.beaver_queue_ranked_requests(queue_game_id,requester_id,opponent_id)
  VALUES(state.game_id,player_id,opponent)
  RETURNING id INTO request_id;
  RETURN jsonb_build_object('request_id',request_id,'status','pending');
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_respond_ranked_v1(
  p_request UUID,
  p_action TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  normalized_action TEXT:=LOWER(BTRIM(COALESCE(p_action,'')));
  state public.beaver_queue_table%ROWTYPE;
  request public.beaver_queue_ranked_requests%ROWTYPE;
  ranked_match public.matches%ROWTYPE;
  cfg public.ranking_config%ROWTYPE;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  IF normalized_action NOT IN('accept','decline') THEN
    RAISE EXCEPTION 'Action must be accept or decline';
  END IF;

  -- Table then request is the same lock order used by queue transitions and
  -- their cancellation trigger.
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue table is not initialized'; END IF;
  SELECT * INTO request FROM public.beaver_queue_ranked_requests
  WHERE id=p_request FOR UPDATE;

  IF NOT FOUND OR player_id<>request.opponent_id THEN
    RAISE EXCEPTION 'Ranked request is not available';
  END IF;
  IF request.status='accepted' THEN
    RETURN jsonb_build_object(
      'request_id',request.id,'status','accepted','match_id',request.match_id,
      'idempotent',TRUE
    );
  END IF;
  IF request.status<>'pending' THEN
    RAISE EXCEPTION 'Ranked request is no longer available';
  END IF;
  IF state.phase<>'playing' OR state.game_id IS DISTINCT FROM request.queue_game_id
     OR state.king_id NOT IN(request.requester_id,request.opponent_id)
     OR state.challenger_id NOT IN(request.requester_id,request.opponent_id) THEN
    UPDATE public.beaver_queue_ranked_requests
    SET status='canceled',responded_at=clock_timestamp()
    WHERE id=request.id;
    RAISE EXCEPTION 'The queue match changed before the Ranked request was answered';
  END IF;
  IF state.game_expires_at<=clock_timestamp()
     OR (state.afk_expires_at IS NOT NULL AND state.afk_expires_at<=clock_timestamp()) THEN
    RAISE EXCEPTION 'This queue match has expired. Refresh the queue.';
  END IF;

  IF normalized_action='decline' THEN
    UPDATE public.beaver_queue_ranked_requests
    SET status='declined',responded_at=clock_timestamp()
    WHERE id=request.id;
    RETURN jsonb_build_object('request_id',request.id,'status','declined');
  END IF;

  -- All eligibility work happens at final mutual agreement, under the same
  -- player locks used by ordinary challenge acceptance.
  PERFORM public.assert_ranked_match_eligibility_v4(request.requester_id,request.opponent_id);
  SELECT * INTO cfg FROM public.ranking_config WHERE id;
  INSERT INTO public.matches(
    player_one_id,player_two_id,status,source,ranked,verification_mode,
    request_id,season_id,expires_at,ranked_day
  ) VALUES(
    request.requester_id,request.opponent_id,'ready','spontaneous',TRUE,'normal',
    request.id,(SELECT id FROM public.seasons WHERE is_active LIMIT 1),
    clock_timestamp()+make_interval(hours=>cfg.result_expiry_hours),
    public.club_ranked_day_v3()
  ) RETURNING * INTO ranked_match;

  UPDATE public.beaver_queue_ranked_requests
  SET status='accepted',match_id=ranked_match.id,responded_at=clock_timestamp()
  WHERE id=request.id;
  UPDATE public.beaver_queue_swap_requests
  SET status='canceled',responded_at=clock_timestamp()
  WHERE status='pending'
    AND (request.requester_id IN(requester_id,target_id)
      OR request.opponent_id IN(requester_id,target_id));
  UPDATE public.beaver_queue_members
  SET status='left',updated_at=clock_timestamp()
  WHERE user_id IN(request.requester_id,request.opponent_id) AND status='playing';
  UPDATE public.beaver_queue_table SET
    phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
    game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
    king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
    afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,
    updated_at=clock_timestamp()
  WHERE id=1 AND phase='playing' AND game_id=request.queue_game_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'The queue match changed during Ranked conversion'; END IF;

  PERFORM public.beaver_queue_advance_internal_v1();
  RETURN jsonb_build_object(
    'request_id',request.id,'status','accepted','match_id',ranked_match.id,
    'expires_at',ranked_match.expires_at,'ranked_day',ranked_match.ranked_day,
    'idempotent',FALSE
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_health_v8()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  state public.beaver_queue_table%ROWTYPE;
  my_status TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
  SELECT status INTO my_status FROM public.beaver_queue_members WHERE user_id=auth.uid();
  RETURN jsonb_build_object(
    'version','20261104_04','initialized',state.id=1,'phase',state.phase,
    'member_status',my_status,
    'heartbeat_granted',has_function_privilege('authenticated','public.beaver_queue_heartbeat_v1()','EXECUTE'),
    'join_granted',has_function_privilege('authenticated','public.beaver_queue_join_v1()','EXECUTE'),
    'tick_granted',has_function_privilege('authenticated','public.beaver_queue_tick_v1()','EXECUTE'),
    'outcome_granted',has_function_privilege('authenticated','public.beaver_queue_report_outcome_v2(uuid,text)','EXECUTE'),
    'swap_granted',has_function_privilege('authenticated','public.beaver_queue_request_swap_v1(uuid)','EXECUTE')
      AND has_function_privilege('authenticated','public.beaver_queue_respond_swap_v1(uuid,text)','EXECUTE'),
    'afk_granted',has_function_privilege('authenticated','public.beaver_queue_report_afk_v1()','EXECUTE')
      AND has_function_privilege('authenticated','public.beaver_queue_confirm_presence_v1()','EXECUTE'),
    'ranked_granted',has_function_privilege('authenticated','public.beaver_queue_request_ranked_v1()','EXECUTE')
      AND has_function_privilege('authenticated','public.beaver_queue_respond_ranked_v1(uuid,text)','EXECUTE'),
    'ranked_requests_ready',to_regclass('public.beaver_queue_ranked_requests') IS NOT NULL,
    'holder_presence_trigger',EXISTS(
      SELECT 1 FROM pg_catalog.pg_trigger trigger_row
      WHERE trigger_row.tgrelid='public.beaver_queue_table'::regclass
        AND trigger_row.tgname='beaver_queue_autoconfirm_holder_v1'
        AND NOT trigger_row.tgisinternal
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.assert_ranked_match_eligibility_v4(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_cancel_ranked_request_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_request_ranked_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_respond_ranked_v1(UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_health_v8() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.beaver_queue_request_ranked_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_respond_ranked_v1(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_health_v8() TO authenticated;

DO $realtime$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_publication WHERE pubname='supabase_realtime')
     AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_publication_tables
       WHERE pubname='supabase_realtime' AND schemaname='public'
         AND tablename='beaver_queue_ranked_requests') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.beaver_queue_ranked_requests;
  END IF;
END;
$realtime$;

NOTIFY pgrst,'reload schema';
COMMIT;
