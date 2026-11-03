-- Queue V3: outcome-only games, ten-minute game deadlines, mutual position
-- swaps, and audited admin history corrections. Apply after 20261103_02.
BEGIN;

DO $dependencies$
BEGIN
  IF to_regprocedure('public.beaver_queue_health_v2()') IS NULL
     OR to_regclass('public.beaver_queue_table') IS NULL
     OR to_regclass('public.beaver_queue_members') IS NULL
     OR to_regclass('public.beaver_queue_games') IS NULL THEN
    RAISE EXCEPTION 'Missing dependency: apply 20261103_02_queue_production_repair.sql first';
  END IF;
END;
$dependencies$;

ALTER TABLE public.beaver_queue_games
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'completed',
  ADD COLUMN IF NOT EXISTS loser_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS corrected_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS corrected_by UUID REFERENCES public.profiles(id) ON DELETE RESTRICT;

UPDATE public.beaver_queue_games
SET loser_id=CASE WHEN winner_id=king_id THEN challenger_id ELSE king_id END
WHERE status='completed' AND loser_id IS NULL;

ALTER TABLE public.beaver_queue_games
  ALTER COLUMN king_score DROP NOT NULL,
  ALTER COLUMN challenger_score DROP NOT NULL,
  ALTER COLUMN winner_id DROP NOT NULL,
  ALTER COLUMN reported_by DROP NOT NULL;

ALTER TABLE public.beaver_queue_games
  DROP CONSTRAINT IF EXISTS beaver_queue_game_score_valid,
  DROP CONSTRAINT IF EXISTS beaver_queue_winner_is_player,
  DROP CONSTRAINT IF EXISTS beaver_queue_game_outcome_v3,
  DROP CONSTRAINT IF EXISTS beaver_queue_game_scores_v3,
  DROP CONSTRAINT IF EXISTS beaver_queue_game_correction_v3;

ALTER TABLE public.beaver_queue_games
  ADD CONSTRAINT beaver_queue_game_outcome_v3 CHECK (
    (status='completed'
      AND winner_id IS NOT NULL
      AND loser_id IS NOT NULL
      AND reported_by IS NOT NULL
      AND winner_id IN (king_id,challenger_id)
      AND loser_id IN (king_id,challenger_id)
      AND winner_id<>loser_id
      AND reported_by IN (king_id,challenger_id))
    OR
    (status='abandoned' AND winner_id IS NULL AND loser_id IS NULL AND reported_by IS NULL
      AND king_score IS NULL AND challenger_score IS NULL)
  ),
  ADD CONSTRAINT beaver_queue_game_scores_v3 CHECK (
    (king_score IS NULL AND challenger_score IS NULL)
    OR
    (king_score IS NOT NULL AND challenger_score IS NOT NULL
      AND king_score BETWEEN 0 AND 99 AND challenger_score BETWEEN 0 AND 99
      AND GREATEST(king_score,challenger_score)>=11
      AND ABS(king_score-challenger_score)>=2
      AND (GREATEST(king_score,challenger_score)=11 OR ABS(king_score-challenger_score)=2))
  ),
  ADD CONSTRAINT beaver_queue_game_correction_v3 CHECK (
    (corrected_at IS NULL AND corrected_by IS NULL)
    OR (corrected_at IS NOT NULL AND corrected_by IS NOT NULL)
  );

CREATE TABLE IF NOT EXISTS public.beaver_queue_swap_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  target_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  requester_position BIGINT NOT NULL,
  target_position BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK(status IN ('pending','accepted','declined','expired','canceled')),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()+INTERVAL '60 seconds',
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  responded_at TIMESTAMPTZ,
  CONSTRAINT beaver_queue_swap_distinct_players CHECK(requester_id<>target_id),
  CONSTRAINT beaver_queue_swap_direction CHECK(target_position<requester_position),
  CONSTRAINT beaver_queue_swap_response_time CHECK(
    (status='pending' AND responded_at IS NULL)
    OR (status<>'pending' AND responded_at IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS beaver_queue_swap_requester_pending_v3
  ON public.beaver_queue_swap_requests(requester_id,expires_at) WHERE status='pending';
CREATE INDEX IF NOT EXISTS beaver_queue_swap_target_pending_v3
  ON public.beaver_queue_swap_requests(target_id,expires_at) WHERE status='pending';

CREATE TABLE IF NOT EXISTS public.beaver_queue_game_corrections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES public.beaver_queue_games(id) ON DELETE RESTRICT,
  old_winner_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  old_loser_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  new_winner_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  new_loser_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  corrected_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  reason TEXT NOT NULL CHECK(LENGTH(BTRIM(reason)) BETWEEN 3 AND 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT beaver_queue_correction_changes_winner CHECK(old_winner_id<>new_winner_id)
);

ALTER TABLE public.beaver_queue_swap_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.beaver_queue_game_corrections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.beaver_queue_swap_requests,public.beaver_queue_game_corrections
  FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE public.beaver_queue_swap_requests,public.beaver_queue_game_corrections
  TO authenticated;

DROP POLICY IF EXISTS "Swap participants read requests" ON public.beaver_queue_swap_requests;
CREATE POLICY "Swap participants read requests" ON public.beaver_queue_swap_requests
  FOR SELECT TO authenticated
  USING(auth.uid() IN (requester_id,target_id));
DROP POLICY IF EXISTS "Admins read queue corrections" ON public.beaver_queue_game_corrections;
CREATE POLICY "Admins read queue corrections" ON public.beaver_queue_game_corrections
  FOR SELECT TO authenticated USING(public.is_admin());

DROP POLICY IF EXISTS "Authenticated users read queue game history" ON public.beaver_queue_games;
DROP POLICY IF EXISTS "Authenticated users read completed queue game history" ON public.beaver_queue_games;
CREATE POLICY "Authenticated users read completed queue game history"
  ON public.beaver_queue_games FOR SELECT TO authenticated
  USING(status='completed' OR public.is_admin());

CREATE OR REPLACE FUNCTION public.beaver_queue_cancel_invalid_swaps_internal_v1()
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path=''
AS $$
  UPDATE public.beaver_queue_swap_requests request
  SET status=CASE WHEN request.expires_at<=clock_timestamp() THEN 'expired' ELSE 'canceled' END,
      responded_at=clock_timestamp()
  WHERE request.status='pending'
    AND (
      request.expires_at<=clock_timestamp()
      OR NOT EXISTS(
        SELECT 1 FROM public.beaver_queue_members member
        WHERE member.user_id=request.requester_id AND member.status='waiting'
      )
      OR NOT EXISTS(
        SELECT 1 FROM public.beaver_queue_members member
        WHERE member.user_id=request.target_id AND member.status='waiting'
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_advance_internal_v1()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  state public.beaver_queue_table%ROWTYPE;
  next_player UUID;
  king_is_stale BOOLEAN:=FALSE;
  holder_name TEXT;
  next_name TEXT;
BEGIN
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue table is not initialized'; END IF;
  PERFORM public.beaver_queue_cancel_invalid_swaps_internal_v1();

  IF state.phase='playing' THEN
    IF state.game_started_at<=clock_timestamp()-INTERVAL '10 minutes' THEN
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
      UPDATE public.beaver_queue_members
      SET status='left',updated_at=clock_timestamp()
      WHERE user_id IN(state.king_id,state.challenger_id) AND status='playing';
      UPDATE public.beaver_queue_table SET
        phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
        game_id=NULL,game_started_at=NULL,updated_at=clock_timestamp()
      WHERE id=1;
      SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
    ELSE
      UPDATE public.beaver_queue_members
      SET status='left',updated_at=clock_timestamp()
      WHERE status='waiting' AND updated_at<clock_timestamp()-INTERVAL '2 minutes';
      PERFORM public.beaver_queue_cancel_invalid_swaps_internal_v1();
      RETURN;
    END IF;
  END IF;

  IF state.king_id IS NOT NULL THEN
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
        game_id=NULL,game_started_at=NULL,updated_at=clock_timestamp()
      WHERE id=1;
      SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
    END IF;
  END IF;

  IF state.phase='called' AND state.call_expires_at<=clock_timestamp() THEN
    UPDATE public.beaver_queue_members SET status='no_show',updated_at=clock_timestamp()
    WHERE user_id=state.challenger_id AND status='called';
    UPDATE public.beaver_queue_table SET
      phase='idle',challenger_id=NULL,call_expires_at=NULL,updated_at=clock_timestamp()
    WHERE id=1;
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
      UPDATE public.beaver_queue_table SET king_id=next_player,updated_at=clock_timestamp()
      WHERE id=1;
      state.king_id:=next_player;
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
        call_expires_at=clock_timestamp()+INTERVAL '60 seconds',updated_at=clock_timestamp()
      WHERE id=1;
      PERFORM public.beaver_queue_cancel_invalid_swaps_internal_v1();
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
      game_id=NULL,game_started_at=NULL,updated_at=clock_timestamp() WHERE id=1;
  ELSIF player_id=state.challenger_id THEN
    UPDATE public.beaver_queue_table SET
      phase='idle',challenger_id=NULL,call_expires_at=NULL,updated_at=clock_timestamp() WHERE id=1;
  END IF;
  PERFORM public.beaver_queue_advance_internal_v1();
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
  UPDATE public.beaver_queue_members SET status='left',updated_at=clock_timestamp()
  WHERE user_id=loser;
  UPDATE public.beaver_queue_members SET status='king',updated_at=clock_timestamp()
  WHERE user_id=winner;
  UPDATE public.beaver_queue_table SET
    phase='idle',king_id=winner,challenger_id=NULL,call_expires_at=NULL,
    game_id=NULL,game_started_at=NULL,updated_at=clock_timestamp() WHERE id=1;
  PERFORM public.beaver_queue_advance_internal_v1();
  RETURN jsonb_build_object('game_id',p_game_id,'winner_id',winner,'loser_id',loser,
    'status','completed','idempotent',FALSE);
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_request_swap_v1(p_target UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  requester public.beaver_queue_members%ROWTYPE;
  target public.beaver_queue_members%ROWTYPE;
  request_id UUID;
  requester_rank BIGINT;
  target_rank BIGINT;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  IF p_target IS NULL OR p_target=player_id THEN RAISE EXCEPTION 'Choose another waiting player'; END IF;
  PERFORM 1 FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  PERFORM public.beaver_queue_advance_internal_v1();
  SELECT * INTO requester FROM public.beaver_queue_members WHERE user_id=player_id;
  SELECT * INTO target FROM public.beaver_queue_members WHERE user_id=p_target;
  IF requester.status IS DISTINCT FROM 'waiting' OR target.status IS DISTINCT FROM 'waiting' THEN
    RAISE EXCEPTION 'Both players must still be waiting';
  END IF;
  IF target.queue_position>=requester.queue_position THEN
    RAISE EXCEPTION 'You can only request a swap with a player ahead of you';
  END IF;
  IF EXISTS(SELECT 1 FROM public.beaver_queue_swap_requests request
    WHERE request.status='pending' AND request.expires_at>clock_timestamp()
      AND (player_id IN(request.requester_id,request.target_id)
        OR p_target IN(request.requester_id,request.target_id))) THEN
    RAISE EXCEPTION 'One of these players already has a pending swap request';
  END IF;
  SELECT COUNT(*)+1 INTO requester_rank FROM public.beaver_queue_members member
  WHERE member.status='waiting' AND member.queue_position<requester.queue_position;
  SELECT COUNT(*)+1 INTO target_rank FROM public.beaver_queue_members member
  WHERE member.status='waiting' AND member.queue_position<target.queue_position;
  INSERT INTO public.beaver_queue_swap_requests(
    requester_id,target_id,requester_position,target_position,expires_at
  ) VALUES(player_id,p_target,requester_rank,target_rank,
    clock_timestamp()+INTERVAL '60 seconds') RETURNING id INTO request_id;
  RETURN jsonb_build_object('request_id',request_id,'status','pending');
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_respond_swap_v1(p_request UUID,p_action TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  normalized_action TEXT:=LOWER(BTRIM(COALESCE(p_action,'')));
  request public.beaver_queue_swap_requests%ROWTYPE;
  requester public.beaver_queue_members%ROWTYPE;
  target public.beaver_queue_members%ROWTYPE;
  temporary_position BIGINT;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  IF normalized_action NOT IN('accept','decline') THEN RAISE EXCEPTION 'Action must be accept or decline'; END IF;
  PERFORM 1 FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  PERFORM public.beaver_queue_advance_internal_v1();
  SELECT * INTO request FROM public.beaver_queue_swap_requests WHERE id=p_request FOR UPDATE;
  IF NOT FOUND OR request.target_id<>player_id THEN RAISE EXCEPTION 'Swap request is not available'; END IF;
  IF request.status<>'pending' THEN RAISE EXCEPTION 'Swap request is no longer available'; END IF;
  IF request.expires_at<=clock_timestamp() THEN
    UPDATE public.beaver_queue_swap_requests SET status='expired',responded_at=clock_timestamp() WHERE id=request.id;
    RAISE EXCEPTION 'Swap request has expired';
  END IF;

  SELECT * INTO requester FROM public.beaver_queue_members WHERE user_id=request.requester_id;
  SELECT * INTO target FROM public.beaver_queue_members WHERE user_id=request.target_id;
  IF requester.status IS DISTINCT FROM 'waiting' OR target.status IS DISTINCT FROM 'waiting' THEN
    UPDATE public.beaver_queue_swap_requests SET status='canceled',responded_at=clock_timestamp()
    WHERE id=request.id;
    RAISE EXCEPTION 'Both players must still be waiting';
  END IF;
  IF target.queue_position>=requester.queue_position THEN
    UPDATE public.beaver_queue_swap_requests SET status='canceled',responded_at=clock_timestamp()
    WHERE id=request.id;
    RAISE EXCEPTION 'Queue positions changed; request another swap';
  END IF;
  IF EXISTS(SELECT 1 FROM public.beaver_queue_swap_requests other
    WHERE other.id<>request.id AND other.status='pending' AND other.expires_at>clock_timestamp()
      AND (request.requester_id IN(other.requester_id,other.target_id)
        OR request.target_id IN(other.requester_id,other.target_id))) THEN
    RAISE EXCEPTION 'A conflicting swap request is pending';
  END IF;
  IF normalized_action='decline' THEN
    UPDATE public.beaver_queue_swap_requests SET status='declined',responded_at=clock_timestamp()
    WHERE id=request.id;
    RETURN jsonb_build_object('request_id',request.id,'status','declined');
  END IF;

  -- Normal queue positions are positive sequence values. Negating the next
  -- value provides a collision-free temporary slot even if a manually repaired
  -- database has a sequence that trails the current maximum position.
  temporary_position:=-nextval('public.beaver_queue_position_seq');
  UPDATE public.beaver_queue_members SET queue_position=temporary_position,updated_at=clock_timestamp()
  WHERE user_id=request.requester_id;
  UPDATE public.beaver_queue_members SET queue_position=requester.queue_position,updated_at=clock_timestamp()
  WHERE user_id=request.target_id;
  UPDATE public.beaver_queue_members SET queue_position=target.queue_position,updated_at=clock_timestamp()
  WHERE user_id=request.requester_id;
  UPDATE public.beaver_queue_swap_requests SET status='accepted',responded_at=clock_timestamp()
  WHERE id=request.id;
  RETURN jsonb_build_object('request_id',request.id,'status','accepted');
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_admin_correct_game_v1(
  p_game_id UUID,p_winner_id UUID,p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  game public.beaver_queue_games%ROWTYPE;
  admin_id UUID:=auth.uid();
  corrected_loser UUID;
  reason_text TEXT:=BTRIM(COALESCE(p_reason,''));
BEGIN
  IF admin_id IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Administrator access required'; END IF;
  IF LENGTH(reason_text) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'Correction reason is required'; END IF;
  SELECT * INTO game FROM public.beaver_queue_games WHERE id=p_game_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue game not found'; END IF;
  IF game.status<>'completed' THEN RAISE EXCEPTION 'Abandoned games cannot be assigned a winner'; END IF;
  IF p_winner_id NOT IN(game.king_id,game.challenger_id) THEN RAISE EXCEPTION 'Winner must be a game participant'; END IF;
  IF p_winner_id=game.winner_id THEN RAISE EXCEPTION 'That player is already the recorded winner'; END IF;
  corrected_loser:=CASE WHEN p_winner_id=game.king_id THEN game.challenger_id ELSE game.king_id END;
  INSERT INTO public.beaver_queue_game_corrections(
    game_id,old_winner_id,old_loser_id,new_winner_id,new_loser_id,corrected_by,reason
  ) VALUES(game.id,game.winner_id,game.loser_id,p_winner_id,corrected_loser,admin_id,reason_text);
  UPDATE public.beaver_queue_games SET winner_id=p_winner_id,loser_id=corrected_loser,
    corrected_at=clock_timestamp(),corrected_by=admin_id WHERE id=game.id;
  RETURN jsonb_build_object('game_id',game.id,'winner_id',p_winner_id,
    'loser_id',corrected_loser,'status','corrected');
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_health_v3()
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
    'version','20261103_03','initialized',state.id=1,'phase',state.phase,
    'member_status',my_status,
    'heartbeat_granted',has_function_privilege('authenticated','public.beaver_queue_heartbeat_v1()','EXECUTE'),
    'join_granted',has_function_privilege('authenticated','public.beaver_queue_join_v1()','EXECUTE'),
    'outcome_granted',has_function_privilege('authenticated','public.beaver_queue_report_outcome_v2(uuid,text)','EXECUTE'),
    'swap_request_granted',has_function_privilege('authenticated','public.beaver_queue_request_swap_v1(uuid)','EXECUTE'),
    'swap_response_granted',has_function_privilege('authenticated','public.beaver_queue_respond_swap_v1(uuid,text)','EXECUTE'),
    'swap_granted',
      has_function_privilege('authenticated','public.beaver_queue_request_swap_v1(uuid)','EXECUTE')
      AND has_function_privilege('authenticated','public.beaver_queue_respond_swap_v1(uuid,text)','EXECUTE')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.beaver_queue_cancel_invalid_swaps_internal_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_report_v1(UUID,INTEGER,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_report_outcome_v2(UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_request_swap_v1(UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_respond_swap_v1(UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_admin_correct_game_v1(UUID,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_health_v3() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.beaver_queue_report_outcome_v2(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_request_swap_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_respond_swap_v1(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_admin_correct_game_v1(UUID,UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_health_v3() TO authenticated;

DO $realtime$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime')
     AND NOT EXISTS(SELECT 1 FROM pg_publication_tables
       WHERE pubname='supabase_realtime' AND schemaname='public'
         AND tablename='beaver_queue_swap_requests') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.beaver_queue_swap_requests;
  END IF;
END;
$realtime$;

SELECT public.beaver_queue_advance_internal_v1();
NOTIFY pgrst,'reload schema';
COMMIT;
