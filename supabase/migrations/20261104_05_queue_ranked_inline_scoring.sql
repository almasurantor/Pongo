-- Queue V9: keep mutually accepted Ranked games at the live table for inline
-- score entry. The original queue deadline remains authoritative.
BEGIN;

DO $dependencies$
BEGIN
  IF to_regprocedure('public.beaver_queue_health_v8()') IS NULL
     OR to_regprocedure('public.beaver_queue_respond_ranked_v1(uuid,text)') IS NULL
     OR to_regprocedure('public.submit_match_report_v2(uuid,uuid,integer,integer)') IS NULL THEN
    RAISE EXCEPTION 'Missing dependency: apply 20261104_04_queue_ranked_matches.sql first';
  END IF;
END;
$dependencies$;

-- A queue transition cancels unanswered requests. If both players had already
-- agreed but no valid score finalized, the linked ranked match is voided. This
-- runs for the normal ten-minute timeout, AFK removal, and administrative
-- repairs, so an abandoned queue game can never remain reportable as Ranked.
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

    UPDATE public.match_cancellation_requests cancellation
    SET status='expired',responded_at=clock_timestamp()
    WHERE cancellation.status='pending'
      AND EXISTS(
        SELECT 1 FROM public.beaver_queue_ranked_requests request
        WHERE request.queue_game_id=OLD.game_id
          AND request.status='accepted'
          AND request.match_id=cancellation.match_id
      );
    UPDATE public.matches ranked_match
    SET status='voided',finalized_at=clock_timestamp(),expires_at=NULL
    WHERE ranked_match.status IN('ready','canceled','expired')
      AND EXISTS(
        SELECT 1 FROM public.beaver_queue_ranked_requests request
        WHERE request.queue_game_id=OLD.game_id
          AND request.status='accepted'
          AND request.match_id=ranked_match.id
      );
  END IF;
  RETURN NEW;
END;
$$;

-- Agreement now creates the normal ranked match but intentionally leaves both
-- players and the live-table timer untouched. Score reporting or the timer is
-- responsible for the eventual atomic handoff.
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
      'queue_game_id',request.queue_game_id,'idempotent',TRUE
    );
  END IF;
  IF request.status<>'pending' THEN
    RAISE EXCEPTION 'Ranked request is no longer available';
  END IF;
  IF state.phase<>'playing' OR state.game_id IS DISTINCT FROM request.queue_game_id
     OR state.king_id NOT IN(request.requester_id,request.opponent_id)
     OR state.challenger_id NOT IN(request.requester_id,request.opponent_id) THEN
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
  RETURN jsonb_build_object(
    'request_id',request.id,'status','accepted','match_id',ranked_match.id,
    'queue_game_id',request.queue_game_id,'expires_at',ranked_match.expires_at,
    'ranked_day',ranked_match.ranked_day,'idempotent',FALSE
  );
END;
$$;

-- Use the existing ranked score validator/finalizer, then clear both queue
-- players only after that shared lifecycle confirms (or closes) the result.
CREATE OR REPLACE FUNCTION public.beaver_queue_submit_ranked_result_v1(
  p_match UUID,
  p_winner UUID,
  p_winner_score INTEGER,
  p_loser_score INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  state public.beaver_queue_table%ROWTYPE;
  request public.beaver_queue_ranked_requests%ROWTYPE;
  result JSONB;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue table is not initialized'; END IF;
  SELECT * INTO request FROM public.beaver_queue_ranked_requests
  WHERE match_id=p_match FOR UPDATE;
  IF NOT FOUND OR request.status<>'accepted'
     OR player_id NOT IN(request.requester_id,request.opponent_id) THEN
    RAISE EXCEPTION 'Ranked queue match is not available';
  END IF;
  IF state.phase<>'playing' OR state.game_id IS DISTINCT FROM request.queue_game_id
     OR state.king_id NOT IN(request.requester_id,request.opponent_id)
     OR state.challenger_id NOT IN(request.requester_id,request.opponent_id) THEN
    RAISE EXCEPTION 'This Ranked queue match is no longer active';
  END IF;
  IF state.game_expires_at<=clock_timestamp()
     OR (state.afk_expires_at IS NOT NULL AND state.afk_expires_at<=clock_timestamp()) THEN
    RAISE EXCEPTION 'The ten-minute score deadline has expired. Refresh the queue.';
  END IF;

  -- The status trigger below allows a queue-linked Ranked confirmation only
  -- while this wrapper owns the queue row and will perform the handoff in the
  -- same transaction.
  PERFORM pg_catalog.set_config('pongo.queue_ranked_match_id',p_match::TEXT,TRUE);
  SELECT public.submit_match_report_v2(
    p_match,p_winner,p_winner_score,p_loser_score
  ) INTO result;

  IF result->>'status' IN('confirmed','expired') THEN
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
    IF NOT FOUND THEN RAISE EXCEPTION 'The queue match changed during score finalization'; END IF;
    PERFORM public.beaver_queue_advance_internal_v1();
  END IF;
  RETURN result||jsonb_build_object('queue_game_id',request.queue_game_id);
END;
$$;

-- submit_match_report_v2 remains callable for ordinary Ranked matches. Bind
-- queue-linked confirmations to the wrapper above so a direct call cannot
-- update ELO while leaving either player stuck or duplicated in the queue.
CREATE OR REPLACE FUNCTION public.beaver_queue_require_ranked_handoff_v1()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path=''
AS $$
BEGIN
  IF NEW.status='confirmed' AND OLD.status IS DISTINCT FROM 'confirmed'
     AND EXISTS(
       SELECT 1
       FROM public.beaver_queue_ranked_requests request
       WHERE request.match_id=NEW.id AND request.status='accepted'
     )
     AND COALESCE(
       pg_catalog.current_setting('pongo.queue_ranked_match_id',TRUE),''
     )<>NEW.id::TEXT THEN
    RAISE EXCEPTION 'Queue Ranked scores must use the live-table score submission';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS beaver_queue_require_ranked_handoff_v1 ON public.matches;
CREATE TRIGGER beaver_queue_require_ranked_handoff_v1
BEFORE UPDATE OF status ON public.matches
FOR EACH ROW
EXECUTE FUNCTION public.beaver_queue_require_ranked_handoff_v1();

-- Once both players agree to Ranked, the score-required path is irreversible.
-- This table-boundary guard also blocks stale or hand-crafted clients from
-- finalizing the same live game through the legacy I Won / I Lost RPC.
CREATE OR REPLACE FUNCTION public.beaver_queue_require_ranked_score_v1()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path=''
AS $$
BEGIN
  IF NEW.status='completed' AND EXISTS(
    SELECT 1
    FROM public.beaver_queue_ranked_requests request
    WHERE request.queue_game_id=NEW.id
      AND request.status='accepted'
      AND request.match_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'This match is Ranked. Submit the final score instead.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS beaver_queue_require_ranked_score_v1 ON public.beaver_queue_games;
CREATE TRIGGER beaver_queue_require_ranked_score_v1
BEFORE INSERT ON public.beaver_queue_games
FOR EACH ROW
EXECUTE FUNCTION public.beaver_queue_require_ranked_score_v1();

CREATE OR REPLACE FUNCTION public.beaver_queue_health_v9()
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
    'version','20261104_05','initialized',state.id=1,'phase',state.phase,
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
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.beaver_queue_submit_ranked_result_v1(UUID,UUID,INTEGER,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_require_ranked_handoff_v1()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_require_ranked_score_v1()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_health_v9() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.beaver_queue_submit_ranked_result_v1(UUID,UUID,INTEGER,INTEGER)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_health_v9() TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
