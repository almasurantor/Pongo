-- Run only against a disposable Supabase database after all migrations.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

SELECT pg_temp.assert_true(
  EXISTS(
    SELECT 1
    FROM pg_constraint constraint_row
    JOIN pg_class relation ON relation.oid=constraint_row.conrelid
    JOIN pg_namespace schema ON schema.oid=relation.relnamespace
    WHERE schema.nspname='public' AND relation.relname='profiles'
      AND constraint_row.conname='profiles_avatar_config_v2_check'
      AND constraint_row.convalidated
  )
  AND NOT EXISTS(
    SELECT 1
    FROM pg_constraint constraint_row
    JOIN pg_class relation ON relation.oid=constraint_row.conrelid
    JOIN pg_namespace schema ON schema.oid=relation.relnamespace
    WHERE schema.nspname='public' AND relation.relname='profiles'
      AND constraint_row.conname='profiles_avatar_config_v1_check'
  ),
  'the validated v2 avatar constraint must replace v1'
);

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
VALUES(
  'fa200000-0000-4000-8000-000000000001',
  'avatar-options@example.test',
  '{"display_name":"Avatar Options"}'::JSONB,
  NOW(),NOW()
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa200000-0000-4000-8000-000000000001',TRUE);

DO $existing_values$
DECLARE
  config JSONB;
BEGIN
  FOREACH config IN ARRAY ARRAY[
    '{"version":1,"fur":"brown","hat":"none","glasses":"none","facialHair":"none","expression":"happy","accessory":"none"}'::JSONB,
    '{"version":1,"fur":"tan","hat":"baseball-cap","glasses":"sunglasses","facialHair":"mustache","expression":"confident","accessory":"headphones"}'::JSONB,
    '{"version":1,"fur":"cream","hat":"beanie","glasses":"round","facialHair":"short-beard","expression":"sleepy","accessory":"bow"}'::JSONB,
    '{"version":1,"fur":"gray","hat":"crown","glasses":"nerd","facialHair":"goatee","expression":"surprised","accessory":"bandana"}'::JSONB,
    '{"version":1,"fur":"black","hat":"bucket-hat","glasses":"none","facialHair":"none","expression":"mischievous","accessory":"none"}'::JSONB,
    '{"version":1,"fur":"blue","hat":"party-hat","glasses":"sunglasses","facialHair":"mustache","expression":"happy","accessory":"headphones"}'::JSONB,
    '{"version":1,"fur":"pink","hat":"none","glasses":"round","facialHair":"short-beard","expression":"confident","accessory":"bow"}'::JSONB
  ]
  LOOP
    PERFORM public.update_my_avatar_v1(config);
    IF (SELECT avatar_config FROM public.profiles WHERE id=auth.uid()) IS DISTINCT FROM config THEN
      RAISE EXCEPTION 'Existing avatar value did not persist: %',config;
    END IF;
  END LOOP;
END;
$existing_values$;

DO $new_values$
DECLARE
  config JSONB;
BEGIN
  FOREACH config IN ARRAY ARRAY[
    '{"version":1,"fur":"rainbow","hat":"wizard-hat","glasses":"heart","facialHair":"curled-mustache","expression":"angry","accessory":"gold-chain"}'::JSONB,
    '{"version":1,"fur":"tan","hat":"dickhead-hat","glasses":"star","facialHair":"handlebar-mustache","expression":"happy","accessory":"earrings"}'::JSONB,
    '{"version":1,"fur":"cream","hat":"none","glasses":"reading","facialHair":"big-beard","expression":"mischievous","accessory":"medal"}'::JSONB,
    '{"version":1,"fur":"gray","hat":"baseball-cap","glasses":"goggles","facialHair":"wizard-beard","expression":"sleepy","accessory":"paddle"}'::JSONB
  ]
  LOOP
    PERFORM public.update_my_avatar_v1(config);
    IF (SELECT avatar_config FROM public.profiles WHERE id=auth.uid()) IS DISTINCT FROM config THEN
      RAISE EXCEPTION 'Expanded avatar value did not persist: %',config;
    END IF;
  END LOOP;
END;
$new_values$;

DO $invalid_value$
BEGIN
  PERFORM public.update_my_avatar_v1(
    '{"version":1,"fur":"invisible","hat":"none","glasses":"none","facialHair":"none","expression":"happy","accessory":"none"}'::JSONB
  );
  RAISE EXCEPTION 'Expected invalid avatar rejection';
EXCEPTION WHEN check_violation THEN NULL;
END;
$invalid_value$;

RESET ROLE;
ROLLBACK;
