-- Ranked ELO V5: asymmetric +70/-40 K factors, a 50-point first-game
-- baseline, a hard zero floor, and the 0/100/200/325/475/650/850 tiers.
BEGIN;

DO $dependencies$
BEGIN
  IF to_regprocedure('public.finalize_match_v2(uuid,uuid)') IS NULL
     OR to_regprocedure('public.replay_rankings_from_v3(timestamp with time zone,uuid,text,uuid)') IS NULL
     OR to_regclass('public.competitive_rank_tiers') IS NULL THEN
    RAISE EXCEPTION 'Missing ranked-match migrations';
  END IF;
END;
$dependencies$;

ALTER TABLE public.ranking_config
  ADD COLUMN IF NOT EXISTS win_k_factor INTEGER NOT NULL DEFAULT 70 CHECK(win_k_factor>0),
  ADD COLUMN IF NOT EXISTS loss_k_factor INTEGER NOT NULL DEFAULT 40 CHECK(loss_k_factor>0);

UPDATE public.ranking_config SET
  starting_elo=50,
  k_factor=70,
  win_k_factor=70,
  loss_k_factor=40,
  score_margin_cap=0,
  elo_formula_version='asymmetric_elo_v2',
  updated_at=NOW()
WHERE id;

ALTER TABLE public.profiles
  ALTER COLUMN current_elo SET DEFAULT 50,
  ALTER COLUMN highest_elo SET DEFAULT 50;

-- Accounts with no completed ranked match have no earned rating to preserve.
UPDATE public.profiles SET current_elo=50,highest_elo=50,updated_at=NOW()
WHERE total_wins+total_losses=0;

UPDATE public.profiles SET
  current_elo=GREATEST(current_elo,0),
  highest_elo=GREATEST(highest_elo,0)
WHERE current_elo<0 OR highest_elo<0;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_current_elo_nonnegative;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_current_elo_nonnegative CHECK(current_elo>=0);

INSERT INTO public.competitive_rank_tiers(rank_name,tier_order,min_elo)
VALUES
  ('Iron',1,NULL),
  ('Bronze',2,100),
  ('Silver',3,200),
  ('Gold',4,325),
  ('Platinum',5,475),
  ('Diamond',6,650),
  ('Legend',7,850)
ON CONFLICT(rank_name) DO UPDATE SET
  tier_order=EXCLUDED.tier_order,
  min_elo=EXCLUDED.min_elo,
  updated_at=NOW();

-- Keep the V3 signature because the finalizer, previews, and correction replay
-- already depend on it. Scores are validated but no longer affect rating deltas.
CREATE OR REPLACE FUNCTION public.calculate_weighted_elo_v3(
  p_winner_rating INTEGER,
  p_loser_rating INTEGER,
  p_winner_score INTEGER,
  p_loser_score INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  cfg public.ranking_config%ROWTYPE;
  winner_expected NUMERIC;
  loser_expected NUMERIC;
  winner_gain_raw NUMERIC;
  loser_loss_raw NUMERIC;
  winner_gain INTEGER;
  loser_loss_unclamped INTEGER;
  loser_loss INTEGER;
BEGIN
  IF p_winner_rating IS NULL OR p_loser_rating IS NULL
     OR p_winner_rating<0 OR p_loser_rating<0
     OR p_winner_score IS NULL OR p_loser_score IS NULL
     OR p_winner_score<=p_loser_score
     OR NOT public.is_valid_match_score_v2(p_winner_score,p_loser_score) THEN
    RAISE EXCEPTION 'Invalid asymmetric ELO input';
  END IF;

  SELECT * INTO cfg FROM public.ranking_config WHERE id;
  winner_expected:=1.0/(1.0+POWER(10.0,(p_loser_rating-p_winner_rating)/400.0));
  loser_expected:=1.0-winner_expected;
  winner_gain_raw:=cfg.win_k_factor*loser_expected;
  loser_loss_raw:=cfg.loss_k_factor*loser_expected;
  winner_gain:=ROUND(winner_gain_raw);
  loser_loss_unclamped:=ROUND(loser_loss_raw);
  loser_loss:=LEAST(p_loser_rating,loser_loss_unclamped);

  RETURN jsonb_build_object(
    'formula_version',cfg.elo_formula_version,
    'win_k_factor',cfg.win_k_factor,
    'loss_k_factor',cfg.loss_k_factor,
    'winner_expected',winner_expected,
    'loser_expected',loser_expected,
    'winner_gain_raw',winner_gain_raw,
    'loser_loss_raw',loser_loss_raw,
    'winner_gain',winner_gain,
    'loser_loss_unclamped',loser_loss_unclamped,
    'loser_loss',loser_loss,
    'floor_applied',loser_loss<loser_loss_unclamped,
    -- Compatibility for older readers; this is the winner gain, not a transfer.
    'final_delta',winner_gain
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_match_rating_preview_v3(p_match UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  match_row public.matches%ROWTYPE;
  player_one public.profiles%ROWTYPE;
  player_two public.profiles%ROWTYPE;
  player_one_rating INTEGER;
  player_two_rating INTEGER;
  player_one_win JSONB;
  player_two_win JSONB;
BEGIN
  SELECT * INTO match_row FROM public.matches WHERE id=p_match;
  IF NOT FOUND OR auth.uid() NOT IN(match_row.player_one_id,match_row.player_two_id) THEN
    RAISE EXCEPTION 'Match not found';
  END IF;
  SELECT * INTO player_one FROM public.profiles WHERE id=match_row.player_one_id;
  SELECT * INTO player_two FROM public.profiles WHERE id=match_row.player_two_id;
  player_one_rating:=CASE WHEN player_one.total_wins+player_one.total_losses=0 THEN 50 ELSE player_one.current_elo END;
  player_two_rating:=CASE WHEN player_two.total_wins+player_two.total_losses=0 THEN 50 ELSE player_two.current_elo END;
  player_one_win:=public.calculate_weighted_elo_v3(player_one_rating,player_two_rating,11,9);
  player_two_win:=public.calculate_weighted_elo_v3(player_two_rating,player_one_rating,11,9);

  RETURN jsonb_build_object(
    'player_one_rating',player_one_rating,
    'player_two_rating',player_two_rating,
    'player_one_win_change',(player_one_win->>'winner_gain')::INTEGER,
    'player_one_loss_change',-((player_two_win->>'loser_loss')::INTEGER),
    'player_two_win_change',(player_two_win->>'winner_gain')::INTEGER,
    'player_two_loss_change',-((player_one_win->>'loser_loss')::INTEGER),
    'player_one_expected',1.0/(1.0+POWER(10.0,(player_two_rating-player_one_rating)/400.0)),
    'formula_version','asymmetric_elo_v2'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_rank_progress_v3(p_elo INTEGER,p_total_games INTEGER DEFAULT 0)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  current_tier public.competitive_rank_tiers%ROWTYPE;
  next_tier public.competitive_rank_tiers%ROWTYPE;
  progress_floor INTEGER;
  progress_percent INTEGER;
  games_played INTEGER:=GREATEST(COALESCE(p_total_games,0),0);
BEGIN
  IF p_elo IS NULL THEN RAISE EXCEPTION 'ELO is required'; END IF;
  IF games_played=0 THEN
    RETURN jsonb_build_object(
      'tier','Unranked','min_elo',NULL,'next_tier',NULL,'next_tier_elo',NULL,
      'points_to_next',0,'progress_percent',0,'is_top_tier',FALSE,
      'is_provisional',FALSE,'placement_games_remaining',0
    );
  END IF;

  SELECT * INTO current_tier FROM public.competitive_rank_tiers tier
  WHERE tier.min_elo IS NULL OR p_elo>=tier.min_elo
  ORDER BY tier.tier_order DESC LIMIT 1;
  SELECT * INTO next_tier FROM public.competitive_rank_tiers tier
  WHERE tier.tier_order=current_tier.tier_order+1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'tier',current_tier.rank_name,'min_elo',current_tier.min_elo,
      'next_tier',NULL,'next_tier_elo',NULL,'points_to_next',0,
      'progress_percent',100,'is_top_tier',TRUE,
      'is_provisional',FALSE,'placement_games_remaining',0
    );
  END IF;

  progress_floor:=COALESCE(current_tier.min_elo,0);
  progress_percent:=ROUND(LEAST(1.0,GREATEST(0.0,
    (GREATEST(p_elo,0)-progress_floor)::NUMERIC/
      NULLIF(next_tier.min_elo-progress_floor,0)
  ))*100);
  RETURN jsonb_build_object(
    'tier',current_tier.rank_name,'min_elo',current_tier.min_elo,
    'next_tier',next_tier.rank_name,'next_tier_elo',next_tier.min_elo,
    'points_to_next',GREATEST(next_tier.min_elo-p_elo,0),
    'progress_percent',progress_percent,'is_top_tier',FALSE,
    'is_provisional',FALSE,'placement_games_remaining',0
  );
END;
$$;

-- Preserve the current display-name contract while changing the new-player
-- ranked baseline from 500 to 50.
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
      ) VALUES(NEW.id,candidate,50,50,0,0,0,0,0,0)
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

CREATE OR REPLACE FUNCTION public.finalize_match_v2(p_match_id UUID,p_actor UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  match_row public.matches%ROWTYPE;
  winner public.profiles%ROWTYPE;
  loser public.profiles%ROWTYPE;
  winner_before INTEGER;
  loser_before INTEGER;
  winner_gain INTEGER;
  loser_loss INTEGER;
  player_one_before INTEGER;
  player_two_before INTEGER;
  player_one_delta INTEGER;
  player_two_delta INTEGER;
  current_week_start DATE;
  domain_event UUID;
  calculation JSONB;
BEGIN
  SELECT * INTO match_row FROM public.matches WHERE id=p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF match_row.status='confirmed' THEN
    RETURN jsonb_build_object(
      'match_id',match_row.id,
      'already_finalized',TRUE,
      'player_one_change',match_row.player_one_elo_change,
      'player_two_change',match_row.player_two_elo_change,
      'player_one_new',match_row.player_one_elo_before+match_row.player_one_elo_change,
      'player_two_new',match_row.player_two_elo_before+match_row.player_two_elo_change,
      'rating_calculation',match_row.rating_calculation
    );
  END IF;
  IF match_row.status<>'result_reported' THEN
    RAISE EXCEPTION 'Match is not eligible for finalization';
  END IF;
  IF match_row.winner_id NOT IN(match_row.player_one_id,match_row.player_two_id)
     OR NOT public.is_valid_match_score_v2(match_row.player_one_score,match_row.player_two_score) THEN
    RAISE EXCEPTION 'Invalid final result';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    LEAST(match_row.player_one_id::TEXT,match_row.player_two_id::TEXT)||':'||
    GREATEST(match_row.player_one_id::TEXT,match_row.player_two_id::TEXT)||':'||
    COALESCE(match_row.ranked_day::TEXT,public.club_ranked_day_v3()::TEXT),0
  ));
  PERFORM id FROM public.profiles
  WHERE id IN(match_row.player_one_id,match_row.player_two_id)
  ORDER BY id FOR UPDATE;

  SELECT * INTO winner FROM public.profiles WHERE id=match_row.winner_id;
  SELECT * INTO loser FROM public.profiles
  WHERE id=CASE WHEN match_row.winner_id=match_row.player_one_id
    THEN match_row.player_two_id ELSE match_row.player_one_id END;

  -- Any account with no ranked result uses the configured 50-point placement
  -- baseline, including accounts created before this migration at 500.
  winner_before:=CASE WHEN winner.total_wins+winner.total_losses=0 THEN 50 ELSE winner.current_elo END;
  loser_before:=CASE WHEN loser.total_wins+loser.total_losses=0 THEN 50 ELSE loser.current_elo END;
  calculation:=public.calculate_weighted_elo_v3(
    winner_before,
    loser_before,
    GREATEST(match_row.player_one_score,match_row.player_two_score),
    LEAST(match_row.player_one_score,match_row.player_two_score)
  )||jsonb_build_object(
    'winner_id',winner.id,
    'loser_id',loser.id,
    'winner_rating_before',winner_before,
    'loser_rating_before',loser_before
  );
  winner_gain:=(calculation->>'winner_gain')::INTEGER;
  loser_loss:=(calculation->>'loser_loss')::INTEGER;

  player_one_before:=CASE WHEN match_row.player_one_id=winner.id THEN winner_before ELSE loser_before END;
  player_two_before:=CASE WHEN match_row.player_two_id=winner.id THEN winner_before ELSE loser_before END;
  player_one_delta:=CASE WHEN match_row.player_one_id=winner.id THEN winner_gain ELSE -loser_loss END;
  player_two_delta:=CASE WHEN match_row.player_two_id=winner.id THEN winner_gain ELSE -loser_loss END;
  current_week_start:=(date_trunc('week',NOW() AT TIME ZONE 'America/New_York'))::DATE;

  UPDATE public.profiles SET
    current_elo=winner_before+winner_gain,
    highest_elo=GREATEST(
      CASE WHEN total_wins+total_losses=0 THEN 50 ELSE highest_elo END,
      winner_before+winner_gain
    ),
    total_wins=total_wins+1,
    weekly_wins=weekly_wins+1,
    current_streak=GREATEST(current_streak,0)+1,
    longest_streak=GREATEST(longest_streak,GREATEST(current_streak,0)+1),
    updated_at=NOW()
  WHERE id=winner.id;

  UPDATE public.profiles SET
    current_elo=GREATEST(loser_before-loser_loss,0),
    highest_elo=CASE WHEN total_wins+total_losses=0
      THEN GREATEST(50,loser_before-loser_loss)
      ELSE highest_elo END,
    total_losses=total_losses+1,
    weekly_losses=weekly_losses+1,
    current_streak=LEAST(current_streak,0)-1,
    updated_at=NOW()
  WHERE id=loser.id;

  INSERT INTO public.rating_events(
    match_id,player_id,event_kind,rating_before,rating_change,
    rating_after,revision,calculation
  ) VALUES(
    match_row.id,match_row.player_one_id,'match_result',
    player_one_before,player_one_delta,player_one_before+player_one_delta,
    match_row.revision,calculation
  );
  INSERT INTO public.rating_events(
    match_id,player_id,event_kind,rating_before,rating_change,
    rating_after,revision,calculation
  ) VALUES(
    match_row.id,match_row.player_two_id,'match_result',
    player_two_before,player_two_delta,player_two_before+player_two_delta,
    match_row.revision,calculation
  );

  INSERT INTO public.weekly_player_stats(player_id,week_start,wins,losses)
  VALUES(winner.id,current_week_start,1,0)
  ON CONFLICT(player_id,week_start) DO UPDATE SET
    wins=public.weekly_player_stats.wins+1,
    updated_at=NOW();
  INSERT INTO public.weekly_player_stats(player_id,week_start,wins,losses)
  VALUES(loser.id,current_week_start,0,1)
  ON CONFLICT(player_id,week_start) DO UPDATE SET
    losses=public.weekly_player_stats.losses+1,
    updated_at=NOW();

  IF match_row.season_id IS NOT NULL THEN
    INSERT INTO public.player_season_stats(season_id,player_id,starting_elo,high_elo,wins,losses)
    VALUES(match_row.season_id,winner.id,winner_before,winner_before+winner_gain,1,0)
    ON CONFLICT(season_id,player_id) DO UPDATE SET
      high_elo=GREATEST(public.player_season_stats.high_elo,EXCLUDED.high_elo),
      wins=public.player_season_stats.wins+1;
    INSERT INTO public.player_season_stats(season_id,player_id,starting_elo,high_elo,wins,losses)
    VALUES(match_row.season_id,loser.id,loser_before,loser_before,0,1)
    ON CONFLICT(season_id,player_id) DO UPDATE SET
      high_elo=GREATEST(public.player_season_stats.high_elo,EXCLUDED.high_elo),
      losses=public.player_season_stats.losses+1;
  END IF;

  UPDATE public.matches SET
    status='confirmed',
    confirmed_by=p_actor,
    confirmed_at=NOW(),
    finalized_at=NOW(),
    expires_at=NULL,
    player_one_elo_before=player_one_before,
    player_two_elo_before=player_two_before,
    player_one_elo_change=player_one_delta,
    player_two_elo_change=player_two_delta,
    rating_calculation=calculation
  WHERE id=match_row.id;

  IF match_row.challenge_id IS NOT NULL THEN
    UPDATE public.challenges SET status='completed' WHERE id=match_row.challenge_id;
  END IF;
  domain_event:=public.emit_domain_event(
    'match.confirmed',p_actor,match_row.id,match_row.challenge_id,
    jsonb_build_object(
      'winner_id',winner.id,
      'player_one_change',player_one_delta,
      'player_two_change',player_two_delta,
      'rating_calculation',calculation
    ),ARRAY[match_row.player_one_id,match_row.player_two_id]
  );
  IF (SELECT COUNT(*) FROM public.matches recent
      WHERE recent.status='confirmed' AND recent.ranked
        AND recent.confirmed_at>NOW()-INTERVAL '24 hours'
        AND (recent.player_one_id IN(match_row.player_one_id,match_row.player_two_id)
          OR recent.player_two_id IN(match_row.player_one_id,match_row.player_two_id)))>=15 THEN
    INSERT INTO public.integrity_flags(player_id,match_id,flag_type,details)
    VALUES(p_actor,match_row.id,'high_match_volume',jsonb_build_object('window_hours',24));
  END IF;

  RETURN jsonb_build_object(
    'match_id',match_row.id,
    'already_finalized',FALSE,
    'player_one_change',player_one_delta,
    'player_two_change',player_two_delta,
    'player_one_new',player_one_before+player_one_delta,
    'player_two_new',player_two_before+player_two_delta,
    'rating_calculation',calculation
  );
END;
$$;

-- Admin corrections replay later ratings with the same asymmetric formula.
CREATE OR REPLACE FUNCTION public.replay_rankings_from_v3(
  p_from TIMESTAMPTZ,
  p_actor UUID,
  p_reason TEXT,
  p_target_match UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  timeline RECORD;
  match_row public.matches%ROWTYPE;
  calculation JSONB;
  player_one_before INTEGER;
  player_two_before INTEGER;
  player_one_delta INTEGER;
  player_two_delta INTEGER;
  winner_gain INTEGER;
  loser_loss INTEGER;
  next_revision INTEGER;
  new_player_one_event UUID;
  new_player_two_event UUID;
  replayed INTEGER:=0;
BEGIN
  IF p_from IS NULL THEN RAISE EXCEPTION 'Replay start is required'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('beaver-smash-rating-replay-v3',0));
  PERFORM id FROM public.profiles ORDER BY id FOR UPDATE;

  CREATE TEMP TABLE IF NOT EXISTS replay_ratings_v3(
    player_id UUID PRIMARY KEY,
    rating INTEGER NOT NULL
  ) ON COMMIT DROP;
  TRUNCATE replay_ratings_v3;
  INSERT INTO replay_ratings_v3(player_id,rating)
  SELECT profile.id,GREATEST(profile.current_elo-COALESCE(SUM(event.rating_change) FILTER(
    WHERE event.is_active AND COALESCE(match_history.confirmed_at,event.created_at)>=p_from
  ),0)::INTEGER,0)
  FROM public.profiles profile
  LEFT JOIN public.rating_events event ON event.player_id=profile.id
  LEFT JOIN public.matches match_history ON match_history.id=event.match_id
  GROUP BY profile.id,profile.current_elo;

  UPDATE public.rating_events event SET is_active=FALSE
  FROM public.matches voided_match
  WHERE event.match_id=voided_match.id AND event.is_active
    AND voided_match.status='voided' AND voided_match.confirmed_at>=p_from;

  FOR timeline IN
    SELECT 'adjustment'::TEXT kind,event.id item_id,event.created_at event_at
    FROM public.rating_events event
    WHERE event.match_id IS NULL AND event.is_active AND event.created_at>=p_from
    UNION ALL
    SELECT 'match',confirmed_match.id,confirmed_match.confirmed_at
    FROM public.matches confirmed_match
    WHERE confirmed_match.status='confirmed' AND confirmed_match.ranked
      AND confirmed_match.confirmed_at>=p_from
    ORDER BY event_at,kind,item_id
  LOOP
    IF timeline.kind='adjustment' THEN
      UPDATE replay_ratings_v3 replay SET rating=GREATEST(replay.rating+event.rating_change,0)
      FROM public.rating_events event
      WHERE event.id=timeline.item_id AND replay.player_id=event.player_id;
      CONTINUE;
    END IF;

    SELECT * INTO match_row FROM public.matches WHERE id=timeline.item_id FOR UPDATE;
    SELECT rating INTO player_one_before FROM replay_ratings_v3 WHERE player_id=match_row.player_one_id;
    SELECT rating INTO player_two_before FROM replay_ratings_v3 WHERE player_id=match_row.player_two_id;
    calculation:=public.calculate_weighted_elo_v3(
      CASE WHEN match_row.winner_id=match_row.player_one_id THEN player_one_before ELSE player_two_before END,
      CASE WHEN match_row.winner_id=match_row.player_one_id THEN player_two_before ELSE player_one_before END,
      GREATEST(match_row.player_one_score,match_row.player_two_score),
      LEAST(match_row.player_one_score,match_row.player_two_score)
    )||jsonb_build_object(
      'winner_id',match_row.winner_id,
      'loser_id',CASE WHEN match_row.winner_id=match_row.player_one_id
        THEN match_row.player_two_id ELSE match_row.player_one_id END,
      'winner_rating_before',CASE WHEN match_row.winner_id=match_row.player_one_id
        THEN player_one_before ELSE player_two_before END,
      'loser_rating_before',CASE WHEN match_row.winner_id=match_row.player_one_id
        THEN player_two_before ELSE player_one_before END,
      'replay_reason',p_reason
    );
    winner_gain:=(calculation->>'winner_gain')::INTEGER;
    loser_loss:=(calculation->>'loser_loss')::INTEGER;
    player_one_delta:=CASE WHEN match_row.winner_id=match_row.player_one_id
      THEN winner_gain ELSE -loser_loss END;
    player_two_delta:=CASE WHEN match_row.winner_id=match_row.player_two_id
      THEN winner_gain ELSE -loser_loss END;

    IF match_row.id=p_target_match THEN
      next_revision:=match_row.revision;
    ELSE
      next_revision:=match_row.revision+1;
      INSERT INTO public.match_revisions(
        match_id,revision,previous_winner_id,previous_player_one_score,previous_player_two_score,
        corrected_winner_id,corrected_player_one_score,corrected_player_two_score,corrected_by,reason
      ) VALUES(
        match_row.id,next_revision,match_row.winner_id,match_row.player_one_score,match_row.player_two_score,
        match_row.winner_id,match_row.player_one_score,match_row.player_two_score,p_actor,
        'Downstream rating replay: '||p_reason
      );
    END IF;

    UPDATE public.rating_events SET is_active=FALSE
    WHERE match_id=match_row.id AND is_active;
    INSERT INTO public.rating_events(
      match_id,player_id,event_kind,rating_before,rating_change,rating_after,
      revision,calculation,created_at
    ) VALUES(
      match_row.id,match_row.player_one_id,'match_result',player_one_before,
      player_one_delta,GREATEST(player_one_before+player_one_delta,0),
      next_revision,calculation,match_row.confirmed_at
    ) RETURNING id INTO new_player_one_event;
    INSERT INTO public.rating_events(
      match_id,player_id,event_kind,rating_before,rating_change,rating_after,
      revision,calculation,created_at
    ) VALUES(
      match_row.id,match_row.player_two_id,'match_result',player_two_before,
      player_two_delta,GREATEST(player_two_before+player_two_delta,0),
      next_revision,calculation,match_row.confirmed_at
    ) RETURNING id INTO new_player_two_event;
    UPDATE public.rating_events SET superseded_by=new_player_one_event
    WHERE match_id=match_row.id AND player_id=match_row.player_one_id
      AND id<>new_player_one_event AND superseded_by IS NULL;
    UPDATE public.rating_events SET superseded_by=new_player_two_event
    WHERE match_id=match_row.id AND player_id=match_row.player_two_id
      AND id<>new_player_two_event AND superseded_by IS NULL;

    UPDATE replay_ratings_v3 SET rating=GREATEST(player_one_before+player_one_delta,0)
    WHERE player_id=match_row.player_one_id;
    UPDATE replay_ratings_v3 SET rating=GREATEST(player_two_before+player_two_delta,0)
    WHERE player_id=match_row.player_two_id;
    UPDATE public.matches SET
      revision=next_revision,
      player_one_elo_before=player_one_before,
      player_two_elo_before=player_two_before,
      player_one_elo_change=player_one_delta,
      player_two_elo_change=player_two_delta,
      rating_calculation=calculation
    WHERE id=match_row.id;
    replayed:=replayed+1;
  END LOOP;

  UPDATE public.profiles profile SET current_elo=replay.rating,updated_at=NOW()
  FROM replay_ratings_v3 replay WHERE replay.player_id=profile.id;
  PERFORM public.rebuild_match_statistics_v3();
  RETURN jsonb_build_object('replayed_matches',replayed,'from',p_from);
END;
$$;

REVOKE ALL ON FUNCTION public.calculate_weighted_elo_v3(INTEGER,INTEGER,INTEGER,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_match_rating_preview_v3(UUID)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.finalize_match_v2(UUID,UUID)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.replay_rankings_from_v3(TIMESTAMPTZ,UUID,TEXT,UUID)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_rank_progress_v3(INTEGER,INTEGER)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.handle_new_user()
  FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.get_match_rating_preview_v3(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_rank_progress_v3(INTEGER,INTEGER) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
