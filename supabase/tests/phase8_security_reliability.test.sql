-- Run only against a disposable Supabase database after all migrations.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
SELECT id,email,jsonb_build_object('display_name',name),NOW(),NOW()
FROM (VALUES
  ('f8000000-0000-0000-0000-000000000001'::UUID,'phase8-a@example.test','Phase Eight A'),
  ('f8000000-0000-0000-0000-000000000002'::UUID,'phase8-b@example.test','Phase Eight B'),
  ('f8000000-0000-0000-0000-000000000003'::UUID,'phase8-c@example.test','Phase Eight C'),
  ('f8000000-0000-0000-0000-000000000004'::UUID,'phase8-admin@example.test','Phase Eight Admin')
) fixtures(id,email,name);

UPDATE public.player_integrity SET verification_level='dual_verification'
WHERE player_id='f8000000-0000-0000-0000-000000000001';

INSERT INTO public.matches(
  id,player_one_id,player_two_id,status,source,ranked,ranked_day,expires_at
) VALUES(
  'f8100000-0000-0000-0000-000000000001',
  'f8000000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000002',
  'ready','legacy',TRUE,public.club_ranked_day_v3(),NOW()+INTERVAL '24 hours'
);
SELECT pg_temp.assert_true(
  (SELECT verification_mode='dual' FROM public.matches WHERE id='f8100000-0000-0000-0000-000000000001'),
  'a ranked match involving a dual-verification account must inherit dual mode'
);

-- The first report remains private and cannot mutate ratings or visible result fields.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f8000000-0000-0000-0000-000000000001',TRUE);
SELECT pg_temp.assert_true(
  public.submit_match_report_v2(
    'f8100000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000001',11,9
  )->>'status'='awaiting_independent_report',
  'first dual report must wait for an independent opponent report'
);
SELECT pg_temp.assert_true(
  public.submit_match_report_v2(
    'f8100000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000001',11,9
  ) @> '{"status":"awaiting_independent_report","idempotent":true}'::JSONB,
  'repeating a private report must be idempotent'
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT status='ready' AND winner_id IS NULL FROM public.matches WHERE id='f8100000-0000-0000-0000-000000000001')
  AND (SELECT COUNT(*)=1 FROM public.match_submissions WHERE match_id='f8100000-0000-0000-0000-000000000001')
  AND (SELECT current_elo=50 FROM public.profiles WHERE id='f8000000-0000-0000-0000-000000000001'),
  'one private report must expose no result and apply no rating change'
);

-- A matching independent report finalizes exactly once and keeps both reports.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f8000000-0000-0000-0000-000000000002',TRUE);
SELECT pg_temp.assert_true(
  public.submit_match_report_v2(
    'f8100000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000001',11,9
  )->>'status'='confirmed',
  'matching independent reports must finalize the result'
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT status='confirmed' AND player_one_elo_change=35 AND player_two_elo_change=-20
   FROM public.matches WHERE id='f8100000-0000-0000-0000-000000000001')
  AND (SELECT COUNT(*)=2 FROM public.match_submissions WHERE match_id='f8100000-0000-0000-0000-000000000001')
  AND (SELECT COUNT(*)=2 FROM public.rating_events WHERE match_id='f8100000-0000-0000-0000-000000000001' AND is_active),
  'dual finalization must retain two reports and one asymmetric active event pair'
);

-- Conflicting independent reports close without ELO and expire cancellation.
INSERT INTO public.matches(
  id,player_one_id,player_two_id,status,source,ranked,ranked_day,expires_at
) VALUES(
  'f8100000-0000-0000-0000-000000000002',
  'f8000000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000002',
  'ready','legacy',TRUE,public.club_ranked_day_v3(),NOW()+INTERVAL '24 hours'
);
INSERT INTO public.match_cancellation_requests(match_id,requested_by,status)
VALUES('f8100000-0000-0000-0000-000000000002','f8000000-0000-0000-0000-000000000001','pending');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f8000000-0000-0000-0000-000000000001',TRUE);
SELECT public.submit_match_report_v2(
  'f8100000-0000-0000-0000-000000000002','f8000000-0000-0000-0000-000000000001',11,9
);
SELECT set_config('request.jwt.claim.sub','f8000000-0000-0000-0000-000000000002',TRUE);
SELECT pg_temp.assert_true(
  public.submit_match_report_v2(
    'f8100000-0000-0000-0000-000000000002','f8000000-0000-0000-0000-000000000002',11,9
  ) @> '{"status":"expired","conflicting_reports":true,"ratings_changed":false}'::JSONB,
  'conflicting independent reports must terminate without ratings'
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT status='expired' AND winner_id IS NULL FROM public.matches WHERE id='f8100000-0000-0000-0000-000000000002')
  AND NOT EXISTS(SELECT 1 FROM public.rating_events WHERE match_id='f8100000-0000-0000-0000-000000000002')
  AND (SELECT status='expired' FROM public.match_cancellation_requests WHERE match_id='f8100000-0000-0000-0000-000000000002')
  AND EXISTS(SELECT 1 FROM public.integrity_flags WHERE match_id='f8100000-0000-0000-0000-000000000002' AND flag_type='dual_report_conflict'),
  'dual conflict must retain its audit signal but change no result or ELO'
);

-- Reaching the per-pair ceiling produces an administrator-visible farming signal.
INSERT INTO public.matches(
  id,player_one_id,player_two_id,status,source,ranked,ranked_day,expires_at
) VALUES(
  'f8100000-0000-0000-0000-000000000003',
  'f8000000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000002',
  'ready','legacy',TRUE,public.club_ranked_day_v3(),NOW()+INTERVAL '24 hours'
);
UPDATE public.matches SET status='confirmed',winner_id=player_one_id,
  player_one_score=11,player_two_score=9,confirmed_at=NOW(),finalized_at=NOW()
WHERE id='f8100000-0000-0000-0000-000000000003';
INSERT INTO public.matches(
  id,player_one_id,player_two_id,status,source,ranked,ranked_day,expires_at
) VALUES(
  'f8100000-0000-0000-0000-000000000004',
  'f8000000-0000-0000-0000-000000000001','f8000000-0000-0000-0000-000000000002',
  'ready','legacy',TRUE,public.club_ranked_day_v3(),NOW()+INTERVAL '24 hours'
);
UPDATE public.matches SET status='confirmed',winner_id=player_two_id,
  player_one_score=9,player_two_score=11,confirmed_at=NOW(),finalized_at=NOW()
WHERE id='f8100000-0000-0000-0000-000000000004';
SELECT pg_temp.assert_true(
  EXISTS(SELECT 1 FROM public.integrity_flags WHERE match_id='f8100000-0000-0000-0000-000000000004' AND flag_type='pair_daily_ceiling'),
  'the third same-pair daily result must emit a match-farming signal'
);

-- Repeated substantiated violations automatically enter monitored status.
UPDATE public.player_integrity SET confirmed_violations=2
WHERE player_id='f8000000-0000-0000-0000-000000000003';
SELECT pg_temp.assert_true(
  (SELECT verification_level='monitored' FROM public.player_integrity WHERE player_id='f8000000-0000-0000-0000-000000000003'),
  'two confirmed violations must automatically mark a normal account monitored'
);

-- Rating facts and append-only audit rows resist even owner-level accidental edits.
DO $$
BEGIN
  UPDATE public.rating_events SET rating_change=rating_change+1
  WHERE match_id='f8100000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'Expected immutable rating fact rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT ILIKE '%immutable%' THEN RAISE; END IF;
END;
$$;
DO $$
BEGIN
  DELETE FROM public.rating_events WHERE match_id='f8100000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'Expected rating event delete rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT ILIKE '%cannot be deleted%' THEN RAISE; END IF;
END;
$$;
DO $$
BEGIN
  DELETE FROM public.domain_events WHERE match_id='f8100000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'Expected append-only event rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT ILIKE '%append-only%' THEN RAISE; END IF;
END;
$$;
DO $$
BEGIN
  DELETE FROM public.match_submissions WHERE match_id='f8100000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'Expected append-only submission rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT ILIKE '%append-only%' THEN RAISE; END IF;
END;
$$;

-- Unrelated players cannot read match-private rows or mutate ranked facts directly.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f8000000-0000-0000-0000-000000000003',TRUE);
SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=0 FROM public.matches WHERE id='f8100000-0000-0000-0000-000000000001')
  AND (SELECT COUNT(*)=0 FROM public.match_submissions WHERE match_id='f8100000-0000-0000-0000-000000000001')
  AND (SELECT COUNT(*)=0 FROM public.integrity_flags),
  'RLS must hide participant and administrator-only integrity records from unrelated users'
);
DO $$
BEGIN
  PERFORM public.admin_review_integrity_flag_v3('00000000-0000-0000-0000-000000000000');
  RAISE EXCEPTION 'Expected administrator authorization rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT ILIKE '%admin access required%' THEN RAISE; END IF;
END;
$$;
DO $$
BEGIN
  INSERT INTO public.matches(player_one_id,player_two_id,status,source)
  VALUES(auth.uid(),'f8000000-0000-0000-0000-000000000002','ready','legacy');
  RAISE EXCEPTION 'Expected direct match write rejection';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END;
$$;
DO $$
BEGIN
  UPDATE public.profiles SET current_elo=900 WHERE id=auth.uid();
  RAISE EXCEPTION 'Expected direct rating write rejection';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END;
$$;
UPDATE public.profiles SET display_name='Phase Eight C Updated' WHERE id=auth.uid();
SELECT pg_temp.assert_true(
  (SELECT display_name='Phase Eight C Updated' FROM public.profiles WHERE id=auth.uid()),
  'the profile display-name edit contract must remain available'
);
RESET ROLE;

-- Admin-only integrity review remains enforced inside its SECURITY DEFINER RPC.
INSERT INTO public.user_roles(user_id,role) VALUES('f8000000-0000-0000-0000-000000000004','admin');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f8000000-0000-0000-0000-000000000004',TRUE);
SELECT pg_temp.assert_true(
  (SELECT COUNT(*)>=4 FROM public.matches WHERE player_one_id='f8000000-0000-0000-0000-000000000001'),
  'administrators must be able to inspect matches referenced by disputes and integrity signals'
);
SELECT public.admin_review_integrity_flag_v3(
  (SELECT id FROM public.integrity_flags WHERE flag_type='dual_report_conflict' LIMIT 1)
);
RESET ROLE;
SELECT pg_temp.assert_true(
  EXISTS(SELECT 1 FROM public.integrity_flags WHERE flag_type='dual_report_conflict' AND reviewed_by='f8000000-0000-0000-0000-000000000004' AND reviewed_at IS NOT NULL),
  'administrators must be able to acknowledge integrity signals'
);

SELECT pg_temp.assert_true(
  NOT has_function_privilege('anon','public.submit_match_report_v2(uuid,uuid,integer,integer)','EXECUTE')
  AND has_function_privilege('authenticated','public.submit_match_report_v2(uuid,uuid,integer,integer)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.finalize_match_v2(uuid,uuid)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.check_daily_match_limit(uuid,uuid)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.protect_rating_event_ledger_v3()','EXECUTE'),
  'only narrowly scoped public RPCs may be called by authenticated clients'
);

SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=9 FROM pg_publication_tables
   WHERE pubname='supabase_realtime'
     AND schemaname='public'
     AND tablename IN (
       'profiles','matches','challenges','rating_events','disputes','notifications',
       'match_cancellation_requests','player_integrity','integrity_flags'
     )),
  'all live application and integrity tables must be published for Realtime'
);

SELECT pg_temp.assert_true(
  NOT EXISTS(
    SELECT 1 FROM public.rating_events
    WHERE match_id IS NOT NULL AND is_active
    GROUP BY match_id,player_id HAVING COUNT(*)>1
  ),
  'the active rating ledger must contain at most one event per match and player'
);

ROLLBACK;
