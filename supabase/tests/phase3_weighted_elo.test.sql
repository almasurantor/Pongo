-- Run only against a disposable Supabase database after all migrations.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

SELECT pg_temp.assert_true(
  (SELECT starting_elo=50 AND k_factor=70 AND win_k_factor=70
    AND loss_k_factor=40 AND score_margin_cap=0
    AND elo_formula_version='asymmetric_elo_v2'
   FROM public.ranking_config WHERE id),
  'ranked configuration must use the 50 baseline and asymmetric K factors'
);

SELECT pg_temp.assert_true(
  public.calculate_weighted_elo_v3(400,400,11,9) @> jsonb_build_object(
    'formula_version','asymmetric_elo_v2','winner_gain',35,
    'loser_loss',20,'floor_applied',FALSE
  ),
  'equal ratings must produce +35 and -20'
);
SELECT pg_temp.assert_true(
  (public.calculate_weighted_elo_v3(400,250,11,9)->>'winner_gain')::INTEGER=21
  AND (public.calculate_weighted_elo_v3(400,250,11,9)->>'loser_loss')::INTEGER=12
  AND (public.calculate_weighted_elo_v3(250,400,11,9)->>'winner_gain')::INTEGER=49
  AND (public.calculate_weighted_elo_v3(250,400,11,9)->>'loser_loss')::INTEGER=28,
  'rating difference must scale expected wins and upsets'
);
SELECT pg_temp.assert_true(
  (public.calculate_weighted_elo_v3(50,10,11,9)->>'loser_loss')::INTEGER=10
  AND (public.calculate_weighted_elo_v3(50,10,11,9)->>'floor_applied')::BOOLEAN,
  'the loss must be clamped at zero ELO'
);
SELECT pg_temp.assert_true(
  (public.calculate_weighted_elo_v3(50,900,11,9)->>'winner_gain')::INTEGER=69
  AND (public.calculate_weighted_elo_v3(50,900,11,9)->>'loser_loss')::INTEGER=40,
  'an Iron upset over Legend must approach the configured K-factor limits'
);

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
SELECT id,email,jsonb_build_object('display_name',name),NOW(),NOW()
FROM (VALUES
  ('f3000000-0000-0000-0000-000000000001'::UUID,'phase3-a@example.test','Phase Three A'),
  ('f3000000-0000-0000-0000-000000000002'::UUID,'phase3-b@example.test','Phase Three B')
) fixtures(id,email,name);

SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=2 AND MIN(current_elo)=50 AND MAX(current_elo)=50
   FROM public.profiles WHERE id IN(
    'f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002'
   )),
  'new profiles must start at the 50-ELO placement baseline'
);

INSERT INTO public.challenges(challenger_id,opponent_id,status,expires_at)
VALUES(
  'f3000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000002','pending',NOW()+INTERVAL '24 hours'
);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f3000000-0000-0000-0000-000000000002',TRUE);
SELECT public.respond_challenge_v2(
  (SELECT id FROM public.challenges WHERE opponent_id=auth.uid() AND status='pending'),'accept'
);
SELECT pg_temp.assert_true(
  public.get_match_rating_preview_v3(
    (SELECT id FROM public.matches WHERE status='ready' AND player_two_id=auth.uid())
  ) @> jsonb_build_object(
    'player_one_rating',50,'player_two_rating',50,
    'player_one_win_change',35,'player_one_loss_change',-20,
    'player_two_win_change',35,'player_two_loss_change',-20,
    'formula_version','asymmetric_elo_v2'
  ),
  'preview must expose the asymmetric win and loss changes'
);
SELECT public.submit_match_report_v2(
  (SELECT id FROM public.matches WHERE status='ready' AND player_two_id=auth.uid()),
  auth.uid(),11,9
);
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT player_one_elo_before=50 AND player_two_elo_before=50
    AND player_one_elo_change=-20 AND player_two_elo_change=35
    AND player_one_elo_change+player_two_elo_change=15
   FROM public.matches WHERE player_one_id='f3000000-0000-0000-0000-000000000001'
     AND player_two_id='f3000000-0000-0000-0000-000000000002' AND status='confirmed'),
  'finalization must apply the intentionally non-zero-sum result'
);
SELECT pg_temp.assert_true(
  (SELECT current_elo=30 AND total_losses=1 FROM public.profiles
   WHERE id='f3000000-0000-0000-0000-000000000001')
  AND (SELECT current_elo=85 AND total_wins=1 FROM public.profiles
   WHERE id='f3000000-0000-0000-0000-000000000002'),
  'first ranked game must place both players from the 50 baseline'
);
SELECT pg_temp.assert_true(
  (SELECT rating_calculation @> jsonb_build_object(
      'formula_version','asymmetric_elo_v2','winner_gain',35,'loser_loss',20
    )
   FROM public.matches WHERE player_one_id='f3000000-0000-0000-0000-000000000001'
     AND player_two_id='f3000000-0000-0000-0000-000000000002' AND status='confirmed')
  AND (SELECT COUNT(*)=2 AND COUNT(calculation)=2 FROM public.rating_events
   WHERE match_id=(SELECT id FROM public.matches
     WHERE player_one_id='f3000000-0000-0000-0000-000000000001'
       AND player_two_id='f3000000-0000-0000-0000-000000000002' AND status='confirmed')),
  'match and immutable ledger rows must retain the formula snapshot'
);

ROLLBACK;
