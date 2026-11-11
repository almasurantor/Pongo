-- Expand the layered Pongo avatar vocabulary without rewriting saved avatars.
-- The validated v2 constraint is installed before the original v1 constraint
-- is removed, so every previously valid configuration remains valid throughout.
-- Keep this as one atomic statement so it can also be applied through the
-- Supabase project query endpoint when the database login-role endpoint is
-- unavailable. A failing dependency or validation rolls back the whole block.
DO $migration$
BEGIN
  IF to_regclass('public.profiles') IS NULL
     OR NOT EXISTS(
       SELECT 1
       FROM information_schema.columns
       WHERE table_schema='public' AND table_name='profiles' AND column_name='avatar_config'
     )
     OR to_regprocedure('public.update_my_avatar_v1(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'Missing dependency: apply the avatar configuration migration first';
  END IF;

  ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_avatar_config_v2_check;

  ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_avatar_config_v2_check CHECK (
      avatar_config IS NULL OR (
        jsonb_typeof(avatar_config)='object'
        AND avatar_config ?& ARRAY['version','fur','hat','glasses','facialHair','expression','accessory']
        AND COALESCE(avatar_config->>'version','1')='1'
        AND avatar_config->>'fur' IN(
          'brown','tan','cream','gray','black','blue','pink','rainbow'
        )
        AND avatar_config->>'hat' IN(
          'none','baseball-cap','beanie','crown','bucket-hat','party-hat',
          'wizard-hat','dickhead-hat'
        )
        AND avatar_config->>'glasses' IN(
          'none','sunglasses','round','nerd','heart','star','reading','goggles'
        )
        AND avatar_config->>'facialHair' IN(
          'none','mustache','short-beard','goatee','curled-mustache',
          'handlebar-mustache','big-beard','wizard-beard'
        )
        AND avatar_config->>'expression' IN(
          'happy','confident','sleepy','surprised','mischievous','angry'
        )
        AND avatar_config->>'accessory' IN(
          'none','headphones','bow','bandana','gold-chain','earrings','medal','paddle'
        )
      )
    ) NOT VALID;

  ALTER TABLE public.profiles
    VALIDATE CONSTRAINT profiles_avatar_config_v2_check;

  ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_avatar_config_v1_check;

  COMMENT ON CONSTRAINT profiles_avatar_config_v2_check ON public.profiles IS
    'Validates version 1 layered Pongo avatars, including the expanded 2026 option set.';

  PERFORM pg_catalog.pg_notify('pgrst','reload schema');
END;
$migration$;
