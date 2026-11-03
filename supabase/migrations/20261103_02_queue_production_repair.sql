-- Production queue repair.
--
-- Fixes the heartbeat/realtime feedback-loop fallout without weakening RLS:
-- every mutation remains a SECURITY DEFINER RPC serialized by the singleton
-- queue-table row. This migration is retry-safe and preserves ranked matches,
-- challenges, limits, ratings, and queue game history.
BEGIN;

DO $dependencies$
BEGIN
  IF to_regclass('public.beaver_queue_table') IS NULL
     OR to_regclass('public.beaver_queue_members') IS NULL
     OR to_regclass('public.beaver_queue_games') IS NULL
     OR to_regclass('public.beaver_queue_position_seq') IS NULL THEN
    RAISE EXCEPTION 'Missing dependency: apply 20261101_01_live_queue.sql before 20261103_02_queue_production_repair.sql';
  END IF;
  IF to_regprocedure('public.beaver_queue_join_v1()') IS NULL
     OR to_regprocedure('public.beaver_queue_leave_v1()') IS NULL THEN
    RAISE EXCEPTION 'Missing queue RPCs: apply 20261101_01_live_queue.sql first';
  END IF;
END;
$dependencies$;

-- Some production databases have the queue objects but are missing the
-- singleton state row (for example, after an interrupted or manually applied
-- base migration). Repair that state before any RPC or cleanup can lock it.
INSERT INTO public.beaver_queue_table(id)
VALUES(1)
ON CONFLICT(id) DO NOTHING;

CREATE INDEX IF NOT EXISTS beaver_queue_active_heartbeat_v2
  ON public.beaver_queue_members(updated_at)
  WHERE status IN ('waiting','called','king');

ALTER TABLE public.beaver_queue_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.beaver_queue_table ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.beaver_queue_games ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.beaver_queue_members,public.beaver_queue_table,
  public.beaver_queue_games FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE public.beaver_queue_members,public.beaver_queue_table,
  public.beaver_queue_games TO authenticated;
REVOKE ALL ON SEQUENCE public.beaver_queue_position_seq FROM PUBLIC,anon,authenticated;

DROP POLICY IF EXISTS "Authenticated users read live queue members" ON public.beaver_queue_members;
CREATE POLICY "Authenticated users read live queue members"
  ON public.beaver_queue_members FOR SELECT TO authenticated
  USING(auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "Authenticated users read live queue state" ON public.beaver_queue_table;
CREATE POLICY "Authenticated users read live queue state"
  ON public.beaver_queue_table FOR SELECT TO authenticated
  USING(auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "Authenticated users read queue game history" ON public.beaver_queue_games;
CREATE POLICY "Authenticated users read queue game history"
  ON public.beaver_queue_games FOR SELECT TO authenticated
  USING(auth.uid() IS NOT NULL);

-- All public queue mutations acquire this row before touching member rows.
-- That consistent lock order prevents join/leave/heartbeat races and makes a
-- duplicate join an idempotent no-op.
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
BEGIN
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue table is not initialized'; END IF;

  -- A playing game is never expired by presence. Its real score must be
  -- reported by a participant, preserving the existing scoring rules.
  IF state.phase='playing' THEN
    UPDATE public.beaver_queue_members
    SET status='left',updated_at=clock_timestamp()
    WHERE status='waiting' AND updated_at<clock_timestamp()-INTERVAL '2 minutes';
    RETURN;
  END IF;

  IF state.king_id IS NOT NULL THEN
    SELECT member.updated_at<clock_timestamp()-INTERVAL '2 minutes'
      INTO king_is_stale
    FROM public.beaver_queue_members member
    WHERE member.user_id=state.king_id AND member.status='king';

    IF COALESCE(king_is_stale,TRUE) THEN
      UPDATE public.beaver_queue_members
      SET status='left',updated_at=clock_timestamp()
      WHERE user_id=state.king_id AND status='king';
      UPDATE public.beaver_queue_members
      SET status='waiting',updated_at=clock_timestamp()
      WHERE user_id=state.challenger_id AND status='called';
      UPDATE public.beaver_queue_table SET
        phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
        game_id=NULL,game_started_at=NULL,updated_at=clock_timestamp()
      WHERE id=1;
      SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
    END IF;
  END IF;

  IF state.phase='called' AND state.call_expires_at<=clock_timestamp() THEN
    UPDATE public.beaver_queue_members
    SET status='no_show',updated_at=clock_timestamp()
    WHERE user_id=state.challenger_id AND status='called';
    UPDATE public.beaver_queue_table SET
      phase='idle',challenger_id=NULL,call_expires_at=NULL,updated_at=clock_timestamp()
    WHERE id=1;
    SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
  END IF;

  UPDATE public.beaver_queue_members
  SET status='left',updated_at=clock_timestamp()
  WHERE status='waiting' AND updated_at<clock_timestamp()-INTERVAL '2 minutes';

  IF state.phase<>'idle' THEN RETURN; END IF;

  IF state.king_id IS NULL THEN
    SELECT member.user_id INTO next_player
    FROM public.beaver_queue_members member
    WHERE member.status='waiting'
    ORDER BY member.queue_position,member.user_id
    LIMIT 1;
    IF next_player IS NOT NULL THEN
      UPDATE public.beaver_queue_members
      SET status='king',updated_at=clock_timestamp()
      WHERE user_id=next_player AND status='waiting';
      UPDATE public.beaver_queue_table
      SET king_id=next_player,updated_at=clock_timestamp()
      WHERE id=1;
      state.king_id:=next_player;
    END IF;
  END IF;

  IF state.king_id IS NOT NULL THEN
    next_player:=NULL;
    SELECT member.user_id INTO next_player
    FROM public.beaver_queue_members member
    WHERE member.status='waiting' AND member.user_id<>state.king_id
    ORDER BY member.queue_position,member.user_id
    LIMIT 1;
    IF next_player IS NOT NULL THEN
      UPDATE public.beaver_queue_members
      SET status='called',updated_at=clock_timestamp()
      WHERE user_id=next_player AND status='waiting';
      UPDATE public.beaver_queue_table SET
        phase='called',challenger_id=next_player,
        call_expires_at=clock_timestamp()+INTERVAL '60 seconds',
        updated_at=clock_timestamp()
      WHERE id=1;
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
DECLARE
  player_id UUID:=auth.uid();
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  PERFORM 1 FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  UPDATE public.beaver_queue_members
  SET updated_at=clock_timestamp()
  WHERE user_id=player_id AND status IN ('waiting','called','king','playing');
  PERFORM public.beaver_queue_advance_internal_v1();
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_join_v1()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  player_name TEXT;
  current_status TEXT;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  PERFORM 1 FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  PERFORM public.beaver_queue_advance_internal_v1();

  SELECT member.status INTO current_status
  FROM public.beaver_queue_members member WHERE member.user_id=player_id;
  IF current_status IN ('waiting','called','king','playing') THEN RETURN; END IF;

  -- Profiles are the app's public identity source. Avoid depending on direct
  -- auth.users reads from a browser-facing RPC.
  SELECT LEFT(BTRIM(profile.display_name),40) INTO player_name
  FROM public.profiles profile WHERE profile.id=player_id;
  IF player_name IS NULL OR player_name='' THEN
    RAISE EXCEPTION 'Player profile not found';
  END IF;

  INSERT INTO public.beaver_queue_members(
    user_id,display_name,status,queue_position,joined_at,updated_at
  ) VALUES(
    player_id,player_name,'waiting',nextval('public.beaver_queue_position_seq'),
    clock_timestamp(),clock_timestamp()
  )
  ON CONFLICT(user_id) DO UPDATE SET
    display_name=EXCLUDED.display_name,status='waiting',
    queue_position=EXCLUDED.queue_position,joined_at=EXCLUDED.joined_at,
    updated_at=EXCLUDED.updated_at;

  PERFORM public.beaver_queue_advance_internal_v1();
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
  SELECT member.status INTO member_status
  FROM public.beaver_queue_members member WHERE member.user_id=player_id;

  IF member_status IS NULL OR member_status IN ('left','no_show') THEN RETURN; END IF;
  IF member_status='playing' THEN
    RAISE EXCEPTION 'A game is underway. Report the result before leaving.';
  END IF;

  UPDATE public.beaver_queue_members
  SET status='left',updated_at=clock_timestamp()
  WHERE user_id=player_id;

  IF player_id=state.king_id THEN
    UPDATE public.beaver_queue_members
    SET status='waiting',updated_at=clock_timestamp()
    WHERE user_id=state.challenger_id AND status='called';
    UPDATE public.beaver_queue_table SET
      phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
      game_id=NULL,game_started_at=NULL,updated_at=clock_timestamp()
    WHERE id=1;
  ELSIF player_id=state.challenger_id THEN
    UPDATE public.beaver_queue_table SET
      phase='idle',challenger_id=NULL,call_expires_at=NULL,updated_at=clock_timestamp()
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
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  PERFORM 1 FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  PERFORM public.beaver_queue_advance_internal_v1();
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
  IF state.phase<>'called' OR state.challenger_id IS DISTINCT FROM player_id
     OR state.call_expires_at<=clock_timestamp() THEN
    RAISE EXCEPTION 'Your 60-second check-in is no longer available';
  END IF;

  UPDATE public.beaver_queue_members
  SET status='playing',updated_at=clock_timestamp()
  WHERE user_id IN (state.king_id,state.challenger_id);
  UPDATE public.beaver_queue_table SET
    phase='playing',game_id=gen_random_uuid(),game_started_at=clock_timestamp(),
    call_expires_at=NULL,updated_at=clock_timestamp()
  WHERE id=1;
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_report_v1(
  p_game_id UUID,p_king_score INTEGER,p_challenger_score INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  state public.beaver_queue_table%ROWTYPE;
  winner UUID;
  loser UUID;
  holder_name TEXT;
  challenger_name TEXT;
  high_score INTEGER;
  low_score INTEGER;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  IF state.phase<>'playing' OR state.game_id IS DISTINCT FROM p_game_id THEN
    RAISE EXCEPTION 'This game is no longer active. Refresh the queue.';
  END IF;
  IF player_id IS DISTINCT FROM state.king_id
     AND player_id IS DISTINCT FROM state.challenger_id THEN
    RAISE EXCEPTION 'Only players in this game can report the score';
  END IF;
  IF p_king_score IS NULL OR p_challenger_score IS NULL THEN
    RAISE EXCEPTION 'Both scores are required';
  END IF;
  high_score:=GREATEST(p_king_score,p_challenger_score);
  low_score:=LEAST(p_king_score,p_challenger_score);
  IF low_score<0 OR high_score>99 OR high_score<11 OR high_score-low_score<2
     OR (high_score>11 AND (low_score<10 OR high_score-low_score<>2)) THEN
    RAISE EXCEPTION 'Invalid table-tennis score; win by 2, first to 11, deuce allowed';
  END IF;

  winner:=CASE WHEN p_king_score>p_challenger_score THEN state.king_id ELSE state.challenger_id END;
  loser:=CASE WHEN winner=state.king_id THEN state.challenger_id ELSE state.king_id END;
  SELECT display_name INTO holder_name FROM public.beaver_queue_members WHERE user_id=state.king_id;
  SELECT display_name INTO challenger_name FROM public.beaver_queue_members WHERE user_id=state.challenger_id;

  INSERT INTO public.beaver_queue_games(
    id,king_id,challenger_id,king_name,challenger_name,
    king_score,challenger_score,winner_id,reported_by
  ) VALUES(
    p_game_id,state.king_id,state.challenger_id,holder_name,challenger_name,
    p_king_score,p_challenger_score,winner,player_id
  );

  UPDATE public.beaver_queue_members SET status='left',updated_at=clock_timestamp() WHERE user_id=loser;
  UPDATE public.beaver_queue_members SET status='king',updated_at=clock_timestamp() WHERE user_id=winner;
  UPDATE public.beaver_queue_table SET
    phase='idle',king_id=winner,challenger_id=NULL,call_expires_at=NULL,
    game_id=NULL,game_started_at=NULL,updated_at=clock_timestamp()
  WHERE id=1;
  PERFORM public.beaver_queue_advance_internal_v1();
  RETURN jsonb_build_object(
    'game_id',p_game_id,'winner_id',winner,'loser_id',loser,'status','completed'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_health_v2()
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
    'version','20261103_02','initialized',state.id=1,'phase',state.phase,
    'member_status',my_status,'heartbeat_granted',
      has_function_privilege('authenticated','public.beaver_queue_heartbeat_v1()','EXECUTE'),
    'join_granted',has_function_privilege('authenticated','public.beaver_queue_join_v1()','EXECUTE')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.beaver_queue_advance_internal_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_heartbeat_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_join_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_leave_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_confirm_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_report_v1(UUID,INTEGER,INTEGER) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_health_v2() FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.beaver_queue_heartbeat_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_join_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_leave_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_confirm_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_report_v1(UUID,INTEGER,INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_health_v2() TO authenticated;

DO $realtime$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN
    IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='beaver_queue_table') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.beaver_queue_table;
    END IF;
    IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='beaver_queue_members') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.beaver_queue_members;
    END IF;
    IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='beaver_queue_games') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.beaver_queue_games;
    END IF;
  END IF;
END;
$realtime$;

-- Clean up expired waiting/called/holder state immediately after deployment.
SELECT public.beaver_queue_advance_internal_v1();
NOTIFY pgrst,'reload schema';
COMMIT;
