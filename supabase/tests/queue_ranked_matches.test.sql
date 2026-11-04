-- Queue V9 optional Ranked conversion and inline score coverage.
-- Run only against a disposable database after all migrations. Everything rolls back.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

SELECT pg_temp.assert_true(
  to_regprocedure('public.beaver_queue_health_v9()') IS NOT NULL
  AND to_regprocedure('public.assert_ranked_match_eligibility_v4(uuid,uuid)') IS NOT NULL
  AND has_function_privilege('authenticated','public.beaver_queue_request_ranked_v1()','EXECUTE')
  AND has_function_privilege('authenticated','public.beaver_queue_respond_ranked_v1(uuid,text)','EXECUTE')
  AND has_function_privilege('authenticated','public.beaver_queue_submit_ranked_result_v1(uuid,uuid,integer,integer)','EXECUTE')
  AND NOT has_function_privilege('anon','public.beaver_queue_request_ranked_v1()','EXECUTE')
  AND (SELECT daily_ranked_player_limit=10 AND daily_ranked_pair_limit=10
    FROM public.ranking_config WHERE id),
  'v9 must expose only authenticated Ranked actions and share both ten-game limits'
);

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
SELECT id,email,jsonb_build_object('display_name',name),NOW(),NOW()
FROM (VALUES
  ('fb000000-0000-4000-8000-000000000001'::UUID,'queue-ranked-a@example.test','Queue Ranked A'),
  ('fb000000-0000-4000-8000-000000000002'::UUID,'queue-ranked-b@example.test','Queue Ranked B'),
  ('fb000000-0000-4000-8000-000000000003'::UUID,'queue-ranked-c@example.test','Queue Ranked C'),
  ('fb000000-0000-4000-8000-000000000004'::UUID,'queue-ranked-d@example.test','Queue Ranked D'),
  ('fb000000-0000-4000-8000-000000000005'::UUID,'queue-ranked-e@example.test','Queue Ranked E'),
  ('fb000000-0000-4000-8000-000000000006'::UUID,'queue-ranked-f@example.test','Queue Ranked F'),
  ('fb000000-0000-4000-8000-000000000007'::UUID,'queue-ranked-g@example.test','Queue Ranked G'),
  ('fb000000-0000-4000-8000-000000000008'::UUID,'queue-ranked-h@example.test','Queue Ranked H'),
  ('fb000000-0000-4000-8000-000000000009'::UUID,'queue-ranked-i@example.test','Queue Ranked I')
) fixtures(id,email,name);

DELETE FROM public.beaver_queue_ranked_requests;
DELETE FROM public.beaver_queue_swap_requests;
DELETE FROM public.beaver_queue_games;
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET
  phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
  game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW()
WHERE id=1;

-- A and B have a normal unranked queue game, with C waiting.
INSERT INTO public.beaver_queue_members(user_id,display_name,status,queue_position,joined_at,updated_at) VALUES
 ('fb000000-0000-4000-8000-000000000001','Queue Ranked A','playing',801,NOW(),NOW()),
 ('fb000000-0000-4000-8000-000000000002','Queue Ranked B','playing',802,NOW(),NOW()),
 ('fb000000-0000-4000-8000-000000000003','Queue Ranked C','waiting',803,NOW(),NOW());
UPDATE public.beaver_queue_table SET
  phase='playing',king_id='fb000000-0000-4000-8000-000000000001',
  challenger_id='fb000000-0000-4000-8000-000000000002',
  game_id='fb100000-0000-4000-8000-000000000001',game_started_at=clock_timestamp(),
  game_expires_at=clock_timestamp()+INTERVAL '10 minutes',solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW()
WHERE id=1;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000001',TRUE);
SELECT public.beaver_queue_request_ranked_v1();
DO $$
BEGIN
  PERFORM public.beaver_queue_request_ranked_v1();
  RAISE EXCEPTION 'Expected duplicate request rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected duplicate request rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%already made%' THEN RAISE; END IF;
END;
$$;
DO $$
BEGIN
  PERFORM public.beaver_queue_respond_ranked_v1(
    (SELECT id FROM public.beaver_queue_ranked_requests WHERE status='pending'),'accept'
  );
  RAISE EXCEPTION 'Expected requester response rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected requester response rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%not available%' THEN RAISE; END IF;
END;
$$;
SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=1 FROM public.beaver_queue_ranked_requests),
  'one request must exist after duplicate attempts'
);
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000003',TRUE);
SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=0 FROM public.beaver_queue_ranked_requests),
  'RLS must hide a request from nonparticipants'
);
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000002',TRUE);
SELECT public.beaver_queue_respond_ranked_v1(
  (SELECT id FROM public.beaver_queue_ranked_requests WHERE status='pending'),'decline'
);
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT status='declined' AND match_id IS NULL
    FROM public.beaver_queue_ranked_requests WHERE queue_game_id='fb100000-0000-4000-8000-000000000001')
  AND (SELECT phase='playing' AND game_id='fb100000-0000-4000-8000-000000000001'
    FROM public.beaver_queue_table WHERE id=1)
  AND NOT EXISTS(SELECT 1 FROM public.matches
    WHERE request_id=(SELECT id FROM public.beaver_queue_ranked_requests
      WHERE queue_game_id='fb100000-0000-4000-8000-000000000001')),
  'declining must leave the original unranked game untouched'
);

-- An unanswered request is canceled when the normal unranked game ends.
UPDATE public.beaver_queue_table
SET game_id='fb100000-0000-4000-8000-000000000002'
WHERE id=1;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000001',TRUE);
SELECT public.beaver_queue_request_ranked_v1();
SELECT public.beaver_queue_report_outcome_v2('fb100000-0000-4000-8000-000000000002','won');
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT status='canceled' FROM public.beaver_queue_ranked_requests
    WHERE queue_game_id='fb100000-0000-4000-8000-000000000002')
  AND EXISTS(SELECT 1 FROM public.beaver_queue_games
    WHERE id='fb100000-0000-4000-8000-000000000002' AND status='completed'),
  'a normal result must cancel its unanswered Ranked request and stay unranked'
);

-- D and E mutually agree. Their standard ranked match is created, but they
-- remain at the live table with the original timer until a score is submitted.
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET
  phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
  game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW()
WHERE id=1;
INSERT INTO public.beaver_queue_members(user_id,display_name,status,queue_position,joined_at,updated_at) VALUES
 ('fb000000-0000-4000-8000-000000000004','Queue Ranked D','playing',811,NOW(),NOW()),
 ('fb000000-0000-4000-8000-000000000005','Queue Ranked E','playing',812,NOW(),NOW()),
 ('fb000000-0000-4000-8000-000000000006','Queue Ranked F','waiting',813,NOW(),NOW());
UPDATE public.beaver_queue_table SET
  phase='playing',king_id='fb000000-0000-4000-8000-000000000004',
  challenger_id='fb000000-0000-4000-8000-000000000005',
  game_id='fb100000-0000-4000-8000-000000000003',game_started_at=clock_timestamp(),
  game_expires_at=clock_timestamp()+INTERVAL '10 minutes',solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW()
WHERE id=1;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000004',TRUE);
SELECT public.beaver_queue_request_ranked_v1();
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000005',TRUE);
SELECT public.beaver_queue_respond_ranked_v1(
  (SELECT id FROM public.beaver_queue_ranked_requests WHERE status='pending'),'accept'
);
RESET ROLE;

SELECT pg_temp.assert_true(
  EXISTS(SELECT 1 FROM public.matches match
    JOIN public.beaver_queue_ranked_requests request ON request.match_id=match.id
    WHERE request.queue_game_id='fb100000-0000-4000-8000-000000000003'
      AND request.status='accepted' AND match.status='ready' AND match.ranked
      AND match.source='spontaneous' AND match.ranked_day=public.club_ranked_day_v3())
  AND NOT EXISTS(SELECT 1 FROM public.beaver_queue_games
    WHERE id='fb100000-0000-4000-8000-000000000003')
  AND (SELECT status='playing' FROM public.beaver_queue_members
    WHERE user_id='fb000000-0000-4000-8000-000000000004')
  AND (SELECT status='playing' FROM public.beaver_queue_members
    WHERE user_id='fb000000-0000-4000-8000-000000000005')
  AND (SELECT phase='playing' AND game_id='fb100000-0000-4000-8000-000000000003'
    AND king_id='fb000000-0000-4000-8000-000000000004'
    AND challenger_id='fb000000-0000-4000-8000-000000000005'
    FROM public.beaver_queue_table WHERE id=1),
  'acceptance must create one normal ranked match while keeping the original queue game and timer'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000005',TRUE);
SELECT public.beaver_queue_respond_ranked_v1(
  (SELECT id FROM public.beaver_queue_ranked_requests
    WHERE queue_game_id='fb100000-0000-4000-8000-000000000003'),'accept'
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=1 FROM public.matches
    WHERE request_id=(SELECT id FROM public.beaver_queue_ranked_requests
      WHERE queue_game_id='fb100000-0000-4000-8000-000000000003')),
  'repeated acceptance must return the existing match without creating a duplicate'
);

-- A stale or malicious client cannot use I Won / I Lost after Ranked is
-- accepted. The failed insert rolls the legacy outcome RPC back completely.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000004',TRUE);
DO $$
BEGIN
  PERFORM public.beaver_queue_report_outcome_v2(
    'fb100000-0000-4000-8000-000000000003','won'
  );
  RAISE EXCEPTION 'Expected unranked outcome rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected unranked outcome rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%Ranked%final score%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;
SELECT pg_temp.assert_true(
  NOT EXISTS(SELECT 1 FROM public.beaver_queue_games
    WHERE id='fb100000-0000-4000-8000-000000000003')
  AND (SELECT phase='playing' AND game_id='fb100000-0000-4000-8000-000000000003'
    FROM public.beaver_queue_table WHERE id=1),
  'accepted Ranked games must reject the old unranked outcome path'
);

-- The shared finalizer is still reused, but queue-linked matches must enter it
-- through the wrapper that owns the queue handoff transaction.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000004',TRUE);
DO $$
BEGIN
  PERFORM public.submit_match_report_v2(
    (SELECT match_id FROM public.beaver_queue_ranked_requests
      WHERE queue_game_id='fb100000-0000-4000-8000-000000000003'),
    'fb000000-0000-4000-8000-000000000004',11,9
  );
  RAISE EXCEPTION 'Expected direct finalizer rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected direct finalizer rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%live-table score submission%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT status='ready' AND winner_id IS NULL
    FROM public.matches WHERE id=(SELECT match_id
      FROM public.beaver_queue_ranked_requests
      WHERE queue_game_id='fb100000-0000-4000-8000-000000000003'))
  AND NOT EXISTS(SELECT 1 FROM public.rating_events
    WHERE match_id=(SELECT match_id FROM public.beaver_queue_ranked_requests
      WHERE queue_game_id='fb100000-0000-4000-8000-000000000003'))
  AND (SELECT phase='playing' FROM public.beaver_queue_table WHERE id=1),
  'direct finalizer calls must not separate ELO finalization from queue handoff'
);

-- The queue wrapper calls the ordinary score/finalization/ELO path, then
-- removes both players and advances F only after the valid score commits.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000004',TRUE);
SELECT public.beaver_queue_submit_ranked_result_v1(
  (SELECT match_id FROM public.beaver_queue_ranked_requests
    WHERE queue_game_id='fb100000-0000-4000-8000-000000000003'),
  'fb000000-0000-4000-8000-000000000004',11,9
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT status='confirmed' AND player_one_score=11 AND player_two_score=9
      AND player_one_elo_change IS NOT NULL AND player_two_elo_change IS NOT NULL
    FROM public.matches WHERE id=(SELECT match_id FROM public.beaver_queue_ranked_requests
      WHERE queue_game_id='fb100000-0000-4000-8000-000000000003'))
  AND (SELECT COUNT(*)=2 FROM public.rating_events
    WHERE match_id=(SELECT match_id FROM public.beaver_queue_ranked_requests
      WHERE queue_game_id='fb100000-0000-4000-8000-000000000003'))
  AND (SELECT status='left' FROM public.beaver_queue_members
    WHERE user_id='fb000000-0000-4000-8000-000000000004')
  AND (SELECT status='left' FROM public.beaver_queue_members
    WHERE user_id='fb000000-0000-4000-8000-000000000005')
  AND (SELECT phase='idle' AND king_id='fb000000-0000-4000-8000-000000000006'
    AND challenger_id IS NULL FROM public.beaver_queue_table WHERE id=1),
  'inline score must use the existing finalizer, remove both players, and advance the queue'
);

-- A failed final eligibility check rolls back every conversion write and
-- leaves the AFK-capable unranked game running.
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET
  phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
  game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW()
WHERE id=1;
INSERT INTO public.matches(player_one_id,player_two_id,status,source,ranked,ranked_day,expires_at)
VALUES('fb000000-0000-4000-8000-000000000007','fb000000-0000-4000-8000-000000000009',
  'ready','challenge',TRUE,public.club_ranked_day_v3(),NOW()+INTERVAL '24 hours');
UPDATE public.ranking_config SET active_ranked_match_limit=1 WHERE id;
INSERT INTO public.beaver_queue_members(user_id,display_name,status,queue_position,joined_at,updated_at) VALUES
 ('fb000000-0000-4000-8000-000000000007','Queue Ranked G','playing',821,NOW(),NOW()),
 ('fb000000-0000-4000-8000-000000000008','Queue Ranked H','playing',822,NOW(),NOW());
UPDATE public.beaver_queue_table SET
  phase='playing',king_id='fb000000-0000-4000-8000-000000000007',
  challenger_id='fb000000-0000-4000-8000-000000000008',
  game_id='fb100000-0000-4000-8000-000000000004',game_started_at=clock_timestamp(),
  game_expires_at=clock_timestamp()+INTERVAL '10 minutes',solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW()
WHERE id=1;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000007',TRUE);
SELECT public.beaver_queue_request_ranked_v1();
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000008',TRUE);
DO $$
BEGIN
  PERFORM public.beaver_queue_respond_ranked_v1(
    (SELECT id FROM public.beaver_queue_ranked_requests WHERE status='pending'),'accept'
  );
  RAISE EXCEPTION 'Expected active ranked limit rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected active ranked limit rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%active ranked match%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;
UPDATE public.ranking_config SET active_ranked_match_limit=3 WHERE id;

SELECT pg_temp.assert_true(
  (SELECT status='pending' AND match_id IS NULL FROM public.beaver_queue_ranked_requests
    WHERE queue_game_id='fb100000-0000-4000-8000-000000000004')
  AND (SELECT phase='playing' AND game_id='fb100000-0000-4000-8000-000000000004'
    AND afk_reporter_id IS NULL FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT status='playing' FROM public.beaver_queue_members
    WHERE user_id='fb000000-0000-4000-8000-000000000007')
  AND (SELECT status='playing' FROM public.beaver_queue_members
    WHERE user_id='fb000000-0000-4000-8000-000000000008')
  AND NOT EXISTS(SELECT 1 FROM public.matches
    WHERE request_id=(SELECT id FROM public.beaver_queue_ranked_requests
      WHERE queue_game_id='fb100000-0000-4000-8000-000000000004')),
  'ineligibility must preserve the queue game and create no partial ranked match'
);

-- If no score arrives by the original ten-minute deadline, both players are
-- removed and the linked ranked match is voided with no rating events.
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET
  phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
  game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW()
WHERE id=1;
INSERT INTO public.beaver_queue_members(user_id,display_name,status,queue_position,joined_at,updated_at) VALUES
 ('fb000000-0000-4000-8000-000000000001','Queue Ranked A','playing',831,NOW(),NOW()),
 ('fb000000-0000-4000-8000-000000000002','Queue Ranked B','playing',832,NOW(),NOW()),
 ('fb000000-0000-4000-8000-000000000003','Queue Ranked C','waiting',833,NOW(),NOW());
UPDATE public.beaver_queue_table SET
  phase='playing',king_id='fb000000-0000-4000-8000-000000000001',
  challenger_id='fb000000-0000-4000-8000-000000000002',
  game_id='fb100000-0000-4000-8000-000000000005',game_started_at=clock_timestamp(),
  game_expires_at=clock_timestamp()+INTERVAL '10 minutes',solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW()
WHERE id=1;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000001',TRUE);
SELECT public.beaver_queue_request_ranked_v1();
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000002',TRUE);
SELECT public.beaver_queue_respond_ranked_v1(
  (SELECT id FROM public.beaver_queue_ranked_requests WHERE status='pending'),'accept'
);
RESET ROLE;
UPDATE public.beaver_queue_table SET game_expires_at=clock_timestamp() WHERE id=1;
SET LOCAL ROLE service_role;
SELECT public.beaver_queue_advance_expired_v1();
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT status='voided' AND winner_id IS NULL AND finalized_at IS NOT NULL
    FROM public.matches WHERE id=(SELECT match_id FROM public.beaver_queue_ranked_requests
      WHERE queue_game_id='fb100000-0000-4000-8000-000000000005'))
  AND NOT EXISTS(SELECT 1 FROM public.rating_events
    WHERE match_id=(SELECT match_id FROM public.beaver_queue_ranked_requests
      WHERE queue_game_id='fb100000-0000-4000-8000-000000000005'))
  AND (SELECT status='left' FROM public.beaver_queue_members
    WHERE user_id='fb000000-0000-4000-8000-000000000001')
  AND (SELECT status='left' FROM public.beaver_queue_members
    WHERE user_id='fb000000-0000-4000-8000-000000000002')
  AND EXISTS(SELECT 1 FROM public.beaver_queue_games
    WHERE id='fb100000-0000-4000-8000-000000000005' AND status='abandoned')
  AND (SELECT phase='idle' AND king_id='fb000000-0000-4000-8000-000000000003'
    FROM public.beaver_queue_table WHERE id=1),
  'deadline must void the ranked match, apply no rating, remove both players, and advance'
);

ROLLBACK;
