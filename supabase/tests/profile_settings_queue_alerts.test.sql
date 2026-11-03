-- Run only against a disposable Supabase database after all migrations.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
VALUES
  ('fb000000-0000-0000-0000-000000000001','settings-a@example.test','{"display_name":"Pongo Tester"}'::JSONB,NOW(),NOW()),
  ('fb000000-0000-0000-0000-000000000002','settings-b@example.test','{"display_name":"Pongo Rival"}'::JSONB,NOW(),NOW()),
  ('fb000000-0000-0000-0000-000000000003','settings-c@example.test','{"display_name":"pongo tester"}'::JSONB,NOW(),NOW());

SELECT pg_temp.assert_true(
  (SELECT display_name='Pongo Tester' FROM public.profiles
   WHERE id='fb000000-0000-0000-0000-000000000001')
  AND (SELECT display_name='Pongo Tester_2' FROM public.profiles
       WHERE id='fb000000-0000-0000-0000-000000000003'),
  'signup must preserve an available name and suffix a case-insensitive collision'
);

INSERT INTO public.beaver_queue_members(
  user_id,display_name,status,queue_position,joined_at,updated_at
) VALUES(
  'fb000000-0000-0000-0000-000000000001','Pongo Tester','left',900001,NOW(),NOW()
);

UPDATE public.profiles SET current_elo=777,total_wins=4,total_losses=2
WHERE id='fb000000-0000-0000-0000-000000000001';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-0000-0000-000000000001',TRUE);
SELECT pg_temp.assert_true(
  (public.check_display_name_available_v4('pongo rival')->>'available')::BOOLEAN=FALSE
  AND (public.check_display_name_available_v4('Pongo Tester')->>'available')::BOOLEAN=TRUE
  AND (public.check_display_name_available_v4('bad!')->>'valid')::BOOLEAN=FALSE,
  'availability must be case-insensitive, exclude the current player, and validate characters'
);
SELECT public.update_my_profile_settings_v4('Pongo Renamed',FALSE,TRUE);
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT display_name='Pongo Renamed'
      AND queue_turn_sound_enabled=FALSE
      AND queue_turn_push_enabled=TRUE
      AND current_elo=777 AND total_wins=4 AND total_losses=2
   FROM public.profiles WHERE id='fb000000-0000-0000-0000-000000000001')
  AND (SELECT display_name='Pongo Renamed' FROM public.beaver_queue_members
       WHERE user_id='fb000000-0000-0000-0000-000000000001')
  AND (SELECT raw_user_meta_data->>'display_name'='Pongo Renamed' FROM auth.users
       WHERE id='fb000000-0000-0000-0000-000000000001'),
  'settings update must preserve ranked stats and update profile, auth metadata, and active queue identity'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-0000-0000-000000000001',TRUE);
DO $$
BEGIN
  PERFORM public.update_my_profile_settings_v4('PONGO RIVAL',TRUE,FALSE);
  RAISE EXCEPTION 'Expected duplicate display name rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected duplicate display name rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%already taken%' THEN RAISE; END IF;
END;
$$;
DO $$
BEGIN
  UPDATE public.profiles SET display_name='Direct Change'
  WHERE id='fb000000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'Expected direct profile update rejection';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END;
$$;
RESET ROLE;

ROLLBACK;
