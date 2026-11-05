-- Restore the production ranked limits after the temporary queue testing cap.
-- Queue requests preflight the same shared gate that is rechecked atomically
-- when both players agree; regular challenge acceptance already uses this gate.
BEGIN;

DO $dependencies$
BEGIN
  IF to_regprocedure('public.assert_ranked_match_eligibility_v4(uuid,uuid)') IS NULL
     OR to_regprocedure('public.beaver_queue_request_ranked_v1()') IS NULL THEN
    RAISE EXCEPTION 'Missing dependency: apply ranked and queue migrations through 20261104_05 first';
  END IF;
END;
$dependencies$;

UPDATE public.ranking_config
SET daily_ranked_player_limit=10,
    daily_ranked_pair_limit=3,
    updated_at=clock_timestamp()
WHERE id
  AND (daily_ranked_player_limit IS DISTINCT FROM 10
    OR daily_ranked_pair_limit IS DISTINCT FROM 3);

DO $config$
BEGIN
  IF NOT EXISTS(
    SELECT 1
    FROM public.ranking_config
    WHERE id
      AND daily_ranked_player_limit=10
      AND daily_ranked_pair_limit=3
  ) THEN
    RAISE EXCEPTION 'Ranked match configuration is missing or could not be repaired';
  END IF;
END;
$config$;

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
  IF EXISTS(
    SELECT 1 FROM public.beaver_queue_ranked_requests
    WHERE queue_game_id=state.game_id
  ) THEN
    RAISE EXCEPTION 'A Ranked request was already made for this match';
  END IF;

  opponent:=CASE
    WHEN player_id=state.king_id THEN state.challenger_id
    ELSE state.king_id
  END;

  -- This is only a preflight: no capacity is reserved until mutual acceptance.
  -- The response RPC calls the same function again under the same stable player
  -- locks, so concurrent challenge/queue acceptances cannot oversubscribe either
  -- the per-player or symmetric per-opponent allowance.
  PERFORM public.assert_ranked_match_eligibility_v4(player_id,opponent);

  INSERT INTO public.beaver_queue_ranked_requests(
    queue_game_id,requester_id,opponent_id
  ) VALUES(
    state.game_id,player_id,opponent
  )
  RETURNING id INTO request_id;

  RETURN jsonb_build_object('request_id',request_id,'status','pending');
END;
$$;

REVOKE ALL ON FUNCTION public.beaver_queue_request_ranked_v1()
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.beaver_queue_request_ranked_v1()
  TO authenticated;

COMMIT;
