-- One-shot live queue overtime and Unicode display names.
-- The existing 10-second queue worker remains the only required scheduler.
BEGIN;

DO $dependencies$
BEGIN
  IF to_regprocedure('public.beaver_queue_health_v9()') IS NULL
     OR to_regprocedure('public.run_pongo_queue_maintenance_v1()') IS NULL
     OR to_regprocedure('public.update_my_profile_settings_v4(text,boolean,boolean)') IS NULL THEN
    RAISE EXCEPTION 'Missing dependency: apply Pongo migrations through 20261104_10 first';
  END IF;
END;
$dependencies$;

-- ---------------------------------------------------------------------------
-- Unicode display names: 1-20 Unicode code points and at least one letter.
-- PostgreSQL's locale-aware POSIX alpha class is the database equivalent of
-- JavaScript's /\p{L}/u check.
-- ---------------------------------------------------------------------------

DO $repair_legacy_names_without_letters$
DECLARE
  player RECORD;
  base_name TEXT;
  candidate TEXT;
  suffix INTEGER;
  suffix_text TEXT;
BEGIN
  FOR player IN
    SELECT id,display_name
    FROM public.profiles
    WHERE display_name !~ '[[:alpha:]]'
    ORDER BY created_at,id
  LOOP
    base_name:=LEFT('Player '||BTRIM(player.display_name),20);
    candidate:=base_name;
    suffix:=2;
    WHILE EXISTS(
      SELECT 1 FROM public.profiles existing
      WHERE existing.id<>player.id AND LOWER(existing.display_name)=LOWER(candidate)
    ) LOOP
      suffix_text:=' '||suffix::TEXT;
      candidate:=LEFT(base_name,20-CHAR_LENGTH(suffix_text))||suffix_text;
      suffix:=suffix+1;
    END LOOP;
    UPDATE public.profiles SET display_name=candidate WHERE id=player.id;
  END LOOP;
END;
$repair_legacy_names_without_letters$;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_display_name_check,
  DROP CONSTRAINT IF EXISTS profiles_display_name_v4_check,
  DROP CONSTRAINT IF EXISTS profiles_display_name_v5_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_display_name_v5_check CHECK(
  display_name=BTRIM(display_name)
  AND CHAR_LENGTH(display_name) BETWEEN 1 AND 20
  AND display_name ~ '[[:alpha:]]'
);

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  requested_name TEXT:=BTRIM(COALESCE(NEW.raw_user_meta_data->>'display_name',''));
  base_name TEXT;
  candidate TEXT;
  suffix INTEGER:=2;
  suffix_text TEXT;
BEGIN
  IF requested_name<>'' THEN
    IF CHAR_LENGTH(requested_name) NOT BETWEEN 1 AND 20
       OR requested_name !~ '[[:alpha:]]' THEN
      RAISE EXCEPTION 'Display name must be 1-20 characters and include at least one letter';
    END IF;
    base_name:=requested_name;
  ELSE
    base_name:=BTRIM(COALESCE(
      NULLIF(NEW.raw_user_meta_data->>'full_name',''),
      NULLIF(SPLIT_PART(NEW.email,'@',1),''),
      ''
    ));
    IF CHAR_LENGTH(base_name) NOT BETWEEN 1 AND 20
       OR base_name !~ '[[:alpha:]]' THEN
      base_name:='Player '||SUBSTRING(REPLACE(NEW.id::TEXT,'-','') FROM 1 FOR 8);
    END IF;
  END IF;
  candidate:=base_name;

  LOOP
    BEGIN
      INSERT INTO public.profiles(
        id,display_name,current_elo,highest_elo,total_wins,total_losses,
        weekly_wins,weekly_losses,current_streak,longest_streak
      ) VALUES(NEW.id,candidate,50,50,0,0,0,0,0,0)
      ON CONFLICT(id) DO NOTHING;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      suffix_text:=' '||suffix::TEXT;
      candidate:=LEFT(base_name,20-CHAR_LENGTH(suffix_text))||suffix_text;
      suffix:=suffix+1;
    END;
  END LOOP;

  INSERT INTO public.player_integrity(player_id)
  VALUES(NEW.id) ON CONFLICT(player_id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_display_name_available_v4(p_name TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  normalized TEXT:=BTRIM(COALESCE(p_name,''));
  valid BOOLEAN;
  available BOOLEAN:=FALSE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  valid:=CHAR_LENGTH(normalized) BETWEEN 1 AND 20
    AND normalized ~ '[[:alpha:]]';
  IF valid THEN
    available:=NOT EXISTS(
      SELECT 1 FROM public.profiles profile
      WHERE LOWER(profile.display_name)=LOWER(normalized)
        AND profile.id<>auth.uid()
    );
  END IF;
  RETURN jsonb_build_object(
    'normalized',normalized,
    'valid',valid,
    'available',available
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.update_my_profile_settings_v4(
  p_display_name TEXT,
  p_queue_turn_sound_enabled BOOLEAN,
  p_queue_turn_push_enabled BOOLEAN
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  normalized TEXT:=BTRIM(COALESCE(p_display_name,''));
  updated public.profiles;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  IF CHAR_LENGTH(normalized) NOT BETWEEN 1 AND 20
     OR normalized !~ '[[:alpha:]]' THEN
    RAISE EXCEPTION 'Display name must be 1-20 characters and include at least one letter';
  END IF;
  IF EXISTS(
    SELECT 1 FROM public.profiles profile
    WHERE LOWER(profile.display_name)=LOWER(normalized)
      AND profile.id<>player_id
  ) THEN RAISE EXCEPTION 'Name already taken'; END IF;

  BEGIN
    UPDATE public.profiles SET
      display_name=normalized,
      queue_turn_sound_enabled=COALESCE(p_queue_turn_sound_enabled,TRUE),
      queue_turn_push_enabled=COALESCE(p_queue_turn_push_enabled,FALSE),
      updated_at=clock_timestamp()
    WHERE id=player_id
    RETURNING * INTO updated;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Name already taken';
  END;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

  UPDATE auth.users SET
    raw_user_meta_data=jsonb_set(
      COALESCE(raw_user_meta_data,'{}'::JSONB),'{display_name}',to_jsonb(normalized),TRUE
    ),
    updated_at=clock_timestamp()
  WHERE id=player_id;

  UPDATE public.beaver_queue_members
  SET display_name=normalized,updated_at=clock_timestamp()
  WHERE user_id=player_id;
  RETURN updated;
END;
$$;

-- ---------------------------------------------------------------------------
-- Match overtime. The initial game deadline starts a 60-second decision
-- window. One approval changes the same authoritative deadline to now + 2m.
-- ---------------------------------------------------------------------------

ALTER TABLE public.beaver_queue_table
  ADD COLUMN IF NOT EXISTS overtime_prompt_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS overtime_used BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE public.beaver_queue_table
SET overtime_prompt_expires_at=game_expires_at+INTERVAL '60 seconds',
    overtime_used=FALSE
WHERE phase='playing' AND overtime_prompt_expires_at IS NULL;
UPDATE public.beaver_queue_table
SET overtime_prompt_expires_at=NULL,overtime_used=FALSE
WHERE phase<>'playing';

CREATE OR REPLACE FUNCTION public.beaver_queue_prepare_overtime_v1()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path=''
AS $$
BEGIN
  IF NEW.phase='playing' AND NEW.game_id IS NOT NULL THEN
    IF OLD.phase IS DISTINCT FROM 'playing'
       OR OLD.game_id IS DISTINCT FROM NEW.game_id THEN
      NEW.overtime_used:=FALSE;
      NEW.overtime_prompt_expires_at:=NEW.game_expires_at+INTERVAL '60 seconds';
    ELSIF NEW.overtime_used THEN
      NEW.overtime_prompt_expires_at:=NULL;
    END IF;
  ELSE
    NEW.overtime_used:=FALSE;
    NEW.overtime_prompt_expires_at:=NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS beaver_queue_prepare_overtime_v1 ON public.beaver_queue_table;
CREATE TRIGGER beaver_queue_prepare_overtime_v1
BEFORE UPDATE OF phase,game_id,game_expires_at,overtime_used,overtime_prompt_expires_at
ON public.beaver_queue_table
FOR EACH ROW
EXECUTE FUNCTION public.beaver_queue_prepare_overtime_v1();

ALTER TABLE public.beaver_queue_table
  DROP CONSTRAINT IF EXISTS beaver_queue_overtime_state_v1;
ALTER TABLE public.beaver_queue_table ADD CONSTRAINT beaver_queue_overtime_state_v1 CHECK(
  (phase='playing' AND (
    (overtime_used=FALSE AND overtime_prompt_expires_at IS NOT NULL)
    OR (overtime_used=TRUE AND overtime_prompt_expires_at IS NULL)
  ))
  OR (phase<>'playing' AND overtime_used=FALSE AND overtime_prompt_expires_at IS NULL)
);

CREATE OR REPLACE FUNCTION public.beaver_queue_expire_game_internal_v1(p_game_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  state public.beaver_queue_table%ROWTYPE;
  holder_name TEXT;
  next_name TEXT;
BEGIN
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  IF state.phase<>'playing' OR state.game_id IS DISTINCT FROM p_game_id THEN
    RETURN FALSE;
  END IF;
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
  WHERE id=1 AND phase='playing' AND game_id=p_game_id;
  RETURN FOUND;
END;
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
  surviving_player UUID;
  king_is_stale BOOLEAN:=FALSE;
  holder_name TEXT;
  next_name TEXT;
  authoritative_game_deadline TIMESTAMPTZ;
BEGIN
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue table is not initialized'; END IF;
  PERFORM public.beaver_queue_cancel_invalid_swaps_internal_v1();

  IF state.phase='playing' THEN
    authoritative_game_deadline:=CASE
      WHEN state.overtime_used THEN state.game_expires_at
      ELSE state.overtime_prompt_expires_at
    END;
    IF state.afk_expires_at IS NOT NULL
       AND state.afk_expires_at<=clock_timestamp()
       AND state.afk_expires_at<=authoritative_game_deadline THEN
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
    ELSIF authoritative_game_deadline<=clock_timestamp() THEN
      PERFORM public.beaver_queue_expire_game_internal_v1(state.game_id);
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

CREATE OR REPLACE FUNCTION public.beaver_queue_overtime_v1(p_game_id UUID,p_action TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  normalized_action TEXT:=LOWER(BTRIM(COALESCE(p_action,'')));
  state public.beaver_queue_table%ROWTYPE;
  existing public.beaver_queue_games%ROWTYPE;
  extended_until TIMESTAMPTZ;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  IF normalized_action NOT IN('extend','end') THEN
    RAISE EXCEPTION 'Overtime action must be extend or end';
  END IF;

  PERFORM 1 FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  PERFORM public.beaver_queue_advance_internal_v1();
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;

  IF state.phase<>'playing' OR state.game_id IS DISTINCT FROM p_game_id THEN
    SELECT * INTO existing FROM public.beaver_queue_games WHERE id=p_game_id;
    IF FOUND AND player_id IN(existing.king_id,existing.challenger_id)
       AND existing.status='abandoned' THEN
      RETURN jsonb_build_object('game_id',p_game_id,'status','expired','idempotent',TRUE);
    END IF;
    RAISE EXCEPTION 'This queue match is no longer active';
  END IF;
  IF player_id NOT IN(state.king_id,state.challenger_id) THEN
    RAISE EXCEPTION 'Only players in this game can decide overtime';
  END IF;
  IF state.overtime_used THEN
    RETURN jsonb_build_object(
      'game_id',state.game_id,'status','extended',
      'game_expires_at',state.game_expires_at,'idempotent',TRUE
    );
  END IF;
  IF state.game_expires_at>clock_timestamp() THEN
    RAISE EXCEPTION 'Overtime is not available before the ten-minute deadline';
  END IF;

  IF normalized_action='end' THEN
    PERFORM public.beaver_queue_expire_game_internal_v1(state.game_id);
    PERFORM public.beaver_queue_advance_internal_v1();
    RETURN jsonb_build_object('game_id',p_game_id,'status','expired','idempotent',FALSE);
  END IF;

  extended_until:=clock_timestamp()+INTERVAL '2 minutes';
  UPDATE public.beaver_queue_table SET
    overtime_used=TRUE,
    overtime_prompt_expires_at=NULL,
    game_expires_at=extended_until,
    updated_at=clock_timestamp()
  WHERE id=1 AND phase='playing' AND game_id=p_game_id AND overtime_used=FALSE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The overtime decision changed. Refresh the queue.';
  END IF;
  RETURN jsonb_build_object(
    'game_id',p_game_id,'status','extended',
    'game_expires_at',extended_until,'idempotent',FALSE
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_health_v10()
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
    'version','20261106_01','initialized',state.id=1,'phase',state.phase,
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
      AND has_function_privilege('authenticated','public.beaver_queue_respond_ranked_v1(uuid,text)','EXECUTE')
      AND has_function_privilege('authenticated','public.beaver_queue_submit_ranked_result_v1(uuid,uuid,integer,integer)','EXECUTE'),
    'ranked_requests_ready',to_regclass('public.beaver_queue_ranked_requests') IS NOT NULL,
    'holder_presence_trigger',EXISTS(
      SELECT 1 FROM pg_catalog.pg_trigger trigger_row
      WHERE trigger_row.tgrelid='public.beaver_queue_table'::regclass
        AND trigger_row.tgname='beaver_queue_autoconfirm_holder_v1'
        AND NOT trigger_row.tgisinternal
    ),
    'overtime_granted',has_function_privilege(
      'authenticated','public.beaver_queue_overtime_v1(uuid,text)','EXECUTE'
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.pongo_queue_maintenance_health_v1()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT jsonb_build_object(
    'healthy',state.last_succeeded_at IS NOT NULL
      AND state.last_succeeded_at>clock_timestamp()-INTERVAL '30 seconds',
    'last_succeeded_at',state.last_succeeded_at,
    'seconds_since_success',CASE WHEN state.last_succeeded_at IS NULL THEN NULL
      ELSE EXTRACT(EPOCH FROM clock_timestamp()-state.last_succeeded_at)::INTEGER END,
    'overdue_queue_deadline',EXISTS(
      SELECT 1 FROM public.beaver_queue_table queue
      WHERE queue.id=1 AND (
        queue.solo_expires_at<=clock_timestamp()
        OR queue.call_expires_at<=clock_timestamp()
        OR queue.afk_expires_at<=clock_timestamp()
        OR (queue.phase='playing' AND queue.overtime_used
          AND queue.game_expires_at<=clock_timestamp())
        OR (queue.phase='playing' AND NOT queue.overtime_used
          AND queue.overtime_prompt_expires_at<=clock_timestamp())
      )
    )
  )
  FROM public.pongo_maintenance_state state
  WHERE state.task='queue'
$$;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.check_display_name_available_v4(TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.update_my_profile_settings_v4(TEXT,BOOLEAN,BOOLEAN) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.check_display_name_available_v4(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_my_profile_settings_v4(TEXT,BOOLEAN,BOOLEAN) TO authenticated;

REVOKE ALL ON FUNCTION public.beaver_queue_prepare_overtime_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_expire_game_internal_v1(UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_overtime_v1(UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_health_v10() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.beaver_queue_overtime_v1(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_health_v10() TO authenticated;

SELECT public.beaver_queue_advance_internal_v1();
NOTIFY pgrst,'reload schema';
COMMIT;
