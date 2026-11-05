-- Repair signup after the mobile ranking expansion.
-- The expand migration made profiles.highest_elo NOT NULL, so the auth trigger
-- must provide it for newly-created users.

BEGIN;

ALTER TABLE public.profiles
  ALTER COLUMN highest_elo SET DEFAULT 1000;

UPDATE public.profiles
SET highest_elo = current_elo
WHERE highest_elo IS NULL;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    display_name,
    current_elo,
    highest_elo,
    total_wins,
    total_losses,
    weekly_wins,
    weekly_losses,
    current_streak,
    longest_streak
  )
  VALUES (
    NEW.id,
    COALESCE(
      NULLIF(NEW.raw_user_meta_data->>'display_name', ''),
      NULLIF(NEW.raw_user_meta_data->>'full_name', ''),
      SPLIT_PART(NEW.email, '@', 1),
      'Player'
    ),
    1000,
    1000,
    0,
    0,
    0,
    0,
    0,
    0
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.player_integrity (player_id)
  VALUES (NEW.id)
  ON CONFLICT (player_id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

COMMIT;
