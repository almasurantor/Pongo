-- Match overtime and Unicode display-name coverage. Disposable database only.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

SELECT pg_temp.assert_true(
  to_regprocedure('public.beaver_queue_overtime_v1(uuid,text)') IS NOT NULL
  AND to_regprocedure('public.beaver_queue_health_v10()') IS NOT NULL
  AND has_function_privilege('authenticated','public.beaver_queue_overtime_v1(uuid,text)','EXECUTE')
  AND NOT has_function_privilege('anon','public.beaver_queue_overtime_v1(uuid,text)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.beaver_queue_expire_game_internal_v1(uuid)','EXECUTE'),
  'only authenticated players may call the public overtime RPC'
);

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at) VALUES
  ('fa100000-0000-4000-8000-000000000001','overtime-a@example.test','{"display_name":"Almas 🏓"}',NOW(),NOW()),
  ('fa100000-0000-4000-8000-000000000002','overtime-b@example.test','{"display_name":"🔥King"}',NOW(),NOW()),
  ('fa100000-0000-4000-8000-000000000003','overtime-c@example.test','{"display_name":"বাংলা🏓"}',NOW(),NOW()),
  ('fa100000-0000-4000-8000-000000000004','overtime-d@example.test','{"display_name":"José🔥"}',NOW(),NOW()),
  ('fa100000-0000-4000-8000-000000000005','overtime-e@example.test','{"display_name":"José🔥"}',NOW(),NOW());

SELECT pg_temp.assert_true(
  (SELECT display_name='Almas 🏓' FROM public.profiles WHERE id='fa100000-0000-4000-8000-000000000001')
  AND (SELECT display_name='🔥King' FROM public.profiles WHERE id='fa100000-0000-4000-8000-000000000002')
  AND (SELECT display_name='বাংলা🏓' FROM public.profiles WHERE id='fa100000-0000-4000-8000-000000000003')
  AND (SELECT display_name='José🔥' FROM public.profiles WHERE id='fa100000-0000-4000-8000-000000000004')
  AND (SELECT display_name='José🔥 2' FROM public.profiles WHERE id='fa100000-0000-4000-8000-000000000005'),
  'signup must preserve Unicode names and keep case-insensitive uniqueness'
);

DO $$
BEGIN
  INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
  VALUES('fa100000-0000-4000-8000-000000000006','invalid-name@example.test','{"display_name":"123🔥"}',NOW(),NOW());
  RAISE EXCEPTION 'Expected invalid signup name rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected invalid signup name rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%include at least one letter%' THEN RAISE; END IF;
END;
$$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa100000-0000-4000-8000-000000000001',TRUE);
SELECT pg_temp.assert_true(
  public.check_display_name_available_v4('A')->>'valid'='true'
  AND public.check_display_name_available_v4('Player123')->>'valid'='true'
  AND public.check_display_name_available_v4('🔥🏓')->>'valid'='false'
  AND public.check_display_name_available_v4('José🔥')->>'available'='false',
  'availability checks must use the same Unicode-letter contract and uniqueness rule'
);
SELECT (public.update_my_profile_settings_v4('A🔥',TRUE,FALSE)).display_name;
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT display_name='A🔥' FROM public.profiles WHERE id='fa100000-0000-4000-8000-000000000001'),
  'profile editing must accept a one-letter emoji name'
);

DELETE FROM public.beaver_queue_ranked_requests;
DELETE FROM public.beaver_queue_swap_requests;
DELETE FROM public.beaver_queue_games;
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET
  phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
  game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,
  updated_at=clock_timestamp()
WHERE id=1;

CREATE TEMP TABLE overtime_baseline AS
SELECT (SELECT COUNT(*) FROM public.matches) matches,
       (SELECT COUNT(*) FROM public.rating_events) rating_events;

INSERT INTO public.beaver_queue_members(user_id,display_name,status,queue_position,joined_at,updated_at) VALUES
  ('fa100000-0000-4000-8000-000000000001','A🔥','playing',1001,NOW(),NOW()),
  ('fa100000-0000-4000-8000-000000000002','🔥King','playing',1002,NOW(),NOW()),
  ('fa100000-0000-4000-8000-000000000003','বাংলা🏓','waiting',1003,NOW(),NOW());
UPDATE public.beaver_queue_table SET
  phase='playing',king_id='fa100000-0000-4000-8000-000000000001',
  challenger_id='fa100000-0000-4000-8000-000000000002',
  game_id='fa110000-0000-4000-8000-000000000001',
  game_started_at=clock_timestamp()-INTERVAL '10 minutes 1 second',
  game_expires_at=clock_timestamp()-INTERVAL '1 second',
  updated_at=clock_timestamp()
WHERE id=1;

SELECT pg_temp.assert_true(
  (SELECT NOT overtime_used
    AND overtime_prompt_expires_at=game_expires_at+INTERVAL '60 seconds'
    FROM public.beaver_queue_table WHERE id=1),
  'a new game must receive one server-authored 60-second overtime decision window'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa100000-0000-4000-8000-000000000001',TRUE);
SELECT public.beaver_queue_overtime_v1('fa110000-0000-4000-8000-000000000001','extend');
RESET ROLE;
CREATE TEMP TABLE first_extension AS
SELECT game_expires_at FROM public.beaver_queue_table WHERE id=1;
GRANT SELECT ON first_extension TO authenticated;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa100000-0000-4000-8000-000000000002',TRUE);
SELECT pg_temp.assert_true(
  public.beaver_queue_overtime_v1('fa110000-0000-4000-8000-000000000001','extend')->>'idempotent'='true',
  'a simultaneous second approval must be idempotent'
);
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT phase='playing' AND overtime_used AND overtime_prompt_expires_at IS NULL
    AND game_expires_at=(SELECT game_expires_at FROM first_extension)
    AND game_expires_at BETWEEN clock_timestamp()+INTERVAL '115 seconds'
      AND clock_timestamp()+INTERVAL '121 seconds'
    FROM public.beaver_queue_table WHERE id=1),
  'one approval must immediately grant exactly one shared two-minute extension'
);

UPDATE public.beaver_queue_table SET game_expires_at=clock_timestamp() WHERE id=1;
SET LOCAL ROLE service_role;
SELECT public.run_pongo_queue_maintenance_v1();
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT phase='idle' AND game_id IS NULL AND king_id='fa100000-0000-4000-8000-000000000003'
    FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT status='left' FROM public.beaver_queue_members WHERE user_id='fa100000-0000-4000-8000-000000000001')
  AND (SELECT status='left' FROM public.beaver_queue_members WHERE user_id='fa100000-0000-4000-8000-000000000002')
  AND EXISTS(SELECT 1 FROM public.beaver_queue_games
    WHERE id='fa110000-0000-4000-8000-000000000001' AND status='abandoned'
      AND winner_id IS NULL AND loser_id IS NULL AND reported_by IS NULL)
  AND (SELECT COUNT(*) FROM public.matches)=(SELECT matches FROM overtime_baseline)
  AND (SELECT COUNT(*) FROM public.rating_events)=(SELECT rating_events FROM overtime_baseline),
  'overtime expiry must remove both players, advance the queue, and record no result or ELO'
);

-- Rebuild a fresh match and prove either player can end during the prompt.
UPDATE public.beaver_queue_members SET status='playing',updated_at=clock_timestamp()
WHERE user_id IN('fa100000-0000-4000-8000-000000000001','fa100000-0000-4000-8000-000000000002');
UPDATE public.beaver_queue_members SET status='waiting',updated_at=clock_timestamp()
WHERE user_id='fa100000-0000-4000-8000-000000000003';
UPDATE public.beaver_queue_table SET
  phase='playing',king_id='fa100000-0000-4000-8000-000000000001',
  challenger_id='fa100000-0000-4000-8000-000000000002',
  game_id='fa110000-0000-4000-8000-000000000002',
  game_started_at=clock_timestamp()-INTERVAL '10 minutes 1 second',
  game_expires_at=clock_timestamp()-INTERVAL '1 second',
  solo_expires_at=NULL,updated_at=clock_timestamp()
WHERE id=1;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa100000-0000-4000-8000-000000000002',TRUE);
SELECT public.beaver_queue_overtime_v1('fa110000-0000-4000-8000-000000000002','end');
RESET ROLE;
SELECT pg_temp.assert_true(
  EXISTS(SELECT 1 FROM public.beaver_queue_games
    WHERE id='fa110000-0000-4000-8000-000000000002' AND status='abandoned')
  AND (SELECT status='left' FROM public.beaver_queue_members WHERE user_id='fa100000-0000-4000-8000-000000000001')
  AND (SELECT status='left' FROM public.beaver_queue_members WHERE user_id='fa100000-0000-4000-8000-000000000002'),
  'either player ending before approval must atomically expire the match'
);

ROLLBACK;
