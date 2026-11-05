-- Local experimental feature: composable Pongo avatar configuration.
-- Additive only; existing profile fields and behavior remain unchanged.
BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS avatar_config JSONB;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_avatar_config_v1_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_avatar_config_v1_check CHECK (
    avatar_config IS NULL OR (
      jsonb_typeof(avatar_config) = 'object'
      AND avatar_config ?& ARRAY['version','fur','hat','glasses','facialHair','expression','accessory']
      AND COALESCE(avatar_config->>'version','1') = '1'
      AND avatar_config->>'fur' IN ('brown','tan','cream','gray','black','blue','pink')
      AND avatar_config->>'hat' IN ('none','baseball-cap','beanie','crown','bucket-hat','party-hat')
      AND avatar_config->>'glasses' IN ('none','sunglasses','round','nerd')
      AND avatar_config->>'facialHair' IN ('none','mustache','short-beard','goatee')
      AND avatar_config->>'expression' IN ('happy','confident','sleepy','surprised','mischievous')
      AND avatar_config->>'accessory' IN ('none','headphones','bow','bandana')
    )
  );

CREATE OR REPLACE FUNCTION public.update_my_avatar_v1(p_avatar_config JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  player_id UUID := auth.uid();
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF p_avatar_config IS NULL THEN RAISE EXCEPTION 'Avatar configuration required'; END IF;

  UPDATE public.profiles
  SET avatar_config = p_avatar_config, updated_at = NOW()
  WHERE id = player_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;
  RETURN p_avatar_config;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_my_avatar_v1(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_my_avatar_v1(JSONB) TO authenticated;
GRANT SELECT(avatar_config) ON public.profiles TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
