-- Run only against a disposable Supabase database after all migrations.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN, message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value, FALSE) THEN RAISE EXCEPTION 'Assertion failed: %', message; END IF;
END;
$$;

INSERT INTO auth.users(id, email, raw_user_meta_data, created_at, updated_at)
SELECT id, email, jsonb_build_object('display_name', name), NOW(), NOW()
FROM (VALUES
  ('f3000000-0000-0000-0000-000000000001'::UUID, 'phase3-a@example.test', 'Phase Three A'),
  ('f3000000-0000-0000-0000-000000000002'::UUID, 'phase3-b@example.test', 'Phase Three B'),
  ('f3000000-0000-0000-0000-000000000003'::UUID, 'phase3-c@example.test', 'Phase Three C'),
  ('f3000000-0000-0000-0000-000000000004'::UUID, 'phase3-d@example.test', 'Phase Three D')
) AS fixtures(id, email, name);

SELECT pg_temp.assert_true(
  (SELECT k_factor=40 AND score_margin_cap=0.1000 AND elo_formula_version='weighted_elo_v1'
   FROM public.ranking_config WHERE id),
  'Phase 3 configuration must use K=40 and a 10 percent cap'
);

SELECT pg_temp.assert_true(
  (public.calculate_weighted_elo_v3(1000,1000,11,9)->>'final_delta')::INTEGER=20
  AND (public.calculate_weighted_elo_v3(1000,1000,11,9)->>'margin_bonus')::INTEGER=0,
  'a minimum-margin even match must transfer standard K=40 ELO'
);
SELECT pg_temp.assert_true(
  (public.calculate_weighted_elo_v3(1000,1000,11,0)->>'final_delta')::INTEGER=22
  AND (public.calculate_weighted_elo_v3(1000,1000,11,0)->>'margin_multiplier')::NUMERIC=1.1000,
  'a shutout must receive the capped 10 percent adjustment'
);
SELECT pg_temp.assert_true(
  (public.calculate_weighted_elo_v3(800,1400,11,9)->>'final_delta')::INTEGER >= 38
  AND (public.calculate_weighted_elo_v3(1400,800,11,9)->>'final_delta')::INTEGER <= 2,
  'opponent strength must dominate the adjustment'
);

-- Historical confirmed rows remain untouched and have no fabricated formula.
INSERT INTO public.matches(
  player_one_id,player_two_id,status,source,ranked,ranked_day,winner_id,
  player_one_score,player_two_score,player_one_elo_before,player_two_elo_before,
  player_one_elo_change,player_two_elo_change,confirmed_at,finalized_at
) VALUES (
  'f3000000-0000-0000-0000-000000000003','f3000000-0000-0000-0000-000000000004',
  'confirmed','legacy',TRUE,public.club_ranked_day_v3()-1,'f3000000-0000-0000-0000-000000000003',
  11,9,1000,1000,16,-16,NOW()-INTERVAL '1 day',NOW()-INTERVAL '1 day'
);
SELECT pg_temp.assert_true(
  (SELECT rating_calculation IS NULL AND player_one_elo_change=16
   FROM public.matches WHERE source='legacy' AND player_one_id='f3000000-0000-0000-0000-000000000003'),
  'historical ratings must not be recalculated'
);

-- Preview and finalization use the same stored ratings and formula.
INSERT INTO public.challenges(challenger_id,opponent_id,status,expires_at)
VALUES('f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002','pending',NOW()+INTERVAL '24 hours');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f3000000-0000-0000-0000-000000000002', TRUE);
SELECT public.respond_challenge_v2((SELECT id FROM public.challenges WHERE opponent_id=auth.uid() AND status='pending'), 'accept');
SELECT pg_temp.assert_true(
  (public.get_match_rating_preview_v3((SELECT id FROM public.matches WHERE status='ready' AND player_two_id=auth.uid()))->>'player_two_win_change')::INTEGER=20
  AND (public.get_match_rating_preview_v3((SELECT id FROM public.matches WHERE status='ready' AND player_two_id=auth.uid()))->>'player_two_loss_change')::INTEGER=-20,
  'pre-match prediction must expose close-score win and loss changes'
);
SELECT public.submit_match_report_v2(
  (SELECT id FROM public.matches WHERE status='ready' AND player_two_id=auth.uid()),
  auth.uid(), 11, 0
);
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT player_one_elo_change=-22 AND player_two_elo_change=22
     AND player_one_elo_change+player_two_elo_change=0
   FROM public.matches WHERE player_one_id='f3000000-0000-0000-0000-000000000001'
     AND player_two_id='f3000000-0000-0000-0000-000000000002' AND status='confirmed'),
  'finalization must apply the weighted result as an exact zero-sum transfer'
);
SELECT pg_temp.assert_true(
  (SELECT rating_calculation->>'formula_version'='weighted_elo_v1'
     AND (rating_calculation->>'base_delta')::INTEGER=20
     AND (rating_calculation->>'margin_bonus')::INTEGER=2
     AND (rating_calculation->>'final_delta')::INTEGER=22
   FROM public.matches WHERE player_one_id='f3000000-0000-0000-0000-000000000001'
     AND player_two_id='f3000000-0000-0000-0000-000000000002' AND status='confirmed'),
  'completed matches must retain the full calculation breakdown'
);
SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=2 AND COUNT(calculation)=2
   FROM public.rating_events
   WHERE match_id=(SELECT id FROM public.matches
     WHERE player_one_id='f3000000-0000-0000-0000-000000000001'
       AND player_two_id='f3000000-0000-0000-0000-000000000002' AND status='confirmed')),
  'both immutable rating events must retain the formula snapshot'
);

ROLLBACK;
