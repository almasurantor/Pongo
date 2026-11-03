-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table (extends Supabase auth.users)
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL CHECK (
    display_name=BTRIM(display_name)
    AND CHAR_LENGTH(display_name) BETWEEN 3 AND 20
    AND display_name ~ '^[A-Za-z0-9][A-Za-z0-9 _.]*[A-Za-z0-9]$'
  ),
  queue_turn_sound_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  queue_turn_push_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  current_elo INTEGER NOT NULL DEFAULT 500,
  total_wins INTEGER NOT NULL DEFAULT 0,
  total_losses INTEGER NOT NULL DEFAULT 0,
  weekly_wins INTEGER NOT NULL DEFAULT 0,
  weekly_losses INTEGER NOT NULL DEFAULT 0,
  highest_elo INTEGER NOT NULL DEFAULT 500,
  current_streak INTEGER NOT NULL DEFAULT 0,
  longest_streak INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Challenges table
CREATE TABLE public.challenges (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  challenger_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  opponent_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'expired', 'completed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '2 hours'),
  CONSTRAINT no_self_challenge CHECK (challenger_id != opponent_id)
);

-- Matches table
CREATE TABLE public.matches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  challenge_id UUID REFERENCES public.challenges(id) ON DELETE SET NULL,
  player_one_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  player_two_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  player_one_score INTEGER,
  player_two_score INTEGER,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'pending_confirmation', 'disputed', 'confirmed', 'auto_expired')),
  reported_by UUID REFERENCES public.profiles(id),
  reported_at TIMESTAMPTZ,
  confirmed_by UUID REFERENCES public.profiles(id),
  disputed_by UUID REFERENCES public.profiles(id),
  disputed_at TIMESTAMPTZ,
  dispute_reason TEXT,
  expires_at TIMESTAMPTZ,
  player_one_elo_before INTEGER,
  player_two_elo_before INTEGER,
  player_one_elo_change INTEGER,
  player_two_elo_change INTEGER,
  confirmed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT no_self_match CHECK (player_one_id != player_two_id),
  CONSTRAINT valid_score CHECK (
    (player_one_score IS NULL AND player_two_score IS NULL) OR
    (player_one_score IS NOT NULL AND player_two_score IS NOT NULL AND player_one_score >= 0 AND player_two_score >= 0)
  )
);

-- Match history view (for easier querying)
CREATE VIEW public.match_history AS
SELECT 
  m.id,
  m.player_one_id,
  m.player_two_id,
  m.player_one_score,
  m.player_two_score,
  m.player_one_elo_change,
  m.player_two_elo_change,
  m.confirmed_at,
  m.created_at,
  CASE 
    WHEN m.player_one_score > m.player_two_score THEN m.player_one_id
    WHEN m.player_two_score > m.player_one_score THEN m.player_two_id
    ELSE NULL
  END AS winner_id
FROM public.matches m
WHERE m.status = 'confirmed';

-- Indexes for performance
CREATE INDEX idx_challenges_challenger ON public.challenges(challenger_id);
CREATE INDEX idx_challenges_opponent ON public.challenges(opponent_id);
CREATE INDEX idx_challenges_status ON public.challenges(status);
CREATE INDEX idx_challenges_expires_at ON public.challenges(expires_at);
-- Prevent duplicate pending challenges (either direction)
CREATE UNIQUE INDEX unique_pending_challenge_pair
ON public.challenges (
  LEAST(challenger_id, opponent_id),
  GREATEST(challenger_id, opponent_id)
)
WHERE status = 'pending';
CREATE INDEX idx_matches_player_one ON public.matches(player_one_id);
CREATE INDEX idx_matches_player_two ON public.matches(player_two_id);
CREATE INDEX idx_matches_status ON public.matches(status);
CREATE INDEX idx_matches_confirmed_at ON public.matches(confirmed_at);
CREATE INDEX idx_profiles_elo ON public.profiles(current_elo DESC);
CREATE UNIQUE INDEX profiles_display_name_unique_v4 ON public.profiles(LOWER(display_name));

-- Function to check daily match limit
CREATE OR REPLACE FUNCTION check_daily_match_limit(
  p_player_one_id UUID,
  p_player_two_id UUID
) RETURNS BOOLEAN AS $$
DECLARE
  match_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO match_count
  FROM public.matches
  WHERE status = 'confirmed'
    AND confirmed_at >= CURRENT_DATE
    AND (
      (player_one_id = p_player_one_id AND player_two_id = p_player_two_id) OR
      (player_one_id = p_player_two_id AND player_two_id = p_player_one_id)
    );
  
  RETURN match_count < 20;
END;
$$ LANGUAGE plpgsql;

-- Function to expire old challenges
CREATE OR REPLACE FUNCTION expire_old_challenges()
RETURNS void AS $$
BEGIN
  UPDATE public.challenges
  SET status = 'expired'
  WHERE status = 'pending'
    AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- Function to expire reported results that were never resolved
CREATE OR REPLACE FUNCTION expire_unconfirmed_matches()
RETURNS void AS $$
BEGIN
  UPDATE public.matches
  SET status = 'auto_expired'
  WHERE status IN ('pending_confirmation', 'disputed')
    AND expires_at IS NOT NULL
    AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION is_valid_match_score(p_one INTEGER, p_two INTEGER)
RETURNS BOOLEAN AS $$
  SELECT COALESCE(p_one >= 0 AND p_two >= 0 AND p_one <> p_two
    AND GREATEST(p_one, p_two) >= 11
    AND ABS(p_one - p_two) >= 2
    AND NOT (GREATEST(p_one, p_two) > 11 AND (LEAST(p_one, p_two) < 10 OR ABS(p_one - p_two) <> 2)), FALSE);
$$ LANGUAGE sql IMMUTABLE;

-- A participant reports both scores. After a dispute, only that reporter may revise them.
CREATE OR REPLACE FUNCTION report_match_result(p_match_id UUID, p_player_one_score INTEGER, p_player_two_score INTEGER)
RETURNS public.matches AS $$
DECLARE m public.matches;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF auth.uid() IS NULL OR auth.uid() NOT IN (m.player_one_id, m.player_two_id) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  IF m.status NOT IN ('active', 'disputed') THEN RAISE EXCEPTION 'This result cannot be reported now'; END IF;
  IF m.status = 'disputed' AND m.reported_by <> auth.uid() THEN
    RAISE EXCEPTION 'Only the original reporter can revise a disputed result';
  END IF;
  IF NOT public.is_valid_match_score(p_player_one_score, p_player_two_score) THEN
    RAISE EXCEPTION 'Invalid score';
  END IF;
  UPDATE public.matches SET
    player_one_score = p_player_one_score, player_two_score = p_player_two_score,
    reported_by = COALESCE(reported_by, auth.uid()), reported_at = NOW(),
    status = 'pending_confirmation', confirmed_by = NULL,
    disputed_by = NULL, disputed_at = NULL, dispute_reason = NULL,
    expires_at = NOW() + INTERVAL '24 hours'
  WHERE id = p_match_id RETURNING * INTO m;
  RETURN m;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION dispute_match_result(p_match_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS public.matches AS $$
DECLARE m public.matches;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF m.status <> 'pending_confirmation' THEN RAISE EXCEPTION 'This result is not awaiting confirmation'; END IF;
  IF auth.uid() IS NULL OR auth.uid() NOT IN (m.player_one_id, m.player_two_id) OR auth.uid() = m.reported_by THEN
    RAISE EXCEPTION 'Only the reporting player''s opponent can dispute this result';
  END IF;
  UPDATE public.matches SET status = 'disputed', disputed_by = auth.uid(), disputed_at = NOW(),
    dispute_reason = NULLIF(LEFT(TRIM(p_reason), 500), ''), expires_at = NOW() + INTERVAL '24 hours'
  WHERE id = p_match_id RETURNING * INTO m;
  RETURN m;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Confirm and apply ratings/stats in one locked transaction, preventing duplicate updates.
CREATE OR REPLACE FUNCTION confirm_match_result(p_match_id UUID)
RETURNS JSONB AS $$
DECLARE
  m public.matches; p1 public.profiles; p2 public.profiles;
  expected_one NUMERIC; margin NUMERIC; actual_one NUMERIC;
  change_one INTEGER; change_two INTEGER;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF m.status <> 'pending_confirmation' THEN RAISE EXCEPTION 'This result is not awaiting confirmation'; END IF;
  IF auth.uid() IS NULL OR auth.uid() NOT IN (m.player_one_id, m.player_two_id) OR auth.uid() = m.reported_by THEN
    RAISE EXCEPTION 'Only the reporting player''s opponent can confirm this result';
  END IF;
  IF NOT public.is_valid_match_score(m.player_one_score, m.player_two_score) THEN
    RAISE EXCEPTION 'Invalid score';
  END IF;

  PERFORM id FROM public.profiles WHERE id IN (m.player_one_id, m.player_two_id) ORDER BY id FOR UPDATE;
  SELECT * INTO p1 FROM public.profiles WHERE id = m.player_one_id;
  SELECT * INTO p2 FROM public.profiles WHERE id = m.player_two_id;
  expected_one := 1.0 / (1.0 + POWER(10.0, (p2.current_elo - p1.current_elo) / 400.0));
  actual_one := CASE WHEN m.player_one_score > m.player_two_score THEN 1.0 ELSE 0.0 END;
  margin := CASE WHEN ABS(m.player_one_score - m.player_two_score) <= 2 THEN 1.0
    WHEN ABS(m.player_one_score - m.player_two_score) <= 5 THEN 1.1
    WHEN ABS(m.player_one_score - m.player_two_score) <= 8 THEN 1.2 ELSE 1.25 END;
  -- FLOOR(x + .5) matches JavaScript Math.round, including negative half-values.
  change_one := FLOOR(32 * margin * (actual_one - expected_one) + 0.5);
  change_two := FLOOR(32 * margin * ((1 - actual_one) - (1 - expected_one)) + 0.5);

  UPDATE public.profiles SET current_elo = current_elo + change_one,
    total_wins = total_wins + CASE WHEN actual_one = 1 THEN 1 ELSE 0 END,
    total_losses = total_losses + CASE WHEN actual_one = 1 THEN 0 ELSE 1 END,
    weekly_wins = weekly_wins + CASE WHEN actual_one = 1 THEN 1 ELSE 0 END,
    weekly_losses = weekly_losses + CASE WHEN actual_one = 1 THEN 0 ELSE 1 END,
    updated_at = NOW() WHERE id = m.player_one_id;
  UPDATE public.profiles SET current_elo = current_elo + change_two,
    total_wins = total_wins + CASE WHEN actual_one = 0 THEN 1 ELSE 0 END,
    total_losses = total_losses + CASE WHEN actual_one = 0 THEN 0 ELSE 1 END,
    weekly_wins = weekly_wins + CASE WHEN actual_one = 0 THEN 1 ELSE 0 END,
    weekly_losses = weekly_losses + CASE WHEN actual_one = 0 THEN 0 ELSE 1 END,
    updated_at = NOW() WHERE id = m.player_two_id;
  UPDATE public.matches SET status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = NOW(),
    expires_at = NULL, player_one_elo_before = p1.current_elo, player_two_elo_before = p2.current_elo,
    player_one_elo_change = change_one, player_two_elo_change = change_two WHERE id = p_match_id;
  IF m.challenge_id IS NOT NULL THEN UPDATE public.challenges SET status = 'completed' WHERE id = m.challenge_id; END IF;
  RETURN jsonb_build_object('eloChanges', jsonb_build_object(
    'player_one', change_one, 'player_two', change_two,
    'player_one_new', p1.current_elo + change_one, 'player_two_new', p2.current_elo + change_two));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Function to reset weekly stats (called by cron)
CREATE OR REPLACE FUNCTION reset_weekly_stats()
RETURNS void AS $$
BEGIN
  UPDATE public.profiles
  SET 
    weekly_wins = 0,
    weekly_losses = 0,
    updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- Function to update both players' stats after match confirmation
-- Uses SECURITY DEFINER to bypass RLS
CREATE OR REPLACE FUNCTION update_match_stats(
  p_match_id UUID,
  p_player_one_id UUID,
  p_player_two_id UUID,
  p_player_one_new_elo INTEGER,
  p_player_two_new_elo INTEGER,
  p_player_one_won BOOLEAN
)
RETURNS void AS $$
BEGIN
  -- Update player one
  UPDATE public.profiles
  SET 
    current_elo = p_player_one_new_elo,
    total_wins = total_wins + CASE WHEN p_player_one_won THEN 1 ELSE 0 END,
    total_losses = total_losses + CASE WHEN p_player_one_won THEN 0 ELSE 1 END,
    weekly_wins = weekly_wins + CASE WHEN p_player_one_won THEN 1 ELSE 0 END,
    weekly_losses = weekly_losses + CASE WHEN p_player_one_won THEN 0 ELSE 1 END,
    updated_at = NOW()
  WHERE id = p_player_one_id;

  -- Update player two
  UPDATE public.profiles
  SET 
    current_elo = p_player_two_new_elo,
    total_wins = total_wins + CASE WHEN p_player_one_won THEN 0 ELSE 1 END,
    total_losses = total_losses + CASE WHEN p_player_one_won THEN 1 ELSE 0 END,
    weekly_wins = weekly_wins + CASE WHEN p_player_one_won THEN 0 ELSE 1 END,
    weekly_losses = weekly_losses + CASE WHEN p_player_one_won THEN 1 ELSE 0 END,
    updated_at = NOW()
  WHERE id = p_player_two_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to update updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Function to create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
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
    candidate,
    500,
    500,
    0,
    0,
    0,
    0,
    0,
    0
  )
  ON CONFLICT (id) DO NOTHING;

      EXIT;
    EXCEPTION WHEN unique_violation THEN
      suffix_text:='_'||suffix::TEXT;
      candidate:=LEFT(base_name,20-CHAR_LENGTH(suffix_text))||suffix_text;
      suffix:=suffix+1;
    END;
  END LOOP;

  IF to_regclass('public.player_integrity') IS NOT NULL THEN
    EXECUTE 'INSERT INTO public.player_integrity (player_id) VALUES ($1) ON CONFLICT (player_id) DO NOTHING'
    USING NEW.id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Trigger to create profile on user signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

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
  RETURN jsonb_build_object('normalized',normalized,'valid',valid,'available',available);
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
    WHERE LOWER(profile.display_name)=LOWER(normalized) AND profile.id<>player_id
  ) THEN RAISE EXCEPTION 'Name already taken'; END IF;
  BEGIN
    UPDATE public.profiles SET
      display_name=normalized,
      queue_turn_sound_enabled=COALESCE(p_queue_turn_sound_enabled,TRUE),
      queue_turn_push_enabled=COALESCE(p_queue_turn_push_enabled,FALSE),
      updated_at=NOW()
    WHERE id=player_id RETURNING * INTO updated;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Name already taken';
  END;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;
  UPDATE auth.users SET
    raw_user_meta_data=jsonb_set(COALESCE(raw_user_meta_data,'{}'::JSONB),'{display_name}',to_jsonb(normalized),TRUE),
    updated_at=NOW()
  WHERE id=player_id;
  IF to_regclass('public.beaver_queue_members') IS NOT NULL THEN
    EXECUTE 'UPDATE public.beaver_queue_members SET display_name=$1,updated_at=NOW() WHERE user_id=$2'
    USING normalized,player_id;
  END IF;
  RETURN updated;
END;
$$;

-- RLS Policies
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;

-- Profiles: Everyone can read, only own profile can update
CREATE POLICY "Profiles are viewable by everyone"
  ON public.profiles FOR SELECT
  USING (true);

CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- Users may edit their display name, but ratings and records are server-owned.
REVOKE UPDATE ON TABLE public.profiles FROM authenticated;

-- Challenges: Users can read only their own (challenger/opponent); Realtime needs this for delivery
DROP POLICY IF EXISTS "Challenges are viewable by everyone" ON public.challenges;
CREATE POLICY "Users can view their own challenges"
  ON public.challenges FOR SELECT
  USING (auth.uid() = challenger_id OR auth.uid() = opponent_id);

CREATE POLICY "Users can create challenges"
  ON public.challenges FOR INSERT
  WITH CHECK (auth.uid() = challenger_id);

CREATE POLICY "Users can update own challenges or challenges they're involved in"
  ON public.challenges FOR UPDATE
  USING (auth.uid() = challenger_id OR auth.uid() = opponent_id);

-- Matches: Users can read only their own; Realtime needs this for delivery
DROP POLICY IF EXISTS "Matches are viewable by everyone" ON public.matches;
CREATE POLICY "Users can view their matches"
  ON public.matches FOR SELECT
  USING (auth.uid() = player_one_id OR auth.uid() = player_two_id);

CREATE POLICY "Users can create active matches"
  ON public.matches FOR INSERT
  WITH CHECK (
    (auth.uid() = player_one_id OR auth.uid() = player_two_id)
    AND status = 'active' AND player_one_score IS NULL AND player_two_score IS NULL
    AND reported_by IS NULL AND confirmed_by IS NULL AND disputed_by IS NULL
    AND reported_at IS NULL AND confirmed_at IS NULL AND disputed_at IS NULL
    AND player_one_elo_change IS NULL AND player_two_elo_change IS NULL
  );

-- Match state is updated only by the role-aware result functions above.
REVOKE EXECUTE ON FUNCTION public.report_match_result(UUID, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.dispute_match_result(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.confirm_match_result(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.expire_unconfirmed_matches() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_match_stats(UUID, UUID, UUID, INTEGER, INTEGER, BOOLEAN) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.report_match_result(UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dispute_match_result(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_match_result(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_unconfirmed_matches() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.check_display_name_available_v4(TEXT) FROM PUBLIC,anon;
REVOKE EXECUTE ON FUNCTION public.update_my_profile_settings_v4(TEXT,BOOLEAN,BOOLEAN) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.check_display_name_available_v4(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_my_profile_settings_v4(TEXT,BOOLEAN,BOOLEAN) TO authenticated;

-- Enable Realtime for tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.challenges;
ALTER PUBLICATION supabase_realtime ADD TABLE public.matches;
