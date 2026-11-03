-- Pongo V4: safe public names and single-purpose queue reminder settings.
BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS queue_turn_sound_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS queue_turn_push_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Bring legacy names into the new contract without replacing profile rows or
-- touching ratings/statistics. Duplicate names receive a short numeric suffix.
DO $normalize_existing_names$
DECLARE
  player RECORD;
  base_name TEXT;
  candidate TEXT;
  suffix INTEGER;
  suffix_text TEXT;
BEGIN
  FOR player IN
    SELECT id,display_name FROM public.profiles ORDER BY created_at,id
  LOOP
    base_name:=regexp_replace(BTRIM(COALESCE(player.display_name,'')),'[[:space:]]+',' ','g');
    base_name:=regexp_replace(base_name,'[^A-Za-z0-9 _.]','','g');
    base_name:=BTRIM(base_name,' _.');
    IF CHAR_LENGTH(base_name)<3 THEN
      base_name:='Player_'||SUBSTRING(REPLACE(player.id::TEXT,'-','') FROM 1 FOR 8);
    END IF;
    base_name:=LEFT(base_name,20);
    candidate:=base_name;
    suffix:=2;
    WHILE EXISTS(
      SELECT 1 FROM public.profiles existing
      WHERE existing.id<>player.id AND LOWER(existing.display_name)=LOWER(candidate)
    ) LOOP
      suffix_text:='_'||suffix::TEXT;
      candidate:=LEFT(base_name,20-CHAR_LENGTH(suffix_text))||suffix_text;
      suffix:=suffix+1;
    END LOOP;
    UPDATE public.profiles SET display_name=candidate WHERE id=player.id;
  END LOOP;
END;
$normalize_existing_names$;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_display_name_v4_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_display_name_v4_check CHECK (
  display_name=BTRIM(display_name)
  AND CHAR_LENGTH(display_name) BETWEEN 3 AND 20
  AND display_name ~ '^[A-Za-z0-9][A-Za-z0-9 _.]*[A-Za-z0-9]$'
);

CREATE UNIQUE INDEX IF NOT EXISTS profiles_display_name_unique_v4
  ON public.profiles(LOWER(display_name));

-- Signup metadata is user supplied, so apply the same contract here and pick
-- a short suffix when a requested public name is already in use.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  base_name TEXT;
  candidate TEXT;
  suffix INTEGER:=2;
  suffix_text TEXT;
BEGIN
  base_name:=COALESCE(
    NULLIF(NEW.raw_user_meta_data->>'display_name',''),
    NULLIF(NEW.raw_user_meta_data->>'full_name',''),
    NULLIF(SPLIT_PART(NEW.email,'@',1),''),
    'Player'
  );
  base_name:=regexp_replace(BTRIM(base_name),'[[:space:]]+',' ','g');
  base_name:=regexp_replace(base_name,'[^A-Za-z0-9 _.]','','g');
  base_name:=BTRIM(LEFT(base_name,20),' _.');
  IF CHAR_LENGTH(base_name)<3 THEN
    base_name:='Player_'||SUBSTRING(REPLACE(NEW.id::TEXT,'-','') FROM 1 FOR 8);
  END IF;
  candidate:=base_name;

  LOOP
    BEGIN
      INSERT INTO public.profiles(
        id,display_name,current_elo,highest_elo,total_wins,total_losses,
        weekly_wins,weekly_losses,current_streak,longest_streak
      ) VALUES(NEW.id,candidate,500,500,0,0,0,0,0,0)
      ON CONFLICT(id) DO NOTHING;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      suffix_text:='_'||suffix::TEXT;
      candidate:=LEFT(base_name,20-CHAR_LENGTH(suffix_text))||suffix_text;
      suffix:=suffix+1;
    END;
  END LOOP;

  INSERT INTO public.player_integrity(player_id)
  VALUES(NEW.id) ON CONFLICT(player_id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_display_name_available_v4(p_name TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  normalized TEXT:=BTRIM(COALESCE(p_name,''));
  valid BOOLEAN;
  available BOOLEAN:=FALSE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  valid:=CHAR_LENGTH(normalized) BETWEEN 3 AND 20
    AND normalized ~ '^[A-Za-z0-9][A-Za-z0-9 _.]*[A-Za-z0-9]$';
  IF valid THEN
    available:=NOT EXISTS(
      SELECT 1 FROM public.profiles profile
      WHERE LOWER(profile.display_name)=LOWER(normalized)
        AND profile.id<>auth.uid()
    );
  END IF;
  RETURN jsonb_build_object(
    'normalized',normalized,
    'valid',valid,
    'available',available
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.update_my_profile_settings_v4(
  p_display_name TEXT,
  p_queue_turn_sound_enabled BOOLEAN,
  p_queue_turn_push_enabled BOOLEAN
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  normalized TEXT:=BTRIM(COALESCE(p_display_name,''));
  updated public.profiles;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  IF CHAR_LENGTH(normalized) NOT BETWEEN 3 AND 20
     OR normalized !~ '^[A-Za-z0-9][A-Za-z0-9 _.]*[A-Za-z0-9]$' THEN
    RAISE EXCEPTION 'Name must be 3–20 characters using letters, numbers, spaces, underscores, or periods';
  END IF;
  IF EXISTS(
    SELECT 1 FROM public.profiles profile
    WHERE LOWER(profile.display_name)=LOWER(normalized)
      AND profile.id<>player_id
  ) THEN RAISE EXCEPTION 'Name already taken'; END IF;

  BEGIN
    UPDATE public.profiles SET
      display_name=normalized,
      queue_turn_sound_enabled=COALESCE(p_queue_turn_sound_enabled,TRUE),
      queue_turn_push_enabled=COALESCE(p_queue_turn_push_enabled,FALSE),
      updated_at=NOW()
    WHERE id=player_id
    RETURNING * INTO updated;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Name already taken';
  END;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

  UPDATE auth.users SET
    raw_user_meta_data=jsonb_set(
      COALESCE(raw_user_meta_data,'{}'::JSONB),'{display_name}',to_jsonb(normalized),TRUE
    ),
    updated_at=NOW()
  WHERE id=player_id;

  IF to_regclass('public.beaver_queue_members') IS NOT NULL THEN
    EXECUTE 'UPDATE public.beaver_queue_members SET display_name=$1,updated_at=NOW() WHERE user_id=$2'
    USING normalized,player_id;
  END IF;
  RETURN updated;
END;
$$;

REVOKE UPDATE(display_name) ON public.profiles FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.check_display_name_available_v4(TEXT) FROM PUBLIC,anon;
REVOKE EXECUTE ON FUNCTION public.update_my_profile_settings_v4(TEXT,BOOLEAN,BOOLEAN) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.check_display_name_available_v4(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_my_profile_settings_v4(TEXT,BOOLEAN,BOOLEAN) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC,anon,authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
