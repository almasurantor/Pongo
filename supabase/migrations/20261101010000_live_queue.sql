-- Pongo experimental one-table live queue.
-- Completely independent from ranked matches, ratings, challenges, and stats.
BEGIN;

-- gen_random_uuid() is built into supported PostgreSQL versions; do not attempt
-- to reinstall pgcrypto from a later migration under the restricted CLI role.
CREATE SEQUENCE IF NOT EXISTS public.beaver_queue_position_seq;

CREATE TABLE IF NOT EXISTS public.beaver_queue_members (
  user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE RESTRICT,
  display_name TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('waiting','called','king','playing','left','no_show')),
  queue_position BIGINT NOT NULL DEFAULT nextval('public.beaver_queue_position_seq'),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS beaver_queue_position_unique
  ON public.beaver_queue_members(queue_position);
CREATE INDEX IF NOT EXISTS beaver_queue_waiting_order
  ON public.beaver_queue_members(queue_position)
  WHERE status='waiting';
CREATE UNIQUE INDEX IF NOT EXISTS beaver_queue_single_holder_and_call
  ON public.beaver_queue_members(status)
  WHERE status IN ('king','called');

CREATE TABLE IF NOT EXISTS public.beaver_queue_table (
  id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id=1),
  phase TEXT NOT NULL DEFAULT 'idle' CHECK (phase IN ('idle','called','playing')),
  king_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  challenger_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  call_expires_at TIMESTAMPTZ,
  game_id UUID,
  game_started_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT beaver_queue_distinct_players CHECK (
    king_id IS NULL OR challenger_id IS NULL OR king_id<>challenger_id
  ),
  CONSTRAINT beaver_queue_phase_consistent CHECK (
    (phase='idle' AND challenger_id IS NULL AND call_expires_at IS NULL
      AND game_id IS NULL AND game_started_at IS NULL)
    OR
    (phase='called' AND king_id IS NOT NULL AND challenger_id IS NOT NULL
      AND call_expires_at IS NOT NULL AND game_id IS NULL AND game_started_at IS NULL)
    OR
    (phase='playing' AND king_id IS NOT NULL AND challenger_id IS NOT NULL
      AND call_expires_at IS NULL AND game_id IS NOT NULL AND game_started_at IS NOT NULL)
  )
);

INSERT INTO public.beaver_queue_table(id) VALUES(1) ON CONFLICT(id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.beaver_queue_games (
  id UUID PRIMARY KEY,
  king_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  challenger_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  king_name TEXT NOT NULL,
  challenger_name TEXT NOT NULL,
  king_score SMALLINT NOT NULL CHECK (king_score BETWEEN 0 AND 99),
  challenger_score SMALLINT NOT NULL CHECK (challenger_score BETWEEN 0 AND 99),
  winner_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  reported_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT beaver_queue_game_players_distinct CHECK (king_id<>challenger_id),
  CONSTRAINT beaver_queue_winner_is_player CHECK (winner_id IN (king_id,challenger_id)),
  CONSTRAINT beaver_queue_game_score_valid CHECK (
    GREATEST(king_score,challenger_score)>=11
    AND ABS(king_score-challenger_score)>=2
    AND (
      GREATEST(king_score,challenger_score)=11
      OR ABS(king_score-challenger_score)=2
    )
  )
);

CREATE INDEX IF NOT EXISTS beaver_queue_recent_games
  ON public.beaver_queue_games(completed_at DESC);

ALTER TABLE public.beaver_queue_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.beaver_queue_table ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.beaver_queue_games ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.beaver_queue_members,public.beaver_queue_table,
  public.beaver_queue_games FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE public.beaver_queue_members,public.beaver_queue_table,
  public.beaver_queue_games TO authenticated;
REVOKE ALL ON SEQUENCE public.beaver_queue_position_seq FROM PUBLIC,anon,authenticated;

DROP POLICY IF EXISTS "Authenticated users read live queue members"
  ON public.beaver_queue_members;
CREATE POLICY "Authenticated users read live queue members"
  ON public.beaver_queue_members FOR SELECT TO authenticated
  USING(auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "Authenticated users read live queue state"
  ON public.beaver_queue_table;
CREATE POLICY "Authenticated users read live queue state"
  ON public.beaver_queue_table FOR SELECT TO authenticated
  USING(auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS "Authenticated users read queue game history"
  ON public.beaver_queue_games;
CREATE POLICY "Authenticated users read queue game history"
  ON public.beaver_queue_games FOR SELECT TO authenticated
  USING(auth.uid() IS NOT NULL);

-- Every queue mutation locks the singleton table row. That lock serializes
-- simultaneous joins, departures, confirmations, reports, and expiry ticks.
CREATE OR REPLACE FUNCTION public.beaver_queue_advance_internal_v1()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  state public.beaver_queue_table;
  next_player UUID;
BEGIN
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue table is not initialized'; END IF;

  IF state.phase='called' AND state.call_expires_at<=clock_timestamp() THEN
    UPDATE public.beaver_queue_members
    SET status='no_show',updated_at=clock_timestamp()
    WHERE user_id=state.challenger_id AND status='called';
    UPDATE public.beaver_queue_table SET
      phase='idle',challenger_id=NULL,call_expires_at=NULL,updated_at=clock_timestamp()
    WHERE id=1;
    SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
  END IF;

  IF state.phase<>'idle' THEN RETURN; END IF;

  IF state.king_id IS NULL THEN
    SELECT user_id INTO next_player
    FROM public.beaver_queue_members
    WHERE status='waiting'
    ORDER BY queue_position,user_id
    LIMIT 1 FOR UPDATE;
    IF next_player IS NOT NULL THEN
      UPDATE public.beaver_queue_members
      SET status='king',updated_at=clock_timestamp()
      WHERE user_id=next_player;
      UPDATE public.beaver_queue_table
      SET king_id=next_player,updated_at=clock_timestamp()
      WHERE id=1;
      state.king_id:=next_player;
    END IF;
  END IF;

  IF state.king_id IS NOT NULL THEN
    next_player:=NULL;
    SELECT user_id INTO next_player
    FROM public.beaver_queue_members
    WHERE status='waiting' AND user_id<>state.king_id
    ORDER BY queue_position,user_id
    LIMIT 1 FOR UPDATE;
    IF next_player IS NOT NULL THEN
      UPDATE public.beaver_queue_members
      SET status='called',updated_at=clock_timestamp()
      WHERE user_id=next_player;
      UPDATE public.beaver_queue_table SET
        phase='called',challenger_id=next_player,
        call_expires_at=clock_timestamp()+INTERVAL '60 seconds',
        updated_at=clock_timestamp()
      WHERE id=1;
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_tick_v1()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  PERFORM public.beaver_queue_advance_internal_v1();
END;
$$;

-- Trusted workers call this RPC so expired turns advance even when the called
-- player's browser is closed. Schedule it frequently with the service role.
CREATE OR REPLACE FUNCTION public.beaver_queue_advance_expired_v1()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
BEGIN
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

  SELECT status INTO current_status
  FROM public.beaver_queue_members WHERE user_id=player_id;
  IF current_status IN ('waiting','called','king','playing') THEN RETURN; END IF;

  SELECT LEFT(COALESCE(
    NULLIF(BTRIM(profile.display_name),''),
    NULLIF(BTRIM(account.raw_user_meta_data->>'display_name'),''),
    NULLIF(split_part(account.email,'@',1),''),
    'Player'
  ),40)
  INTO player_name
  FROM auth.users account
  LEFT JOIN public.profiles profile ON profile.id=account.id
  WHERE account.id=player_id;
  IF player_name IS NULL THEN RAISE EXCEPTION 'Player profile not found'; END IF;

  INSERT INTO public.beaver_queue_members(
    user_id,display_name,status,queue_position,joined_at,updated_at
  ) VALUES(
    player_id,player_name,'waiting',nextval('public.beaver_queue_position_seq'),
    clock_timestamp(),clock_timestamp()
  )
  ON CONFLICT(user_id) DO UPDATE SET
    display_name=EXCLUDED.display_name,status='waiting',
    queue_position=EXCLUDED.queue_position,joined_at=EXCLUDED.joined_at,
    updated_at=clock_timestamp();

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
  state public.beaver_queue_table;
  member_status TEXT;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  PERFORM public.beaver_queue_advance_internal_v1();
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
  SELECT status INTO member_status
  FROM public.beaver_queue_members WHERE user_id=player_id;

  IF member_status IS NULL OR member_status IN ('left','no_show') THEN RETURN; END IF;
  IF member_status='playing' THEN
    RAISE EXCEPTION 'A game is underway. Report the result before leaving.';
  END IF;

  UPDATE public.beaver_queue_members
  SET status='left',updated_at=clock_timestamp()
  WHERE user_id=player_id;

  IF player_id=state.king_id THEN
    IF state.challenger_id IS NOT NULL THEN
      UPDATE public.beaver_queue_members
      SET status='waiting',updated_at=clock_timestamp()
      WHERE user_id=state.challenger_id AND status='called';
    END IF;
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
  state public.beaver_queue_table;
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
  state public.beaver_queue_table;
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

  winner:=CASE WHEN p_king_score>p_challenger_score
    THEN state.king_id ELSE state.challenger_id END;
  loser:=CASE WHEN winner=state.king_id
    THEN state.challenger_id ELSE state.king_id END;
  SELECT display_name INTO holder_name
  FROM public.beaver_queue_members WHERE user_id=state.king_id;
  SELECT display_name INTO challenger_name
  FROM public.beaver_queue_members WHERE user_id=state.challenger_id;

  INSERT INTO public.beaver_queue_games(
    id,king_id,challenger_id,king_name,challenger_name,
    king_score,challenger_score,winner_id,reported_by
  ) VALUES(
    p_game_id,state.king_id,state.challenger_id,holder_name,challenger_name,
    p_king_score,p_challenger_score,winner,player_id
  );

  UPDATE public.beaver_queue_members
  SET status='left',updated_at=clock_timestamp() WHERE user_id=loser;
  UPDATE public.beaver_queue_members
  SET status='king',updated_at=clock_timestamp() WHERE user_id=winner;
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

REVOKE ALL ON FUNCTION public.beaver_queue_advance_internal_v1()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_tick_v1()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_advance_expired_v1()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_join_v1()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_leave_v1()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_confirm_v1()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_report_v1(UUID,INTEGER,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.beaver_queue_tick_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_join_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_leave_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_confirm_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_report_v1(UUID,INTEGER,INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_advance_expired_v1() TO service_role;

DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN
    IF NOT EXISTS(
      SELECT 1 FROM pg_publication_tables
      WHERE pubname='supabase_realtime' AND schemaname='public'
        AND tablename='beaver_queue_table'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.beaver_queue_table;
    END IF;
    IF NOT EXISTS(
      SELECT 1 FROM pg_publication_tables
      WHERE pubname='supabase_realtime' AND schemaname='public'
        AND tablename='beaver_queue_members'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.beaver_queue_members;
    END IF;
    IF NOT EXISTS(
      SELECT 1 FROM pg_publication_tables
      WHERE pubname='supabase_realtime' AND schemaname='public'
        AND tablename='beaver_queue_games'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.beaver_queue_games;
    END IF;
  END IF;
END;
$$;

-- Make newly-created queue RPCs visible to PostgREST immediately after the
-- migration commits instead of waiting for its schema cache to refresh.
NOTIFY pgrst, 'reload schema';

COMMIT;
