-- Queue V6: explicit game deadlines and challenger presence check-in.
-- Apply after 20261103_05_queue_afk_timeouts.sql.
BEGIN;

DO $dependencies$
BEGIN
  IF to_regprocedure('public.beaver_queue_health_v5()') IS NULL THEN
    RAISE EXCEPTION 'Missing dependency: apply 20261103_05_queue_afk_timeouts.sql first';
  END IF;
END;
$dependencies$;

ALTER TABLE public.beaver_queue_table
  ADD COLUMN IF NOT EXISTS game_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS king_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS challenger_confirmed_at TIMESTAMPTZ;

UPDATE public.beaver_queue_table
SET game_expires_at=game_started_at+INTERVAL '10 minutes'
WHERE phase='playing' AND game_expires_at IS NULL;

-- A player already holding the table is present by definition. Preserve any
-- active call during deployment while requiring only the incoming challenger.
UPDATE public.beaver_queue_table
SET king_confirmed_at=COALESCE(king_confirmed_at,clock_timestamp())
WHERE phase='called';

ALTER TABLE public.beaver_queue_table
  DROP CONSTRAINT IF EXISTS beaver_queue_game_deadline_v6,
  DROP CONSTRAINT IF EXISTS beaver_queue_checkins_v6;
ALTER TABLE public.beaver_queue_table
  ADD CONSTRAINT beaver_queue_game_deadline_v6 CHECK(
    (phase='playing' AND game_expires_at IS NOT NULL)
    OR (phase<>'playing' AND game_expires_at IS NULL)
  ),
  ADD CONSTRAINT beaver_queue_checkins_v6 CHECK(
    phase='called'
    OR (king_confirmed_at IS NULL AND challenger_confirmed_at IS NULL)
  );

CREATE OR REPLACE FUNCTION public.beaver_queue_advance_internal_v1()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  state public.beaver_queue_table%ROWTYPE;
  next_player UUID;
  surviving_player UUID;
  king_is_stale BOOLEAN:=FALSE;
  holder_name TEXT;
  next_name TEXT;
BEGIN
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue table is not initialized'; END IF;
  PERFORM public.beaver_queue_cancel_invalid_swaps_internal_v1();

  IF state.phase='playing' THEN
    -- The earlier authoritative deadline wins. An AFK report can never extend
    -- a game beyond game_expires_at.
    IF state.afk_expires_at IS NOT NULL
       AND state.afk_expires_at<=clock_timestamp()
       AND state.afk_expires_at<=state.game_expires_at THEN
      SELECT display_name INTO holder_name FROM public.beaver_queue_members WHERE user_id=state.king_id;
      SELECT display_name INTO next_name FROM public.beaver_queue_members WHERE user_id=state.challenger_id;
      INSERT INTO public.beaver_queue_games(
        id,king_id,challenger_id,king_name,challenger_name,status,
        king_score,challenger_score,winner_id,loser_id,reported_by,completed_at
      ) VALUES(
        state.game_id,state.king_id,state.challenger_id,
        COALESCE(holder_name,'Player'),COALESCE(next_name,'Player'),'abandoned',
        NULL,NULL,NULL,NULL,NULL,clock_timestamp()
      ) ON CONFLICT(id) DO NOTHING;
      UPDATE public.beaver_queue_members SET status='left',updated_at=clock_timestamp()
      WHERE user_id=state.afk_target_id AND status='playing';
      UPDATE public.beaver_queue_members SET status='king',updated_at=clock_timestamp()
      WHERE user_id=state.afk_reporter_id AND status='playing';
      UPDATE public.beaver_queue_table SET
        phase='idle',king_id=state.afk_reporter_id,challenger_id=NULL,
        call_expires_at=NULL,game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
        king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
        afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,
        updated_at=clock_timestamp()
      WHERE id=1 AND phase='playing' AND game_id=state.game_id;
      SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
    ELSIF state.game_expires_at<=clock_timestamp() THEN
      SELECT display_name INTO holder_name FROM public.beaver_queue_members WHERE user_id=state.king_id;
      SELECT display_name INTO next_name FROM public.beaver_queue_members WHERE user_id=state.challenger_id;
      INSERT INTO public.beaver_queue_games(
        id,king_id,challenger_id,king_name,challenger_name,status,
        king_score,challenger_score,winner_id,loser_id,reported_by,completed_at
      ) VALUES(
        state.game_id,state.king_id,state.challenger_id,
        COALESCE(holder_name,'Player'),COALESCE(next_name,'Player'),'abandoned',
        NULL,NULL,NULL,NULL,NULL,clock_timestamp()
      ) ON CONFLICT(id) DO NOTHING;
      UPDATE public.beaver_queue_members SET status='left',updated_at=clock_timestamp()
      WHERE user_id IN(state.king_id,state.challenger_id) AND status='playing';
      UPDATE public.beaver_queue_table SET
        phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
        game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
        king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
        afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,
        updated_at=clock_timestamp()
      WHERE id=1 AND phase='playing' AND game_id=state.game_id;
      SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
    ELSE
      UPDATE public.beaver_queue_members SET status='left',updated_at=clock_timestamp()
      WHERE status='waiting' AND updated_at<clock_timestamp()-INTERVAL '2 minutes';
      PERFORM public.beaver_queue_cancel_invalid_swaps_internal_v1();
      RETURN;
    END IF;
  END IF;

  IF state.king_id IS NOT NULL AND state.phase<>'playing' THEN
    SELECT member.updated_at<clock_timestamp()-INTERVAL '2 minutes'
      INTO king_is_stale
    FROM public.beaver_queue_members member
    WHERE member.user_id=state.king_id AND member.status='king';
    IF COALESCE(king_is_stale,TRUE) THEN
      UPDATE public.beaver_queue_members SET status='left',updated_at=clock_timestamp()
      WHERE user_id=state.king_id AND status='king';
      UPDATE public.beaver_queue_members SET status='waiting',updated_at=clock_timestamp()
      WHERE user_id=state.challenger_id AND status='called';
      UPDATE public.beaver_queue_table SET
        phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
        game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
        king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
        afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,
        updated_at=clock_timestamp()
      WHERE id=1;
      SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
    END IF;
  END IF;

  IF state.phase='called' AND state.call_expires_at<=clock_timestamp() THEN
    UPDATE public.beaver_queue_members SET status='no_show',updated_at=clock_timestamp()
    WHERE user_id=state.king_id AND status='king' AND state.king_confirmed_at IS NULL;
    UPDATE public.beaver_queue_members SET status='no_show',updated_at=clock_timestamp()
    WHERE user_id=state.challenger_id AND status='called' AND state.challenger_confirmed_at IS NULL;

    surviving_player:=CASE
      WHEN state.king_confirmed_at IS NOT NULL THEN state.king_id
      WHEN state.challenger_confirmed_at IS NOT NULL THEN state.challenger_id
      ELSE NULL
    END;
    IF surviving_player=state.challenger_id THEN
      UPDATE public.beaver_queue_members SET status='king',updated_at=clock_timestamp()
      WHERE user_id=surviving_player AND status='called';
    END IF;
    UPDATE public.beaver_queue_table SET
      phase='idle',king_id=surviving_player,challenger_id=NULL,
      call_expires_at=NULL,game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
      king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
      afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,
      updated_at=clock_timestamp()
    WHERE id=1 AND phase='called';
    SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
  END IF;

  UPDATE public.beaver_queue_members SET status='left',updated_at=clock_timestamp()
  WHERE status='waiting' AND updated_at<clock_timestamp()-INTERVAL '2 minutes';
  PERFORM public.beaver_queue_cancel_invalid_swaps_internal_v1();
  IF state.phase<>'idle' THEN RETURN; END IF;

  IF state.king_id IS NULL THEN
    SELECT member.user_id INTO next_player
    FROM public.beaver_queue_members member
    WHERE member.status='waiting'
    ORDER BY member.queue_position,member.user_id LIMIT 1;
    IF next_player IS NOT NULL THEN
      UPDATE public.beaver_queue_members SET status='king',updated_at=clock_timestamp()
      WHERE user_id=next_player AND status='waiting';
      UPDATE public.beaver_queue_table SET
        king_id=next_player,solo_expires_at=clock_timestamp()+INTERVAL '60 seconds',
        updated_at=clock_timestamp()
      WHERE id=1;
      state.king_id:=next_player;
      state.solo_expires_at:=clock_timestamp()+INTERVAL '60 seconds';
      PERFORM public.beaver_queue_cancel_invalid_swaps_internal_v1();
    END IF;
  END IF;

  IF state.king_id IS NOT NULL THEN
    next_player:=NULL;
    SELECT member.user_id INTO next_player
    FROM public.beaver_queue_members member
    WHERE member.status='waiting' AND member.user_id<>state.king_id
    ORDER BY member.queue_position,member.user_id LIMIT 1;
    IF next_player IS NOT NULL THEN
      UPDATE public.beaver_queue_members SET status='called',updated_at=clock_timestamp()
      WHERE user_id=next_player AND status='waiting';
      UPDATE public.beaver_queue_table SET
        phase='called',challenger_id=next_player,
        call_expires_at=clock_timestamp()+INTERVAL '60 seconds',solo_expires_at=NULL,
        king_confirmed_at=clock_timestamp(),challenger_confirmed_at=NULL,updated_at=clock_timestamp()
      WHERE id=1;
      PERFORM public.beaver_queue_cancel_invalid_swaps_internal_v1();
    ELSIF state.solo_expires_at IS NULL THEN
      UPDATE public.beaver_queue_table SET
        solo_expires_at=clock_timestamp()+INTERVAL '60 seconds',updated_at=clock_timestamp()
      WHERE id=1;
    ELSIF state.solo_expires_at<=clock_timestamp() THEN
      UPDATE public.beaver_queue_members SET status='left',updated_at=clock_timestamp()
      WHERE user_id=state.king_id AND status='king';
      UPDATE public.beaver_queue_table SET
        king_id=NULL,solo_expires_at=NULL,updated_at=clock_timestamp()
      WHERE id=1;
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_leave_v1()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  state public.beaver_queue_table%ROWTYPE;
  member_status TEXT;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue table is not initialized'; END IF;
  PERFORM public.beaver_queue_advance_internal_v1();
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
  SELECT status INTO member_status FROM public.beaver_queue_members WHERE user_id=player_id;
  IF member_status IS NULL OR member_status IN('left','no_show') THEN RETURN; END IF;
  IF member_status='playing' THEN RAISE EXCEPTION 'A game is underway. Report the result before leaving.'; END IF;

  UPDATE public.beaver_queue_swap_requests request
  SET status='canceled',responded_at=clock_timestamp()
  WHERE request.status='pending'
    AND (request.requester_id=player_id OR request.target_id=player_id);
  UPDATE public.beaver_queue_members SET status='left',updated_at=clock_timestamp()
  WHERE user_id=player_id;

  IF player_id=state.king_id THEN
    UPDATE public.beaver_queue_members SET status='waiting',updated_at=clock_timestamp()
    WHERE user_id=state.challenger_id AND status='called';
    UPDATE public.beaver_queue_table SET
      phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
      game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
      king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
      afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,
      updated_at=clock_timestamp() WHERE id=1;
  ELSIF player_id=state.challenger_id THEN
    UPDATE public.beaver_queue_table SET
      phase='idle',challenger_id=NULL,call_expires_at=NULL,solo_expires_at=NULL,
      king_confirmed_at=NULL,challenger_confirmed_at=NULL,updated_at=clock_timestamp()
    WHERE id=1;
  END IF;
  PERFORM public.beaver_queue_advance_internal_v1();
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_confirm_v1()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  state public.beaver_queue_table%ROWTYPE;
  match_started_at TIMESTAMPTZ;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  PERFORM 1 FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  PERFORM public.beaver_queue_advance_internal_v1();
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
  IF state.phase='playing' AND player_id IN(state.king_id,state.challenger_id) THEN
    RETURN;
  END IF;
  IF state.phase<>'called' OR player_id NOT IN(state.king_id,state.challenger_id)
     OR state.call_expires_at<=clock_timestamp() THEN
    RAISE EXCEPTION 'Your 60-second check-in is no longer available';
  END IF;

  IF player_id=state.king_id AND state.king_confirmed_at IS NULL THEN
    UPDATE public.beaver_queue_table SET king_confirmed_at=clock_timestamp(),updated_at=clock_timestamp()
    WHERE id=1 AND phase='called';
  ELSIF player_id=state.challenger_id AND state.challenger_confirmed_at IS NULL THEN
    UPDATE public.beaver_queue_table SET challenger_confirmed_at=clock_timestamp(),updated_at=clock_timestamp()
    WHERE id=1 AND phase='called';
  END IF;

  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
  IF state.king_confirmed_at IS NOT NULL AND state.challenger_confirmed_at IS NOT NULL THEN
    match_started_at:=clock_timestamp();
    UPDATE public.beaver_queue_members SET status='playing',updated_at=clock_timestamp()
    WHERE user_id IN(state.king_id,state.challenger_id);
    UPDATE public.beaver_queue_table SET
      phase='playing',game_id=gen_random_uuid(),game_started_at=match_started_at,
      game_expires_at=match_started_at+INTERVAL '10 minutes',call_expires_at=NULL,
      king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
      afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,
      updated_at=clock_timestamp()
    WHERE id=1 AND phase='called';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_report_outcome_v2(p_game_id UUID,p_outcome TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  normalized_outcome TEXT:=LOWER(BTRIM(COALESCE(p_outcome,'')));
  state public.beaver_queue_table%ROWTYPE;
  existing public.beaver_queue_games%ROWTYPE;
  winner UUID;
  loser UUID;
  holder_name TEXT;
  next_name TEXT;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  IF normalized_outcome NOT IN('won','lost') THEN RAISE EXCEPTION 'Outcome must be won or lost'; END IF;
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue table is not initialized'; END IF;
  SELECT * INTO existing FROM public.beaver_queue_games WHERE id=p_game_id;
  IF FOUND THEN
    IF player_id NOT IN(existing.king_id,existing.challenger_id) THEN
      RAISE EXCEPTION 'Only players in this game can report the outcome';
    END IF;
    IF existing.status<>'completed' THEN RAISE EXCEPTION 'This game was abandoned and cannot be reported'; END IF;
    winner:=CASE WHEN normalized_outcome='won' THEN player_id
      WHEN player_id=existing.king_id THEN existing.challenger_id ELSE existing.king_id END;
    IF winner=existing.winner_id THEN
      RETURN jsonb_build_object('game_id',existing.id,'winner_id',existing.winner_id,
        'loser_id',existing.loser_id,'status','completed','idempotent',TRUE);
    END IF;
    RAISE EXCEPTION 'This game was already finalized with a different outcome. Contact an administrator.';
  END IF;
  IF state.phase<>'playing' OR state.game_id IS DISTINCT FROM p_game_id THEN
    RAISE EXCEPTION 'This game is no longer active. Refresh the queue.';
  END IF;
  IF player_id NOT IN(state.king_id,state.challenger_id) THEN
    RAISE EXCEPTION 'Only players in this game can report the outcome';
  END IF;
  IF state.game_expires_at<=clock_timestamp()
     OR (state.afk_expires_at IS NOT NULL AND state.afk_expires_at<=clock_timestamp()) THEN
    RAISE EXCEPTION 'This game deadline has expired. Refresh the queue.';
  END IF;
  winner:=CASE WHEN normalized_outcome='won' THEN player_id
    WHEN player_id=state.king_id THEN state.challenger_id ELSE state.king_id END;
  loser:=CASE WHEN winner=state.king_id THEN state.challenger_id ELSE state.king_id END;
  SELECT display_name INTO holder_name FROM public.beaver_queue_members WHERE user_id=state.king_id;
  SELECT display_name INTO next_name FROM public.beaver_queue_members WHERE user_id=state.challenger_id;
  INSERT INTO public.beaver_queue_games(
    id,king_id,challenger_id,king_name,challenger_name,status,
    king_score,challenger_score,winner_id,loser_id,reported_by,completed_at
  ) VALUES(
    p_game_id,state.king_id,state.challenger_id,COALESCE(holder_name,'Player'),
    COALESCE(next_name,'Player'),'completed',NULL,NULL,winner,loser,player_id,clock_timestamp()
  );
  UPDATE public.beaver_queue_members SET status='left',updated_at=clock_timestamp() WHERE user_id=loser;
  UPDATE public.beaver_queue_members SET status='king',updated_at=clock_timestamp() WHERE user_id=winner;
  UPDATE public.beaver_queue_table SET
    phase='idle',king_id=winner,challenger_id=NULL,call_expires_at=NULL,
    game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
    king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
    afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,
    updated_at=clock_timestamp() WHERE id=1 AND phase='playing' AND game_id=p_game_id;
  PERFORM public.beaver_queue_advance_internal_v1();
  RETURN jsonb_build_object('game_id',p_game_id,'winner_id',winner,'loser_id',loser,
    'status','completed','idempotent',FALSE);
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_health_v6()
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
    'version','20261104_02','initialized',state.id=1,'phase',state.phase,
    'member_status',my_status,
    'heartbeat_granted',has_function_privilege('authenticated','public.beaver_queue_heartbeat_v1()','EXECUTE'),
    'join_granted',has_function_privilege('authenticated','public.beaver_queue_join_v1()','EXECUTE'),
    'tick_granted',has_function_privilege('authenticated','public.beaver_queue_tick_v1()','EXECUTE'),
    'outcome_granted',has_function_privilege('authenticated','public.beaver_queue_report_outcome_v2(uuid,text)','EXECUTE'),
    'swap_granted',has_function_privilege('authenticated','public.beaver_queue_request_swap_v1(uuid)','EXECUTE')
      AND has_function_privilege('authenticated','public.beaver_queue_respond_swap_v1(uuid,text)','EXECUTE'),
    'afk_granted',has_function_privilege('authenticated','public.beaver_queue_report_afk_v1()','EXECUTE')
      AND has_function_privilege('authenticated','public.beaver_queue_confirm_presence_v1()','EXECUTE')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.beaver_queue_health_v6() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.beaver_queue_health_v6() TO authenticated;

SELECT public.beaver_queue_advance_internal_v1();
NOTIFY pgrst,'reload schema';
COMMIT;
