-- Pongo mobile ranking platform: additive/legacy-compatible expansion.
-- Apply this before deploying the matching application. It intentionally keeps
-- the legacy submission columns and status names until the contract migration.
BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS public.ranking_config (
  id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
  starting_elo INTEGER NOT NULL DEFAULT 1000 CHECK (starting_elo > 0),
  k_factor INTEGER NOT NULL DEFAULT 32 CHECK (k_factor > 0),
  daily_ranked_pair_limit INTEGER NOT NULL DEFAULT 20 CHECK (daily_ranked_pair_limit > 0),
  challenge_expiry_hours INTEGER NOT NULL DEFAULT 24 CHECK (challenge_expiry_hours > 0),
  result_expiry_hours INTEGER NOT NULL DEFAULT 24 CHECK (result_expiry_hours > 0),
  max_score INTEGER NOT NULL DEFAULT 99 CHECK (max_score >= 11),
  ledger_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO public.ranking_config (id) VALUES (TRUE) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS highest_elo INTEGER;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS current_streak INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS longest_streak INTEGER NOT NULL DEFAULT 0;
UPDATE public.profiles SET highest_elo = current_elo WHERE highest_elo IS NULL;
ALTER TABLE public.profiles ALTER COLUMN highest_elo SET NOT NULL;

CREATE TABLE IF NOT EXISTS public.user_roles (
  user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('admin')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.player_integrity (
  player_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  verification_level TEXT NOT NULL DEFAULT 'normal'
    CHECK (verification_level IN ('normal', 'monitored', 'dual_verification', 'ranked_restricted')),
  confirmed_violations INTEGER NOT NULL DEFAULT 0 CHECK (confirmed_violations >= 0),
  restriction_reason TEXT,
  updated_by UUID REFERENCES public.profiles(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO public.player_integrity (player_id)
SELECT id FROM public.profiles ON CONFLICT (player_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.profile_stat_baselines (
  player_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating INTEGER NOT NULL,
  total_wins INTEGER NOT NULL,
  total_losses INTEGER NOT NULL,
  weekly_wins INTEGER NOT NULL,
  weekly_losses INTEGER NOT NULL,
  highest_elo INTEGER NOT NULL,
  current_streak INTEGER NOT NULL,
  longest_streak INTEGER NOT NULL,
  captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO public.profile_stat_baselines
  (player_id, rating, total_wins, total_losses, weekly_wins, weekly_losses,
   highest_elo, current_streak, longest_streak)
SELECT id, current_elo, total_wins, total_losses, weekly_wins, weekly_losses,
       highest_elo, current_streak, longest_streak
FROM public.profiles
ON CONFLICT (player_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.seasons (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL UNIQUE,
  starts_on DATE,
  ends_on DATE,
  is_active BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT season_dates_valid CHECK (starts_on IS NULL OR ends_on IS NULL OR starts_on <= ends_on)
);
CREATE UNIQUE INDEX IF NOT EXISTS one_active_season ON public.seasons (is_active) WHERE is_active;

ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'challenge'
  CHECK (source IN ('challenge', 'spontaneous', 'legacy'));
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS ranked BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS winner_id UUID REFERENCES public.profiles(id);
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS reported_by UUID REFERENCES public.profiles(id);
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS reported_at TIMESTAMPTZ;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS confirmed_by UUID REFERENCES public.profiles(id);
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS disputed_by UUID REFERENCES public.profiles(id);
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS disputed_at TIMESTAMPTZ;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS dispute_reason TEXT;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS verification_mode TEXT NOT NULL DEFAULT 'normal'
  CHECK (verification_mode IN ('normal', 'dual'));
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS request_id UUID;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS finalized_at TIMESTAMPTZ;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS season_id UUID REFERENCES public.seasons(id) ON DELETE SET NULL;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS revision INTEGER NOT NULL DEFAULT 0;

UPDATE public.matches SET source = CASE WHEN challenge_id IS NULL THEN 'legacy' ELSE 'challenge' END;
UPDATE public.matches SET winner_id = CASE
  WHEN player_one_score > player_two_score THEN player_one_id
  WHEN player_two_score > player_one_score THEN player_two_id END
WHERE status = 'confirmed' AND winner_id IS NULL;
UPDATE public.matches SET finalized_at = confirmed_at WHERE status = 'confirmed' AND finalized_at IS NULL;

ALTER TABLE public.matches DROP CONSTRAINT IF EXISTS matches_status_check;
ALTER TABLE public.matches ADD CONSTRAINT matches_status_check CHECK (status IN (
  'active', 'pending_confirmation', 'disputed', 'auto_expired',
  'ready', 'result_reported', 'awaiting_independent_report',
  'correction_proposed', 'admin_review', 'confirmed', 'expired', 'voided'
));
ALTER TABLE public.challenges DROP CONSTRAINT IF EXISTS challenges_status_check;
ALTER TABLE public.challenges ADD CONSTRAINT challenges_status_check
  CHECK (status IN ('pending', 'accepted', 'declined', 'expired', 'completed'));
ALTER TABLE public.challenges ALTER COLUMN expires_at SET DEFAULT (NOW() + INTERVAL '24 hours');

CREATE UNIQUE INDEX IF NOT EXISTS unique_match_request_id ON public.matches(request_id) WHERE request_id IS NOT NULL;
-- Do not add a challenge_id uniqueness constraint here: the legacy project has
-- historical duplicate challenge links. New accepts are serialized by locking
-- the pending challenge row before inserting their match.
CREATE INDEX IF NOT EXISTS idx_matches_winner ON public.matches(winner_id);
CREATE INDEX IF NOT EXISTS idx_matches_reported_by ON public.matches(reported_by);

CREATE TABLE IF NOT EXISTS public.rating_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  match_id UUID REFERENCES public.matches(id) ON DELETE RESTRICT,
  player_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  event_kind TEXT NOT NULL CHECK (event_kind IN ('match_result', 'legacy_match', 'opening_balance', 'migration_adjustment', 'reversal', 'admin_adjustment')),
  rating_before INTEGER NOT NULL,
  rating_change INTEGER NOT NULL,
  rating_after INTEGER NOT NULL,
  revision INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  superseded_by UUID REFERENCES public.rating_events(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT rating_math CHECK (rating_after = rating_before + rating_change)
);
CREATE UNIQUE INDEX IF NOT EXISTS unique_rating_event_revision
  ON public.rating_events(match_id, player_id, revision, event_kind) WHERE match_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_rating_events_player_created ON public.rating_events(player_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.weekly_player_stats (
  player_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  week_start DATE NOT NULL,
  wins INTEGER NOT NULL DEFAULT 0 CHECK (wins >= 0),
  losses INTEGER NOT NULL DEFAULT 0 CHECK (losses >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (player_id, week_start)
);
INSERT INTO public.weekly_player_stats(player_id, week_start, wins, losses)
SELECT id, (date_trunc('week', NOW() AT TIME ZONE 'America/New_York'))::date,
       weekly_wins, weekly_losses
FROM public.profiles
ON CONFLICT (player_id, week_start) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.player_season_stats (
  season_id UUID NOT NULL REFERENCES public.seasons(id) ON DELETE CASCADE,
  player_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  starting_elo INTEGER NOT NULL,
  ending_elo INTEGER,
  high_elo INTEGER NOT NULL,
  wins INTEGER NOT NULL DEFAULT 0,
  losses INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (season_id, player_id)
);

CREATE TABLE IF NOT EXISTS public.match_submissions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  match_id UUID NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  submitted_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  winner_id UUID NOT NULL REFERENCES public.profiles(id),
  player_one_score INTEGER NOT NULL,
  player_two_score INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(match_id, submitted_by)
);

CREATE TABLE IF NOT EXISTS public.disputes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  match_id UUID NOT NULL REFERENCES public.matches(id) ON DELETE RESTRICT,
  opened_by UUID NOT NULL REFERENCES public.profiles(id),
  reason TEXT NOT NULL CHECK (reason IN ('wrong_score', 'wrong_winner', 'dual_conflict', 'other')),
  original_winner_id UUID NOT NULL REFERENCES public.profiles(id),
  original_player_one_score INTEGER NOT NULL,
  original_player_two_score INTEGER NOT NULL,
  proposed_winner_id UUID NOT NULL REFERENCES public.profiles(id),
  proposed_player_one_score INTEGER NOT NULL,
  proposed_player_two_score INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'admin_review', 'resolved', 'voided')),
  resolved_by UUID REFERENCES public.profiles(id),
  resolution TEXT CHECK (resolution IN ('original', 'proposed', 'custom', 'no_violation', 'voided')),
  violation_user_id UUID REFERENCES public.profiles(id),
  admin_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS one_open_dispute_per_match ON public.disputes(match_id)
  WHERE status IN ('proposed', 'admin_review');

CREATE TABLE IF NOT EXISTS public.match_revisions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  match_id UUID NOT NULL REFERENCES public.matches(id) ON DELETE RESTRICT,
  revision INTEGER NOT NULL,
  previous_winner_id UUID REFERENCES public.profiles(id),
  previous_player_one_score INTEGER,
  previous_player_two_score INTEGER,
  corrected_winner_id UUID REFERENCES public.profiles(id),
  corrected_player_one_score INTEGER,
  corrected_player_two_score INTEGER,
  corrected_by UUID NOT NULL REFERENCES public.profiles(id),
  reason TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(match_id, revision)
);

CREATE TABLE IF NOT EXISTS public.domain_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_type TEXT NOT NULL,
  actor_id UUID REFERENCES public.profiles(id),
  match_id UUID REFERENCES public.matches(id) ON DELETE SET NULL,
  challenge_id UUID REFERENCES public.challenges(id) ON DELETE SET NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES public.domain_events(id) ON DELETE CASCADE,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, event_id)
);
CREATE TABLE IF NOT EXISTS public.integrity_flags (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  match_id UUID REFERENCES public.matches(id) ON DELETE SET NULL,
  flag_type TEXT NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  reviewed_by UUID REFERENCES public.profiles(id),
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Preserve legacy rating history where possible, then anchor every profile to
-- its current visible rating with an audited adjustment.
INSERT INTO public.rating_events(match_id, player_id, event_kind, rating_before, rating_change, rating_after, created_at)
SELECT id, player_one_id, 'legacy_match', player_one_elo_before, player_one_elo_change,
       player_one_elo_before + player_one_elo_change, COALESCE(confirmed_at, created_at)
FROM public.matches
WHERE status = 'confirmed' AND player_one_elo_before IS NOT NULL AND player_one_elo_change IS NOT NULL
ON CONFLICT DO NOTHING;
INSERT INTO public.rating_events(match_id, player_id, event_kind, rating_before, rating_change, rating_after, created_at)
SELECT id, player_two_id, 'legacy_match', player_two_elo_before, player_two_elo_change,
       player_two_elo_before + player_two_elo_change, COALESCE(confirmed_at, created_at)
FROM public.matches
WHERE status = 'confirmed' AND player_two_elo_before IS NOT NULL AND player_two_elo_change IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.rating_events(player_id, event_kind, rating_before, rating_change, rating_after, created_at)
SELECT p.id, 'migration_adjustment', COALESCE(last_event.rating_after, cfg.starting_elo),
       p.current_elo - COALESCE(last_event.rating_after, cfg.starting_elo), p.current_elo, cfg.ledger_started_at
FROM public.profiles p CROSS JOIN public.ranking_config cfg
LEFT JOIN LATERAL (
  SELECT re.rating_after FROM public.rating_events re
  WHERE re.player_id = p.id ORDER BY re.created_at DESC, re.id DESC LIMIT 1
) last_event ON TRUE
WHERE NOT EXISTS (
  SELECT 1 FROM public.rating_events re
  WHERE re.player_id = p.id AND re.event_kind = 'migration_adjustment' AND re.match_id IS NULL
);

INSERT INTO public.user_roles(user_id, role)
SELECT id, 'admin' FROM public.profiles
WHERE id = '494357c8-607e-4605-980b-19260c8a2cfc'::UUID
  AND display_name = 'almasurantor'
ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role;

CREATE OR REPLACE FUNCTION public.is_admin(p_user UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = p_user AND role = 'admin');
$$;

CREATE OR REPLACE FUNCTION public.is_valid_match_score_v2(p_one INTEGER, p_two INTEGER)
RETURNS BOOLEAN LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT COALESCE(
    p_one >= 0 AND p_two >= 0 AND p_one <= (SELECT max_score FROM public.ranking_config WHERE id)
    AND p_two <= (SELECT max_score FROM public.ranking_config WHERE id)
    AND p_one <> p_two AND GREATEST(p_one,p_two) >= 11
    AND ABS(p_one-p_two) >= 2
    AND NOT (GREATEST(p_one,p_two) > 11 AND (LEAST(p_one,p_two) < 10 OR ABS(p_one-p_two) <> 2)), FALSE);
$$;

CREATE OR REPLACE FUNCTION public.assert_ranked_access(p_user UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF COALESCE((SELECT verification_level = 'ranked_restricted' FROM public.player_integrity WHERE player_id=p_user), FALSE) THEN
    RAISE EXCEPTION 'Ranked Play Restricted';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.emit_domain_event(
  p_type TEXT, p_actor UUID, p_match UUID, p_challenge UUID, p_payload JSONB, p_recipients UUID[]
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_event UUID; v_user UUID;
BEGIN
  INSERT INTO public.domain_events(event_type,actor_id,match_id,challenge_id,payload)
  VALUES(p_type,p_actor,p_match,p_challenge,COALESCE(p_payload,'{}'::jsonb)) RETURNING id INTO v_event;
  FOREACH v_user IN ARRAY COALESCE(p_recipients, ARRAY[]::UUID[]) LOOP
    INSERT INTO public.notifications(user_id,event_id) VALUES(v_user,v_event) ON CONFLICT DO NOTHING;
  END LOOP;
  RETURN v_event;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_daily_match_limit(p_player_one_id UUID, p_player_two_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COUNT(*) < (SELECT daily_ranked_pair_limit FROM public.ranking_config WHERE id)
  FROM public.matches
  WHERE ranked AND status='confirmed'
    AND (confirmed_at AT TIME ZONE 'America/New_York')::date = (NOW() AT TIME ZONE 'America/New_York')::date
    AND ((player_one_id=p_player_one_id AND player_two_id=p_player_two_id)
      OR (player_one_id=p_player_two_id AND player_two_id=p_player_one_id));
$$;

CREATE OR REPLACE FUNCTION public.finalize_match_v2(p_match_id UUID, p_actor UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  m public.matches; winner public.profiles; loser public.profiles; cfg public.ranking_config;
  expected NUMERIC; delta INTEGER; p1_delta INTEGER; p2_delta INTEGER; week DATE; v_event UUID;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id=p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF m.status='confirmed' THEN
    RETURN jsonb_build_object('match_id',m.id,'already_finalized',TRUE,
      'player_one_change',m.player_one_elo_change,'player_two_change',m.player_two_elo_change);
  END IF;
  IF m.status NOT IN ('result_reported','correction_proposed','admin_review','awaiting_independent_report') THEN
    RAISE EXCEPTION 'Match is not eligible for finalization';
  END IF;
  IF m.winner_id NOT IN (m.player_one_id,m.player_two_id) OR NOT public.is_valid_match_score_v2(m.player_one_score,m.player_two_score) THEN
    RAISE EXCEPTION 'Invalid final result';
  END IF;
  -- Serialize finalizations for this unordered pair/day so concurrent pending
  -- matches cannot race past the configured limit.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    LEAST(m.player_one_id::TEXT,m.player_two_id::TEXT)||':'||
    GREATEST(m.player_one_id::TEXT,m.player_two_id::TEXT)||':'||
    (NOW() AT TIME ZONE 'America/New_York')::DATE::TEXT, 0));
  IF m.ranked AND NOT public.check_daily_match_limit(m.player_one_id,m.player_two_id) THEN
    RAISE EXCEPTION 'Daily ranked match limit reached';
  END IF;
  PERFORM id FROM public.profiles WHERE id IN (m.player_one_id,m.player_two_id) ORDER BY id FOR UPDATE;
  SELECT * INTO cfg FROM public.ranking_config WHERE id;
  SELECT * INTO winner FROM public.profiles WHERE id=m.winner_id;
  SELECT * INTO loser FROM public.profiles WHERE id=CASE WHEN m.winner_id=m.player_one_id THEN m.player_two_id ELSE m.player_one_id END;
  expected := 1.0/(1.0+POWER(10.0,(loser.current_elo-winner.current_elo)/400.0));
  delta := ROUND(cfg.k_factor*(1.0-expected));
  p1_delta := CASE WHEN m.player_one_id=winner.id THEN delta ELSE -delta END;
  p2_delta := -p1_delta;
  week := (date_trunc('week', NOW() AT TIME ZONE 'America/New_York'))::date;

  UPDATE public.profiles SET current_elo=current_elo+p1_delta,
    highest_elo=GREATEST(highest_elo,current_elo+p1_delta),
    total_wins=total_wins+CASE WHEN id=winner.id THEN 1 ELSE 0 END,
    total_losses=total_losses+CASE WHEN id=loser.id THEN 1 ELSE 0 END,
    weekly_wins=weekly_wins+CASE WHEN id=winner.id THEN 1 ELSE 0 END,
    weekly_losses=weekly_losses+CASE WHEN id=loser.id THEN 1 ELSE 0 END,
    current_streak=CASE WHEN id=winner.id THEN GREATEST(current_streak,0)+1 ELSE LEAST(current_streak,0)-1 END,
    longest_streak=CASE WHEN id=winner.id THEN GREATEST(longest_streak,GREATEST(current_streak,0)+1) ELSE longest_streak END,
    updated_at=NOW() WHERE id=m.player_one_id;
  UPDATE public.profiles SET current_elo=current_elo+p2_delta,
    highest_elo=GREATEST(highest_elo,current_elo+p2_delta),
    total_wins=total_wins+CASE WHEN id=winner.id THEN 1 ELSE 0 END,
    total_losses=total_losses+CASE WHEN id=loser.id THEN 1 ELSE 0 END,
    weekly_wins=weekly_wins+CASE WHEN id=winner.id THEN 1 ELSE 0 END,
    weekly_losses=weekly_losses+CASE WHEN id=loser.id THEN 1 ELSE 0 END,
    current_streak=CASE WHEN id=winner.id THEN GREATEST(current_streak,0)+1 ELSE LEAST(current_streak,0)-1 END,
    longest_streak=CASE WHEN id=winner.id THEN GREATEST(longest_streak,GREATEST(current_streak,0)+1) ELSE longest_streak END,
    updated_at=NOW() WHERE id=m.player_two_id;

  INSERT INTO public.rating_events(match_id,player_id,event_kind,rating_before,rating_change,rating_after,revision)
  VALUES(m.id,m.player_one_id,'match_result',CASE WHEN m.player_one_id=winner.id THEN winner.current_elo ELSE loser.current_elo END,
    p1_delta,CASE WHEN m.player_one_id=winner.id THEN winner.current_elo ELSE loser.current_elo END+p1_delta,m.revision);
  INSERT INTO public.rating_events(match_id,player_id,event_kind,rating_before,rating_change,rating_after,revision)
  VALUES(m.id,m.player_two_id,'match_result',CASE WHEN m.player_two_id=winner.id THEN winner.current_elo ELSE loser.current_elo END,
    p2_delta,CASE WHEN m.player_two_id=winner.id THEN winner.current_elo ELSE loser.current_elo END+p2_delta,m.revision);

  INSERT INTO public.weekly_player_stats(player_id,week_start,wins,losses)
  VALUES(m.player_one_id,week,CASE WHEN m.player_one_id=winner.id THEN 1 ELSE 0 END,CASE WHEN m.player_one_id=loser.id THEN 1 ELSE 0 END)
  ON CONFLICT(player_id,week_start) DO UPDATE SET wins=weekly_player_stats.wins+EXCLUDED.wins,
    losses=weekly_player_stats.losses+EXCLUDED.losses,updated_at=NOW();
  INSERT INTO public.weekly_player_stats(player_id,week_start,wins,losses)
  VALUES(m.player_two_id,week,CASE WHEN m.player_two_id=winner.id THEN 1 ELSE 0 END,CASE WHEN m.player_two_id=loser.id THEN 1 ELSE 0 END)
  ON CONFLICT(player_id,week_start) DO UPDATE SET wins=weekly_player_stats.wins+EXCLUDED.wins,
    losses=weekly_player_stats.losses+EXCLUDED.losses,updated_at=NOW();

  IF m.season_id IS NOT NULL THEN
    INSERT INTO public.player_season_stats(season_id,player_id,starting_elo,high_elo,wins,losses)
    VALUES(m.season_id,m.player_one_id,CASE WHEN m.player_one_id=winner.id THEN winner.current_elo ELSE loser.current_elo END,
      CASE WHEN m.player_one_id=winner.id THEN winner.current_elo+p1_delta ELSE loser.current_elo+p1_delta END,
      CASE WHEN m.player_one_id=winner.id THEN 1 ELSE 0 END,CASE WHEN m.player_one_id=loser.id THEN 1 ELSE 0 END)
    ON CONFLICT(season_id,player_id) DO UPDATE SET high_elo=GREATEST(player_season_stats.high_elo,EXCLUDED.high_elo),
      wins=player_season_stats.wins+EXCLUDED.wins,losses=player_season_stats.losses+EXCLUDED.losses;
    INSERT INTO public.player_season_stats(season_id,player_id,starting_elo,high_elo,wins,losses)
    VALUES(m.season_id,m.player_two_id,CASE WHEN m.player_two_id=winner.id THEN winner.current_elo ELSE loser.current_elo END,
      CASE WHEN m.player_two_id=winner.id THEN winner.current_elo+p2_delta ELSE loser.current_elo+p2_delta END,
      CASE WHEN m.player_two_id=winner.id THEN 1 ELSE 0 END,CASE WHEN m.player_two_id=loser.id THEN 1 ELSE 0 END)
    ON CONFLICT(season_id,player_id) DO UPDATE SET high_elo=GREATEST(player_season_stats.high_elo,EXCLUDED.high_elo),
      wins=player_season_stats.wins+EXCLUDED.wins,losses=player_season_stats.losses+EXCLUDED.losses;
  END IF;

  UPDATE public.matches SET status='confirmed',confirmed_by=p_actor,confirmed_at=NOW(),finalized_at=NOW(),expires_at=NULL,
    player_one_elo_before=CASE WHEN m.player_one_id=winner.id THEN winner.current_elo ELSE loser.current_elo END,
    player_two_elo_before=CASE WHEN m.player_two_id=winner.id THEN winner.current_elo ELSE loser.current_elo END,
    player_one_elo_change=p1_delta,player_two_elo_change=p2_delta WHERE id=m.id;
  IF m.challenge_id IS NOT NULL THEN UPDATE public.challenges SET status='completed' WHERE id=m.challenge_id; END IF;
  v_event := public.emit_domain_event('match.confirmed',p_actor,m.id,m.challenge_id,
    jsonb_build_object('winner_id',winner.id,'player_one_change',p1_delta,'player_two_change',p2_delta),ARRAY[m.player_one_id,m.player_two_id]);
  IF (SELECT COUNT(*) FROM public.matches x WHERE x.status='confirmed' AND x.ranked
      AND x.confirmed_at > NOW()-INTERVAL '24 hours'
      AND (x.player_one_id IN(m.player_one_id,m.player_two_id) OR x.player_two_id IN(m.player_one_id,m.player_two_id))) >= 15 THEN
    INSERT INTO public.integrity_flags(player_id,match_id,flag_type,details)
    VALUES(p_actor,m.id,'high_match_volume',jsonb_build_object('window_hours',24));
  END IF;
  RETURN jsonb_build_object('match_id',m.id,'already_finalized',FALSE,'player_one_change',p1_delta,
    'player_two_change',p2_delta,'player_one_new',CASE WHEN m.player_one_id=winner.id THEN winner.current_elo ELSE loser.current_elo END+p1_delta,
    'player_two_new',CASE WHEN m.player_two_id=winner.id THEN winner.current_elo ELSE loser.current_elo END+p2_delta);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_challenge_v2(p_opponent UUID)
RETURNS public.challenges LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE c public.challenges; cfg public.ranking_config;
BEGIN
  IF auth.uid() IS NULL OR p_opponent=auth.uid() THEN RAISE EXCEPTION 'Invalid opponent'; END IF;
  PERFORM public.assert_ranked_access(auth.uid()); PERFORM public.assert_ranked_access(p_opponent);
  IF NOT public.check_daily_match_limit(auth.uid(),p_opponent) THEN RAISE EXCEPTION 'Daily ranked match limit reached'; END IF;
  SELECT * INTO cfg FROM public.ranking_config WHERE id;
  INSERT INTO public.challenges(challenger_id,opponent_id,status,expires_at)
  VALUES(auth.uid(),p_opponent,'pending',NOW()+make_interval(hours=>cfg.challenge_expiry_hours)) RETURNING * INTO c;
  PERFORM public.emit_domain_event('challenge.received',auth.uid(),NULL,c.id,'{}',ARRAY[p_opponent]);
  RETURN c;
END; $$;

CREATE OR REPLACE FUNCTION public.cancel_challenge_v2(p_challenge UUID)
RETURNS public.challenges LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE c public.challenges;
BEGIN
  SELECT * INTO c FROM public.challenges WHERE id=p_challenge FOR UPDATE;
  IF NOT FOUND OR c.challenger_id<>auth.uid() OR c.status<>'pending' THEN
    RAISE EXCEPTION 'Challenge cannot be cancelled';
  END IF;
  UPDATE public.challenges SET status='declined' WHERE id=c.id RETURNING * INTO c;
  PERFORM public.emit_domain_event('challenge.cancelled',auth.uid(),NULL,c.id,'{}',ARRAY[c.opponent_id]);
  RETURN c;
END; $$;

CREATE OR REPLACE FUNCTION public.respond_challenge_v2(p_challenge UUID,p_action TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE c public.challenges; m public.matches; mode TEXT;
BEGIN
  SELECT * INTO c FROM public.challenges WHERE id=p_challenge FOR UPDATE;
  IF NOT FOUND OR c.opponent_id<>auth.uid() OR c.status<>'pending' OR c.expires_at<NOW() THEN RAISE EXCEPTION 'Challenge is not actionable'; END IF;
  IF p_action='decline' THEN
    UPDATE public.challenges SET status='declined' WHERE id=c.id;
    PERFORM public.emit_domain_event('challenge.declined',auth.uid(),NULL,c.id,'{}',ARRAY[c.challenger_id]);
    RETURN jsonb_build_object('challenge_id',c.id,'status','declined');
  ELSIF p_action<>'accept' THEN RAISE EXCEPTION 'Invalid challenge action'; END IF;
  PERFORM public.assert_ranked_access(c.challenger_id); PERFORM public.assert_ranked_access(c.opponent_id);
  IF NOT public.check_daily_match_limit(c.challenger_id,c.opponent_id) THEN RAISE EXCEPTION 'Daily ranked match limit reached'; END IF;
  SELECT CASE WHEN EXISTS(SELECT 1 FROM public.player_integrity WHERE player_id IN(c.challenger_id,c.opponent_id) AND verification_level='dual_verification') THEN 'dual' ELSE 'normal' END INTO mode;
  INSERT INTO public.matches(challenge_id,player_one_id,player_two_id,status,source,verification_mode,season_id)
  VALUES(c.id,c.challenger_id,c.opponent_id,'ready','challenge',mode,(SELECT id FROM public.seasons WHERE is_active LIMIT 1)) RETURNING * INTO m;
  UPDATE public.challenges SET status='accepted' WHERE id=c.id;
  PERFORM public.emit_domain_event('challenge.accepted',auth.uid(),m.id,c.id,'{}',ARRAY[c.challenger_id,c.opponent_id]);
  RETURN jsonb_build_object('challenge_id',c.id,'status','accepted','match_id',m.id);
END; $$;

CREATE OR REPLACE FUNCTION public.submit_match_report_v2(
  p_match UUID,p_winner UUID,p_winner_score INTEGER,p_loser_score INTEGER
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE m public.matches; p1s INTEGER; p2s INTEGER; first public.match_submissions; cfg public.ranking_config; result JSONB;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id=p_match FOR UPDATE;
  IF NOT FOUND OR auth.uid() NOT IN(m.player_one_id,m.player_two_id) THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF m.status NOT IN('ready','active','awaiting_independent_report') THEN RAISE EXCEPTION 'Match cannot accept a report'; END IF;
  IF p_winner NOT IN(m.player_one_id,m.player_two_id) THEN RAISE EXCEPTION 'Winner must be a participant'; END IF;
  p1s:=CASE WHEN p_winner=m.player_one_id THEN p_winner_score ELSE p_loser_score END;
  p2s:=CASE WHEN p_winner=m.player_two_id THEN p_winner_score ELSE p_loser_score END;
  IF NOT public.is_valid_match_score_v2(p1s,p2s) THEN RAISE EXCEPTION 'Invalid table tennis score'; END IF;
  PERFORM public.assert_ranked_access(m.player_one_id); PERFORM public.assert_ranked_access(m.player_two_id);
  SELECT * INTO cfg FROM public.ranking_config WHERE id;
  IF m.verification_mode='dual' THEN
    INSERT INTO public.match_submissions(match_id,submitted_by,winner_id,player_one_score,player_two_score)
    VALUES(m.id,auth.uid(),p_winner,p1s,p2s) ON CONFLICT(match_id,submitted_by) DO NOTHING;
    SELECT * INTO first FROM public.match_submissions WHERE match_id=m.id AND submitted_by<>auth.uid() ORDER BY created_at LIMIT 1;
    IF NOT FOUND THEN
      UPDATE public.matches SET status='awaiting_independent_report',expires_at=NOW()+make_interval(hours=>cfg.result_expiry_hours) WHERE id=m.id;
      RETURN jsonb_build_object('match_id',m.id,'status','awaiting_independent_report');
    END IF;
    IF first.winner_id=p_winner AND first.player_one_score=p1s AND first.player_two_score=p2s THEN
      UPDATE public.matches SET winner_id=p_winner,player_one_score=p1s,player_two_score=p2s,reported_by=first.submitted_by,
        reported_at=first.created_at,confirmed_by=auth.uid(),status='result_reported' WHERE id=m.id;
      RETURN public.finalize_match_v2(m.id,auth.uid());
    END IF;
    INSERT INTO public.disputes(match_id,opened_by,reason,original_winner_id,original_player_one_score,original_player_two_score,
      proposed_winner_id,proposed_player_one_score,proposed_player_two_score,status)
    VALUES(m.id,auth.uid(),'dual_conflict',first.winner_id,first.player_one_score,first.player_two_score,
      p_winner,p1s,p2s,'admin_review');
    UPDATE public.matches SET status='admin_review',disputed_by=auth.uid(),disputed_at=NOW() WHERE id=m.id;
    RETURN jsonb_build_object('match_id',m.id,'status','admin_review');
  END IF;
  UPDATE public.matches SET winner_id=p_winner,player_one_score=p1s,player_two_score=p2s,reported_by=auth.uid(),reported_at=NOW(),
    status='result_reported',expires_at=NOW()+make_interval(hours=>cfg.result_expiry_hours) WHERE id=m.id;
  PERFORM public.emit_domain_event('match.result_reported',auth.uid(),m.id,m.challenge_id,
    jsonb_build_object('winner_id',p_winner,'player_one_score',p1s,'player_two_score',p2s),
    ARRAY[CASE WHEN auth.uid()=m.player_one_id THEN m.player_two_id ELSE m.player_one_id END]);
  RETURN jsonb_build_object('match_id',m.id,'status','result_reported');
END; $$;

CREATE OR REPLACE FUNCTION public.create_spontaneous_match_v2(
  p_opponent UUID,p_winner UUID,p_winner_score INTEGER,p_loser_score INTEGER,p_request UUID,p_allow_duplicate BOOLEAN DEFAULT FALSE
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE existing public.matches; m public.matches; mode TEXT; result JSONB; p1s INTEGER; p2s INTEGER;
BEGIN
  IF auth.uid() IS NULL OR p_opponent=auth.uid() THEN RAISE EXCEPTION 'Invalid opponent'; END IF;
  IF p_winner NOT IN(auth.uid(),p_opponent) THEN RAISE EXCEPTION 'Winner must be a participant'; END IF;
  IF NOT public.check_daily_match_limit(auth.uid(),p_opponent) THEN RAISE EXCEPTION 'Daily ranked match limit reached'; END IF;
  PERFORM public.assert_ranked_access(auth.uid()); PERFORM public.assert_ranked_access(p_opponent);
  SELECT * INTO existing FROM public.matches WHERE request_id=p_request;
  IF FOUND THEN RETURN jsonb_build_object('match_id',existing.id,'status',existing.status,'idempotent',TRUE); END IF;
  p1s:=CASE WHEN p_winner=auth.uid() THEN p_winner_score ELSE p_loser_score END;
  p2s:=CASE WHEN p_winner=p_opponent THEN p_winner_score ELSE p_loser_score END;
  IF NOT public.is_valid_match_score_v2(p1s,p2s) THEN RAISE EXCEPTION 'Invalid table tennis score'; END IF;
  SELECT * INTO existing FROM public.matches WHERE created_at>NOW()-INTERVAL '5 minutes' AND status<>'voided'
    AND winner_id=p_winner AND GREATEST(player_one_score,player_two_score)=p_winner_score
    AND LEAST(player_one_score,player_two_score)=p_loser_score
    AND ((player_one_id=auth.uid() AND player_two_id=p_opponent) OR (player_one_id=p_opponent AND player_two_id=auth.uid()))
    ORDER BY created_at DESC LIMIT 1;
  IF FOUND AND NOT p_allow_duplicate THEN
    INSERT INTO public.integrity_flags(player_id,match_id,flag_type,details)
    VALUES(auth.uid(),existing.id,'duplicate_attempt',jsonb_build_object('request_id',p_request));
    RETURN jsonb_build_object('potential_duplicate',TRUE,'existing_match_id',existing.id);
  END IF;
  SELECT CASE WHEN EXISTS(SELECT 1 FROM public.player_integrity WHERE player_id IN(auth.uid(),p_opponent) AND verification_level='dual_verification') THEN 'dual' ELSE 'normal' END INTO mode;
  INSERT INTO public.matches(player_one_id,player_two_id,status,source,verification_mode,request_id,season_id)
  VALUES(auth.uid(),p_opponent,'ready','spontaneous',mode,p_request,(SELECT id FROM public.seasons WHERE is_active LIMIT 1)) RETURNING * INTO m;
  SELECT public.submit_match_report_v2(m.id,p_winner,p_winner_score,p_loser_score) INTO result;
  RETURN result || jsonb_build_object('match_id',m.id);
END; $$;

CREATE OR REPLACE FUNCTION public.confirm_match_result_v2(p_match UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE m public.matches;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id=p_match FOR UPDATE;
  IF NOT FOUND OR auth.uid() NOT IN(m.player_one_id,m.player_two_id) THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF m.status='confirmed' THEN RETURN public.finalize_match_v2(m.id,auth.uid()); END IF;
  IF m.status<>'result_reported' OR m.reported_by=auth.uid() THEN RAISE EXCEPTION 'Only the reporter''s opponent can confirm'; END IF;
  RETURN public.finalize_match_v2(m.id,auth.uid());
END; $$;

CREATE OR REPLACE FUNCTION public.propose_match_correction_v2(
  p_match UUID,p_reason TEXT,p_winner UUID,p_winner_score INTEGER,p_loser_score INTEGER
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE m public.matches; d public.disputes; p1s INTEGER; p2s INTEGER;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id=p_match FOR UPDATE;
  IF NOT FOUND OR m.status<>'result_reported' OR auth.uid() NOT IN(m.player_one_id,m.player_two_id) OR auth.uid()=m.reported_by THEN
    RAISE EXCEPTION 'Result cannot be disputed by this user'; END IF;
  IF p_reason NOT IN('wrong_score','wrong_winner') OR p_winner NOT IN(m.player_one_id,m.player_two_id) THEN RAISE EXCEPTION 'Invalid correction'; END IF;
  p1s:=CASE WHEN p_winner=m.player_one_id THEN p_winner_score ELSE p_loser_score END;
  p2s:=CASE WHEN p_winner=m.player_two_id THEN p_winner_score ELSE p_loser_score END;
  IF NOT public.is_valid_match_score_v2(p1s,p2s) THEN RAISE EXCEPTION 'Invalid table tennis score'; END IF;
  INSERT INTO public.disputes(match_id,opened_by,reason,original_winner_id,original_player_one_score,original_player_two_score,
    proposed_winner_id,proposed_player_one_score,proposed_player_two_score)
  VALUES(m.id,auth.uid(),p_reason,m.winner_id,m.player_one_score,m.player_two_score,p_winner,p1s,p2s) RETURNING * INTO d;
  IF p_reason='wrong_winner' THEN
    INSERT INTO public.integrity_flags(player_id,match_id,flag_type,details)
    VALUES(m.reported_by,m.id,'winner_dispute',jsonb_build_object('dispute_id',d.id));
  END IF;
  UPDATE public.matches SET status='correction_proposed',disputed_by=auth.uid(),disputed_at=NOW(),dispute_reason=p_reason WHERE id=m.id;
  PERFORM public.emit_domain_event('match.correction_proposed',auth.uid(),m.id,m.challenge_id,jsonb_build_object('dispute_id',d.id),ARRAY[m.reported_by]);
  RETURN jsonb_build_object('match_id',m.id,'dispute_id',d.id,'status','correction_proposed');
END; $$;

CREATE OR REPLACE FUNCTION public.respond_match_correction_v2(p_dispute UUID,p_accept BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE d public.disputes; m public.matches;
BEGIN
  SELECT * INTO d FROM public.disputes WHERE id=p_dispute FOR UPDATE;
  IF NOT FOUND OR d.status<>'proposed' THEN RAISE EXCEPTION 'Correction is not actionable'; END IF;
  SELECT * INTO m FROM public.matches WHERE id=d.match_id FOR UPDATE;
  IF m.reported_by<>auth.uid() OR m.status<>'correction_proposed' THEN RAISE EXCEPTION 'Only the original reporter can respond'; END IF;
  IF p_accept THEN
    UPDATE public.matches SET winner_id=d.proposed_winner_id,player_one_score=d.proposed_player_one_score,
      player_two_score=d.proposed_player_two_score,status='correction_proposed' WHERE id=m.id;
    UPDATE public.disputes SET status='resolved',resolved_by=auth.uid(),resolution='proposed',resolved_at=NOW() WHERE id=d.id;
    RETURN public.finalize_match_v2(m.id,auth.uid());
  END IF;
  UPDATE public.matches SET status='admin_review' WHERE id=m.id;
  UPDATE public.disputes SET status='admin_review' WHERE id=d.id;
  PERFORM public.emit_domain_event('match.admin_review',auth.uid(),m.id,m.challenge_id,jsonb_build_object('dispute_id',d.id),
    ARRAY(SELECT user_id FROM public.user_roles WHERE role='admin'));
  RETURN jsonb_build_object('match_id',m.id,'dispute_id',d.id,'status','admin_review');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute_v2(
  p_dispute UUID,p_resolution TEXT,p_winner UUID DEFAULT NULL,p_winner_score INTEGER DEFAULT NULL,
  p_loser_score INTEGER DEFAULT NULL,p_violation_user UUID DEFAULT NULL,p_notes TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE d public.disputes; m public.matches; win UUID; p1s INTEGER; p2s INTEGER; result JSONB;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;
  SELECT * INTO d FROM public.disputes WHERE id=p_dispute FOR UPDATE;
  IF NOT FOUND OR d.status NOT IN('proposed','admin_review') THEN RAISE EXCEPTION 'Dispute is not open'; END IF;
  SELECT * INTO m FROM public.matches WHERE id=d.match_id FOR UPDATE;
  IF p_resolution='voided' THEN
    UPDATE public.matches SET status='voided',finalized_at=NOW() WHERE id=m.id;
    UPDATE public.disputes SET status='voided',resolved_by=auth.uid(),resolution='voided',admin_notes=p_notes,resolved_at=NOW() WHERE id=d.id;
    RETURN jsonb_build_object('match_id',m.id,'status','voided');
  ELSIF p_resolution='original' OR p_resolution='no_violation' THEN
    win:=d.original_winner_id;p1s:=d.original_player_one_score;p2s:=d.original_player_two_score;
  ELSIF p_resolution='proposed' THEN
    win:=d.proposed_winner_id;p1s:=d.proposed_player_one_score;p2s:=d.proposed_player_two_score;
  ELSIF p_resolution='custom' THEN
    win:=p_winner;p1s:=CASE WHEN win=m.player_one_id THEN p_winner_score ELSE p_loser_score END;
    p2s:=CASE WHEN win=m.player_two_id THEN p_winner_score ELSE p_loser_score END;
  ELSE RAISE EXCEPTION 'Invalid resolution'; END IF;
  IF win NOT IN(m.player_one_id,m.player_two_id) OR NOT public.is_valid_match_score_v2(p1s,p2s) THEN RAISE EXCEPTION 'Invalid resolved score'; END IF;
  UPDATE public.matches SET winner_id=win,player_one_score=p1s,player_two_score=p2s,status='admin_review' WHERE id=m.id;
  UPDATE public.disputes SET status='resolved',resolved_by=auth.uid(),resolution=p_resolution,violation_user_id=p_violation_user,
    admin_notes=p_notes,resolved_at=NOW() WHERE id=d.id;
  IF p_violation_user IS NOT NULL THEN
    UPDATE public.player_integrity SET confirmed_violations=confirmed_violations+1,updated_by=auth.uid(),updated_at=NOW()
    WHERE player_id=p_violation_user;
    INSERT INTO public.integrity_flags(player_id,match_id,flag_type,details,reviewed_by,reviewed_at)
    VALUES(p_violation_user,m.id,'confirmed_violation',jsonb_build_object('dispute_id',d.id),auth.uid(),NOW());
  END IF;
  SELECT public.finalize_match_v2(m.id,auth.uid()) INTO result;
  RETURN result;
END; $$;

CREATE OR REPLACE FUNCTION public.expire_mobile_ranking_items_v2()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE challenge_count INTEGER; match_count INTEGER;
BEGIN
  UPDATE public.challenges SET status='expired' WHERE status='pending' AND expires_at<NOW();
  GET DIAGNOSTICS challenge_count = ROW_COUNT;
  UPDATE public.matches SET status='expired',finalized_at=NOW()
  WHERE status IN('ready','result_reported','awaiting_independent_report','correction_proposed')
    AND expires_at IS NOT NULL AND expires_at<NOW();
  GET DIAGNOSTICS match_count = ROW_COUNT;
  RETURN jsonb_build_object('expired_challenges',challenge_count,'expired_matches',match_count);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_player_integrity_v2(p_player UUID,p_level TEXT,p_reason TEXT DEFAULT NULL)
RETURNS public.player_integrity LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.player_integrity;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;
  IF p_level NOT IN('normal','monitored','dual_verification','ranked_restricted') THEN RAISE EXCEPTION 'Invalid level'; END IF;
  INSERT INTO public.player_integrity(player_id,verification_level,restriction_reason,updated_by,updated_at)
  VALUES(p_player,p_level,p_reason,auth.uid(),NOW()) ON CONFLICT(player_id) DO UPDATE SET verification_level=EXCLUDED.verification_level,
    restriction_reason=EXCLUDED.restriction_reason,updated_by=EXCLUDED.updated_by,updated_at=NOW() RETURNING * INTO result;
  PERFORM public.emit_domain_event('player.integrity_changed',auth.uid(),NULL,NULL,jsonb_build_object('level',p_level),ARRAY[p_player]);
  RETURN result;
END; $$;

-- Security: reads are scoped, writes go through the functions above.
ALTER TABLE public.ranking_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_integrity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_stat_baselines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rating_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekly_player_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_season_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.domain_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrity_flags ENABLE ROW LEVEL SECURITY;

-- Keep the legacy column order so existing profile/history queries continue to
-- work while switching the view to the caller's RLS context.
CREATE OR REPLACE VIEW public.match_history WITH (security_invoker=TRUE) AS
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
  m.winner_id,
  m.source,
  m.ranked,
  m.revision
FROM public.matches m
WHERE m.status='confirmed';

DROP POLICY IF EXISTS "Authenticated can read ranking config" ON public.ranking_config;
CREATE POLICY "Authenticated can read ranking config" ON public.ranking_config FOR SELECT TO authenticated USING(TRUE);
DROP POLICY IF EXISTS "Users read own role" ON public.user_roles;
CREATE POLICY "Users read own role" ON public.user_roles FOR SELECT TO authenticated USING(user_id=auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Users read own integrity" ON public.player_integrity;
CREATE POLICY "Users read own integrity" ON public.player_integrity FOR SELECT TO authenticated USING(player_id=auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Rating history is readable" ON public.rating_events;
CREATE POLICY "Rating history is readable" ON public.rating_events FOR SELECT TO authenticated USING(TRUE);
DROP POLICY IF EXISTS "Weekly stats are readable" ON public.weekly_player_stats;
CREATE POLICY "Weekly stats are readable" ON public.weekly_player_stats FOR SELECT TO authenticated USING(TRUE);
DROP POLICY IF EXISTS "Seasons are readable" ON public.seasons;
CREATE POLICY "Seasons are readable" ON public.seasons FOR SELECT TO authenticated USING(TRUE);
DROP POLICY IF EXISTS "Season stats are readable" ON public.player_season_stats;
CREATE POLICY "Season stats are readable" ON public.player_season_stats FOR SELECT TO authenticated USING(TRUE);
DROP POLICY IF EXISTS "Users read own submissions" ON public.match_submissions;
CREATE POLICY "Users read own submissions" ON public.match_submissions FOR SELECT TO authenticated
  USING(submitted_by=auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS "Participants and admins read disputes" ON public.disputes;
CREATE POLICY "Participants and admins read disputes" ON public.disputes FOR SELECT TO authenticated
  USING(public.is_admin() OR EXISTS(SELECT 1 FROM public.matches m WHERE m.id=match_id AND auth.uid() IN(m.player_one_id,m.player_two_id)));
DROP POLICY IF EXISTS "Admins read revisions" ON public.match_revisions;
CREATE POLICY "Admins read revisions" ON public.match_revisions FOR SELECT TO authenticated USING(public.is_admin());
DROP POLICY IF EXISTS "Users read relevant events" ON public.domain_events;
CREATE POLICY "Users read relevant events" ON public.domain_events FOR SELECT TO authenticated
  USING(actor_id=auth.uid() OR EXISTS(SELECT 1 FROM public.notifications n WHERE n.event_id=id AND n.user_id=auth.uid()) OR public.is_admin());
DROP POLICY IF EXISTS "Users read notifications" ON public.notifications;
CREATE POLICY "Users read notifications" ON public.notifications FOR SELECT TO authenticated USING(user_id=auth.uid());
DROP POLICY IF EXISTS "Admins read integrity flags" ON public.integrity_flags;
CREATE POLICY "Admins read integrity flags" ON public.integrity_flags FOR SELECT TO authenticated USING(public.is_admin());

-- Existing match/challenge policies intentionally remain during expand. The
-- contract migration removes them after the compatible app is deployed.
REVOKE INSERT,UPDATE,DELETE ON public.rating_events,public.disputes,public.match_submissions,public.player_integrity,
  public.user_roles,public.integrity_flags,public.domain_events,public.notifications FROM authenticated;

REVOKE EXECUTE ON FUNCTION public.finalize_match_v2(UUID,UUID) FROM PUBLIC,authenticated,anon;
REVOKE EXECUTE ON FUNCTION public.assert_ranked_access(UUID) FROM PUBLIC,authenticated,anon;
REVOKE EXECUTE ON FUNCTION public.emit_domain_event(TEXT,UUID,UUID,UUID,JSONB,UUID[]) FROM PUBLIC,authenticated,anon;
REVOKE EXECUTE ON FUNCTION public.create_challenge_v2(UUID) FROM PUBLIC,anon;
REVOKE EXECUTE ON FUNCTION public.respond_challenge_v2(UUID,TEXT) FROM PUBLIC,anon;
REVOKE EXECUTE ON FUNCTION public.cancel_challenge_v2(UUID) FROM PUBLIC,anon;
REVOKE EXECUTE ON FUNCTION public.submit_match_report_v2(UUID,UUID,INTEGER,INTEGER) FROM PUBLIC,anon;
REVOKE EXECUTE ON FUNCTION public.create_spontaneous_match_v2(UUID,UUID,INTEGER,INTEGER,UUID,BOOLEAN) FROM PUBLIC,anon;
REVOKE EXECUTE ON FUNCTION public.confirm_match_result_v2(UUID) FROM PUBLIC,anon;
REVOKE EXECUTE ON FUNCTION public.propose_match_correction_v2(UUID,TEXT,UUID,INTEGER,INTEGER) FROM PUBLIC,anon;
REVOKE EXECUTE ON FUNCTION public.respond_match_correction_v2(UUID,BOOLEAN) FROM PUBLIC,anon;
REVOKE EXECUTE ON FUNCTION public.admin_resolve_dispute_v2(UUID,TEXT,UUID,INTEGER,INTEGER,UUID,TEXT) FROM PUBLIC,anon;
REVOKE EXECUTE ON FUNCTION public.admin_set_player_integrity_v2(UUID,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE EXECUTE ON FUNCTION public.expire_mobile_ranking_items_v2() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.expire_mobile_ranking_items_v2() TO service_role;
REVOKE EXECUTE ON FUNCTION public.is_admin(UUID) FROM PUBLIC,anon;
REVOKE EXECUTE ON FUNCTION public.is_valid_match_score_v2(INTEGER,INTEGER) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.is_admin(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_valid_match_score_v2(INTEGER,INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_daily_match_limit(UUID,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_challenge_v2(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_challenge_v2(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_challenge_v2(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_match_report_v2(UUID,UUID,INTEGER,INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_spontaneous_match_v2(UUID,UUID,INTEGER,INTEGER,UUID,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_match_result_v2(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.propose_match_correction_v2(UUID,TEXT,UUID,INTEGER,INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_match_correction_v2(UUID,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute_v2(UUID,TEXT,UUID,INTEGER,INTEGER,UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_player_integrity_v2(UUID,TEXT,TEXT) TO authenticated;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.rating_events;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.weekly_player_stats;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.disputes;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMIT;
