-- Run only against a disposable Supabase database after all migrations.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN, message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
SELECT id,email,jsonb_build_object('display_name',name),NOW(),NOW()
FROM (VALUES
  ('f6000000-0000-0000-0000-000000000001'::UUID,'phase6-a@example.test','Phase Six A'),
  ('f6000000-0000-0000-0000-000000000002'::UUID,'phase6-b@example.test','Phase Six B'),
  ('f6000000-0000-0000-0000-000000000003'::UUID,'phase6-c@example.test','Phase Six C'),
  ('f6000000-0000-0000-0000-000000000004'::UUID,'phase6-d@example.test','Phase Six D')
) fixtures(id,email,name);

INSERT INTO public.matches(
  id,player_one_id,player_two_id,status,source,ranked,ranked_day,winner_id,
  player_one_score,player_two_score,player_one_elo_before,player_two_elo_before,
  player_one_elo_change,player_two_elo_change,confirmed_at,finalized_at,rating_calculation
) VALUES
  ('f6100000-0000-0000-0000-000000000001','f6000000-0000-0000-0000-000000000001','f6000000-0000-0000-0000-000000000002','confirmed','legacy',TRUE,public.club_ranked_day_v3(),'f6000000-0000-0000-0000-000000000001',11,9,1000,1000,20,-20,NOW()-INTERVAL '1 hour',NOW()-INTERVAL '1 hour','{}'),
  ('f6100000-0000-0000-0000-000000000002','f6000000-0000-0000-0000-000000000001','f6000000-0000-0000-0000-000000000003','confirmed','legacy',TRUE,public.club_ranked_day_v3(),'f6000000-0000-0000-0000-000000000001',11,9,1020,1000,19,-19,NOW()-INTERVAL '30 minutes',NOW()-INTERVAL '30 minutes','{}');

INSERT INTO public.rating_events(match_id,player_id,event_kind,rating_before,rating_change,rating_after,created_at)
VALUES
  ('f6100000-0000-0000-0000-000000000001','f6000000-0000-0000-0000-000000000001','legacy_match',1000,20,1020,NOW()-INTERVAL '1 hour'),
  ('f6100000-0000-0000-0000-000000000001','f6000000-0000-0000-0000-000000000002','legacy_match',1000,-20,980,NOW()-INTERVAL '1 hour'),
  ('f6100000-0000-0000-0000-000000000002','f6000000-0000-0000-0000-000000000001','legacy_match',1020,19,1039,NOW()-INTERVAL '30 minutes'),
  ('f6100000-0000-0000-0000-000000000002','f6000000-0000-0000-0000-000000000003','legacy_match',1000,-19,981,NOW()-INTERVAL '30 minutes');
UPDATE public.profiles SET current_elo=1039,total_wins=2 WHERE id='f6000000-0000-0000-0000-000000000001';
UPDATE public.profiles SET current_elo=980,total_losses=1 WHERE id='f6000000-0000-0000-0000-000000000002';
UPDATE public.profiles SET current_elo=981,total_losses=1 WHERE id='f6000000-0000-0000-0000-000000000003';

-- Opening a dispute changes no result, rating, event, or statistic.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000002',TRUE);
SELECT public.create_match_dispute_v3(
  'f6100000-0000-0000-0000-000000000001','incorrect_winner','correction',
  'f6000000-0000-0000-0000-000000000002',11,9
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT current_elo=1039 FROM public.profiles WHERE id='f6000000-0000-0000-0000-000000000001')
  AND (SELECT winner_id='f6000000-0000-0000-0000-000000000001' FROM public.matches WHERE id='f6100000-0000-0000-0000-000000000001')
  AND (SELECT COUNT(*)=4 FROM public.rating_events WHERE match_id IN ('f6100000-0000-0000-0000-000000000001','f6100000-0000-0000-0000-000000000002') AND is_active),
  'a dispute alone must not alter ratings or results'
);

-- Opponent approval applies the correction and replays the downstream match.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000001',TRUE);
SELECT public.respond_match_dispute_v3(
  (SELECT id FROM public.disputes WHERE match_id='f6100000-0000-0000-0000-000000000001' AND status='pending'),
  'approve'
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT winner_id='f6000000-0000-0000-0000-000000000002' AND revision=1
   FROM public.matches WHERE id='f6100000-0000-0000-0000-000000000001')
  AND (SELECT player_one_elo_before=980 AND revision=1
   FROM public.matches WHERE id='f6100000-0000-0000-0000-000000000002'),
  'mutual correction must revise the target and replay downstream rating inputs'
);
SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=2 FROM public.rating_events WHERE match_id='f6100000-0000-0000-0000-000000000001' AND is_active)
  AND (SELECT COUNT(*)=2 FROM public.rating_events WHERE match_id='f6100000-0000-0000-0000-000000000002' AND is_active)
  AND EXISTS(SELECT 1 FROM public.rating_events WHERE match_id='f6100000-0000-0000-0000-000000000001' AND NOT is_active AND superseded_by IS NOT NULL),
  'replay must retain immutable superseded events and exactly one active pair'
);
SELECT pg_temp.assert_true(
  (SELECT current_elo=(SELECT rating_after FROM public.rating_events WHERE match_id='f6100000-0000-0000-0000-000000000002' AND player_id=profiles.id AND is_active)
   FROM public.profiles WHERE id='f6000000-0000-0000-0000-000000000001')
  AND (SELECT total_wins=1 AND total_losses=1 FROM public.profiles WHERE id='f6000000-0000-0000-0000-000000000001'),
  'profile ratings and records must be rebuilt from revised history'
);

-- A mutually approved void removes the target and replays later matches again.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000001',TRUE);
SELECT public.create_match_dispute_v3(
  'f6100000-0000-0000-0000-000000000001','match_never_happened','void',NULL,NULL,NULL
);
SELECT set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000002',TRUE);
SELECT public.respond_match_dispute_v3(
  (SELECT id FROM public.disputes WHERE match_id='f6100000-0000-0000-0000-000000000001' AND status='pending'),
  'approve'
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT status='voided' FROM public.matches WHERE id='f6100000-0000-0000-0000-000000000001')
  AND NOT EXISTS(SELECT 1 FROM public.rating_events WHERE match_id='f6100000-0000-0000-0000-000000000001' AND is_active)
  AND (SELECT player_one_elo_before=1000 AND revision=2 FROM public.matches WHERE id='f6100000-0000-0000-0000-000000000002'),
  'mutual void must remove its active events and replay downstream history'
);

-- Declining a correction escalates with no rating mutation.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000003',TRUE);
SELECT public.create_match_dispute_v3(
  'f6100000-0000-0000-0000-000000000002','incorrect_winner','correction',
  'f6000000-0000-0000-0000-000000000003',11,9
);
SELECT set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000001',TRUE);
SELECT public.respond_match_dispute_v3(
  (SELECT id FROM public.disputes WHERE match_id='f6100000-0000-0000-0000-000000000002' AND status='pending'),
  'decline'
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT status='admin_review' AND response='declined' FROM public.disputes WHERE match_id='f6100000-0000-0000-0000-000000000002')
  AND (SELECT revision=2 FROM public.matches WHERE id='f6100000-0000-0000-0000-000000000002'),
  'decline must escalate without changing the match or rating revision'
);

-- The 48-hour opening deadline is enforced inside PostgreSQL.
INSERT INTO public.matches(
  id,player_one_id,player_two_id,status,source,ranked,ranked_day,winner_id,
  player_one_score,player_two_score,confirmed_at,finalized_at
) VALUES(
  'f6100000-0000-0000-0000-000000000003','f6000000-0000-0000-0000-000000000002','f6000000-0000-0000-0000-000000000003',
  'confirmed','legacy',TRUE,public.club_ranked_day_v3(NOW()-INTERVAL '3 days'),'f6000000-0000-0000-0000-000000000002',11,9,NOW()-INTERVAL '3 days',NOW()-INTERVAL '3 days'
);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000002',TRUE);
DO $$
BEGIN
  PERFORM public.create_match_dispute_v3('f6100000-0000-0000-0000-000000000003','other','void',NULL,NULL,NULL);
  RAISE EXCEPTION 'Expected dispute deadline rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT ILIKE '%48-hour dispute window%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

-- Unrelated users cannot read participant disputes through RLS.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000004',TRUE);
SELECT pg_temp.assert_true((SELECT COUNT(*)=0 FROM public.disputes),'unrelated users must not read disputes');
RESET ROLE;

SELECT pg_temp.assert_true(
  EXISTS(SELECT 1 FROM public.domain_events WHERE event_type='match.dispute_opened')
  AND EXISTS(SELECT 1 FROM public.domain_events WHERE event_type='match.dispute_approved')
  AND EXISTS(SELECT 1 FROM public.domain_events WHERE event_type='match.dispute_escalated'),
  'dispute requests and decisions must create domain audit events'
);

ROLLBACK;
