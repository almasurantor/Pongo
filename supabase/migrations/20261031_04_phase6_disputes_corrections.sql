-- Beaver Smash V3 Phase 6: mutual post-result corrections/voids with rating replay.
BEGIN;

ALTER TABLE public.ranking_config
  ADD COLUMN IF NOT EXISTS dispute_window_hours INTEGER NOT NULL DEFAULT 48
    CHECK (dispute_window_hours BETWEEN 1 AND 168);
UPDATE public.ranking_config SET dispute_window_hours=48, updated_at=NOW() WHERE id;

ALTER TABLE public.disputes
  ADD COLUMN IF NOT EXISTS requested_resolution TEXT NOT NULL DEFAULT 'correction'
    CHECK (requested_resolution IN ('correction', 'void')),
  ADD COLUMN IF NOT EXISTS responded_by UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS response TEXT CHECK (response IN ('approved', 'declined')),
  ADD COLUMN IF NOT EXISTS responded_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS escalated_at TIMESTAMPTZ;

ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_reason_check;
ALTER TABLE public.disputes ADD CONSTRAINT disputes_reason_check CHECK (reason IN (
  'incorrect_score', 'incorrect_winner', 'match_never_happened', 'other',
  'wrong_score', 'wrong_winner', 'dual_conflict'
));
ALTER TABLE public.disputes DROP CONSTRAINT IF EXISTS disputes_status_check;
UPDATE public.disputes SET status='admin_review', escalated_at=COALESCE(escalated_at,NOW())
WHERE status='proposed';
ALTER TABLE public.disputes ADD CONSTRAINT disputes_status_check CHECK (status IN (
  'pending', 'admin_review', 'resolved', 'voided', 'declined', 'expired'
));
UPDATE public.disputes SET expires_at=COALESCE(expires_at,created_at+INTERVAL '48 hours')
WHERE status IN ('pending','admin_review');

DROP INDEX IF EXISTS public.one_open_dispute_per_match;
CREATE UNIQUE INDEX one_open_dispute_per_match ON public.disputes(match_id)
  WHERE status IN ('pending','admin_review');
CREATE INDEX IF NOT EXISTS disputes_pending_deadline_v3 ON public.disputes(expires_at)
  WHERE status='pending';

DROP POLICY IF EXISTS "Admins read revisions" ON public.match_revisions;
CREATE POLICY "Participants and admins read revisions" ON public.match_revisions
  FOR SELECT TO authenticated USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.matches m
      WHERE m.id=match_id AND auth.uid() IN (m.player_one_id,m.player_two_id)
    )
  );
GRANT SELECT ON public.match_revisions TO authenticated;

-- All rating writes use the same global lock as historical replay. This keeps
-- a new finalization from holding a match row while replay holds profile rows.
CREATE OR REPLACE FUNCTION public.submit_match_report_v2(
  p_match UUID,p_winner UUID,p_winner_score INTEGER,p_loser_score INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m public.matches;
  p1s INTEGER;
  p2s INTEGER;
  result JSONB;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('beaver-smash-rating-replay-v3',0));
  SELECT * INTO m FROM public.matches WHERE id=p_match FOR UPDATE;
  IF NOT FOUND OR auth.uid() NOT IN (m.player_one_id,m.player_two_id) THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF m.status='confirmed' THEN
    RETURN jsonb_build_object(
      'match_id',m.id,'status','confirmed','already_finalized',TRUE,
      'player_one_change',m.player_one_elo_change,'player_two_change',m.player_two_elo_change,
      'player_one_new',m.player_one_elo_before+m.player_one_elo_change,
      'player_two_new',m.player_two_elo_before+m.player_two_elo_change,
      'rating_calculation',m.rating_calculation
    );
  END IF;
  IF m.status<>'ready' THEN RAISE EXCEPTION 'Match is already closed'; END IF;
  IF m.expires_at IS NOT NULL AND m.expires_at<=NOW() THEN
    UPDATE public.match_cancellation_requests SET status='expired',responded_at=NOW()
    WHERE match_id=m.id AND status='pending';
    UPDATE public.matches SET status='expired',finalized_at=NOW() WHERE id=m.id;
    RETURN jsonb_build_object('match_id',m.id,'status','expired');
  END IF;
  IF p_winner NOT IN (m.player_one_id,m.player_two_id) OR p_winner_score IS NULL OR p_loser_score IS NULL OR p_winner_score<=p_loser_score THEN
    RAISE EXCEPTION 'Invalid winner or score';
  END IF;
  p1s:=CASE WHEN p_winner=m.player_one_id THEN p_winner_score ELSE p_loser_score END;
  p2s:=CASE WHEN p_winner=m.player_two_id THEN p_winner_score ELSE p_loser_score END;
  IF NOT public.is_valid_match_score_v2(p1s,p2s) THEN RAISE EXCEPTION 'Invalid table tennis score'; END IF;
  PERFORM public.assert_ranked_access(m.player_one_id);
  PERFORM public.assert_ranked_access(m.player_two_id);
  UPDATE public.matches SET
    winner_id=p_winner,player_one_score=p1s,player_two_score=p2s,
    reported_by=auth.uid(),reported_at=NOW(),status='result_reported'
  WHERE id=m.id;
  UPDATE public.match_cancellation_requests SET status='expired',responded_at=NOW()
  WHERE match_id=m.id AND status='pending';
  SELECT public.finalize_match_v2(m.id,auth.uid()) INTO result;
  RETURN result||jsonb_build_object('status','confirmed');
END;
$$;

CREATE OR REPLACE FUNCTION public.rebuild_match_statistics_v3()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item RECORD;
  current_week DATE := date_trunc('week',NOW() AT TIME ZONE 'America/New_York')::DATE;
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS replay_profile_stats_v3(
    player_id UUID PRIMARY KEY,
    wins INTEGER NOT NULL,
    losses INTEGER NOT NULL,
    weekly_wins INTEGER NOT NULL,
    weekly_losses INTEGER NOT NULL,
    current_streak INTEGER NOT NULL,
    longest_streak INTEGER NOT NULL
  ) ON COMMIT DROP;
  TRUNCATE replay_profile_stats_v3;
  INSERT INTO replay_profile_stats_v3
  SELECT id,0,0,0,0,0,0 FROM public.profiles;

  FOR item IN
    SELECT id,player_one_id,player_two_id,winner_id,confirmed_at
    FROM public.matches
    WHERE status='confirmed' AND ranked
    ORDER BY confirmed_at,id
  LOOP
    UPDATE replay_profile_stats_v3 SET
      wins=wins+1,
      weekly_wins=weekly_wins+CASE WHEN date_trunc('week',item.confirmed_at AT TIME ZONE 'America/New_York')::DATE=current_week THEN 1 ELSE 0 END,
      current_streak=CASE WHEN current_streak>=0 THEN current_streak+1 ELSE 1 END,
      longest_streak=GREATEST(longest_streak,CASE WHEN current_streak>=0 THEN current_streak+1 ELSE 1 END)
    WHERE player_id=item.winner_id;
    UPDATE replay_profile_stats_v3 SET
      losses=losses+1,
      weekly_losses=weekly_losses+CASE WHEN date_trunc('week',item.confirmed_at AT TIME ZONE 'America/New_York')::DATE=current_week THEN 1 ELSE 0 END,
      current_streak=CASE WHEN current_streak<=0 THEN current_streak-1 ELSE -1 END
    WHERE player_id=CASE WHEN item.winner_id=item.player_one_id THEN item.player_two_id ELSE item.player_one_id END;
  END LOOP;

  UPDATE public.profiles p SET
    total_wins=s.wins,total_losses=s.losses,
    weekly_wins=s.weekly_wins,weekly_losses=s.weekly_losses,
    current_streak=s.current_streak,longest_streak=s.longest_streak,
    highest_elo=GREATEST(
      (SELECT starting_elo FROM public.ranking_config WHERE id),
      COALESCE((SELECT MAX(re.rating_after) FROM public.rating_events re WHERE re.player_id=p.id AND re.is_active),p.current_elo),
      p.current_elo
    ),updated_at=NOW()
  FROM replay_profile_stats_v3 s WHERE s.player_id=p.id;

  DELETE FROM public.weekly_player_stats;
  INSERT INTO public.weekly_player_stats(player_id,week_start,wins,losses)
  SELECT player_id,week_start,
    COUNT(*) FILTER (WHERE won)::INTEGER,
    COUNT(*) FILTER (WHERE NOT won)::INTEGER
  FROM (
    SELECT m.player_one_id AS player_id,
      date_trunc('week',m.confirmed_at AT TIME ZONE 'America/New_York')::DATE AS week_start,
      m.winner_id=m.player_one_id AS won
    FROM public.matches m WHERE m.status='confirmed' AND m.ranked
    UNION ALL
    SELECT m.player_two_id,
      date_trunc('week',m.confirmed_at AT TIME ZONE 'America/New_York')::DATE,
      m.winner_id=m.player_two_id
    FROM public.matches m WHERE m.status='confirmed' AND m.ranked
  ) expanded
  GROUP BY player_id,week_start;

  DELETE FROM public.player_season_stats;
  INSERT INTO public.player_season_stats(
    season_id,player_id,starting_elo,ending_elo,high_elo,wins,losses
  )
  SELECT season_id,player_id,
    (ARRAY_AGG(rating_before ORDER BY confirmed_at,id))[1],
    (ARRAY_AGG(rating_after ORDER BY confirmed_at DESC,id DESC))[1],
    MAX(GREATEST(rating_before,rating_after)),
    COUNT(*) FILTER (WHERE won)::INTEGER,
    COUNT(*) FILTER (WHERE NOT won)::INTEGER
  FROM (
    SELECT m.id,m.season_id,m.confirmed_at,m.player_one_id AS player_id,
      m.player_one_elo_before AS rating_before,
      m.player_one_elo_before+m.player_one_elo_change AS rating_after,
      m.winner_id=m.player_one_id AS won
    FROM public.matches m WHERE m.status='confirmed' AND m.ranked AND m.season_id IS NOT NULL
    UNION ALL
    SELECT m.id,m.season_id,m.confirmed_at,m.player_two_id,
      m.player_two_elo_before,m.player_two_elo_before+m.player_two_elo_change,
      m.winner_id=m.player_two_id
    FROM public.matches m WHERE m.status='confirmed' AND m.ranked AND m.season_id IS NOT NULL
  ) expanded
  GROUP BY season_id,player_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.replay_rankings_from_v3(
  p_from TIMESTAMPTZ,
  p_actor UUID,
  p_reason TEXT,
  p_target_match UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  timeline RECORD;
  m public.matches;
  calculation JSONB;
  p1_before INTEGER;
  p2_before INTEGER;
  p1_delta INTEGER;
  p2_delta INTEGER;
  delta INTEGER;
  next_revision INTEGER;
  new_p1_event UUID;
  new_p2_event UUID;
  replayed INTEGER := 0;
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
  SELECT p.id,p.current_elo-COALESCE(SUM(re.rating_change) FILTER (
    WHERE re.is_active AND COALESCE(m.confirmed_at,re.created_at)>=p_from
  ),0)::INTEGER
  FROM public.profiles p
  LEFT JOIN public.rating_events re ON re.player_id=p.id
  LEFT JOIN public.matches m ON m.id=re.match_id
  GROUP BY p.id,p.current_elo;

  -- Voided results are removed after their old delta has been subtracted above.
  UPDATE public.rating_events re SET is_active=FALSE
  FROM public.matches vm
  WHERE re.match_id=vm.id AND re.is_active
    AND vm.status='voided' AND vm.confirmed_at>=p_from;

  FOR timeline IN
    SELECT 'adjustment'::TEXT AS kind,re.id AS item_id,re.created_at AS event_at
    FROM public.rating_events re
    WHERE re.match_id IS NULL AND re.is_active AND re.created_at>=p_from
    UNION ALL
    SELECT 'match',cm.id,cm.confirmed_at
    FROM public.matches cm
    WHERE cm.status='confirmed' AND cm.ranked AND cm.confirmed_at>=p_from
    ORDER BY event_at,kind,item_id
  LOOP
    IF timeline.kind='adjustment' THEN
      UPDATE replay_ratings_v3 rr SET rating=rr.rating+re.rating_change
      FROM public.rating_events re
      WHERE re.id=timeline.item_id AND rr.player_id=re.player_id;
      CONTINUE;
    END IF;

    SELECT * INTO m FROM public.matches WHERE id=timeline.item_id FOR UPDATE;
    SELECT rating INTO p1_before FROM replay_ratings_v3 WHERE player_id=m.player_one_id;
    SELECT rating INTO p2_before FROM replay_ratings_v3 WHERE player_id=m.player_two_id;
    calculation:=public.calculate_weighted_elo_v3(
      CASE WHEN m.winner_id=m.player_one_id THEN p1_before ELSE p2_before END,
      CASE WHEN m.winner_id=m.player_one_id THEN p2_before ELSE p1_before END,
      GREATEST(m.player_one_score,m.player_two_score),
      LEAST(m.player_one_score,m.player_two_score)
    ) || jsonb_build_object(
      'winner_id',m.winner_id,
      'loser_id',CASE WHEN m.winner_id=m.player_one_id THEN m.player_two_id ELSE m.player_one_id END,
      'winner_rating_before',CASE WHEN m.winner_id=m.player_one_id THEN p1_before ELSE p2_before END,
      'loser_rating_before',CASE WHEN m.winner_id=m.player_one_id THEN p2_before ELSE p1_before END,
      'replay_reason',p_reason
    );
    delta:=(calculation->>'final_delta')::INTEGER;
    p1_delta:=CASE WHEN m.winner_id=m.player_one_id THEN delta ELSE -delta END;
    p2_delta:=-p1_delta;

    IF m.id=p_target_match THEN
      next_revision:=m.revision;
    ELSE
      next_revision:=m.revision+1;
      INSERT INTO public.match_revisions(
        match_id,revision,previous_winner_id,previous_player_one_score,previous_player_two_score,
        corrected_winner_id,corrected_player_one_score,corrected_player_two_score,corrected_by,reason
      ) VALUES(
        m.id,next_revision,m.winner_id,m.player_one_score,m.player_two_score,
        m.winner_id,m.player_one_score,m.player_two_score,p_actor,'Downstream rating replay: '||p_reason
      );
    END IF;

    UPDATE public.rating_events SET is_active=FALSE
    WHERE match_id=m.id AND is_active;
    INSERT INTO public.rating_events(
      match_id,player_id,event_kind,rating_before,rating_change,rating_after,revision,calculation,created_at
    ) VALUES(
      m.id,m.player_one_id,'match_result',p1_before,p1_delta,p1_before+p1_delta,next_revision,calculation,m.confirmed_at
    ) RETURNING id INTO new_p1_event;
    INSERT INTO public.rating_events(
      match_id,player_id,event_kind,rating_before,rating_change,rating_after,revision,calculation,created_at
    ) VALUES(
      m.id,m.player_two_id,'match_result',p2_before,p2_delta,p2_before+p2_delta,next_revision,calculation,m.confirmed_at
    ) RETURNING id INTO new_p2_event;
    UPDATE public.rating_events SET superseded_by=new_p1_event
    WHERE match_id=m.id AND player_id=m.player_one_id AND id<>new_p1_event AND superseded_by IS NULL;
    UPDATE public.rating_events SET superseded_by=new_p2_event
    WHERE match_id=m.id AND player_id=m.player_two_id AND id<>new_p2_event AND superseded_by IS NULL;

    UPDATE replay_ratings_v3 SET rating=p1_before+p1_delta WHERE player_id=m.player_one_id;
    UPDATE replay_ratings_v3 SET rating=p2_before+p2_delta WHERE player_id=m.player_two_id;
    UPDATE public.matches SET
      revision=next_revision,
      player_one_elo_before=p1_before,player_two_elo_before=p2_before,
      player_one_elo_change=p1_delta,player_two_elo_change=p2_delta,
      rating_calculation=calculation
    WHERE id=m.id;
    replayed:=replayed+1;
  END LOOP;

  UPDATE public.profiles p SET current_elo=rr.rating,updated_at=NOW()
  FROM replay_ratings_v3 rr WHERE rr.player_id=p.id;
  PERFORM public.rebuild_match_statistics_v3();
  RETURN jsonb_build_object('replayed_matches',replayed,'from',p_from);
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_match_revision_v3(
  p_match UUID,
  p_resolution TEXT,
  p_winner UUID,
  p_player_one_score INTEGER,
  p_player_two_score INTEGER,
  p_actor UUID,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m public.matches;
  replay JSONB;
  next_revision INTEGER;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id=p_match FOR UPDATE;
  IF NOT FOUND OR m.status<>'confirmed' THEN RAISE EXCEPTION 'Confirmed match not found'; END IF;
  IF p_resolution NOT IN ('correction','void') THEN RAISE EXCEPTION 'Invalid revision resolution'; END IF;
  IF p_resolution='correction' AND (
    p_winner NOT IN (m.player_one_id,m.player_two_id)
    OR NOT public.is_valid_match_score_v2(p_player_one_score,p_player_two_score)
    OR (p_winner=m.player_one_id AND p_player_one_score<=p_player_two_score)
    OR (p_winner=m.player_two_id AND p_player_two_score<=p_player_one_score)
  ) THEN RAISE EXCEPTION 'Invalid corrected result'; END IF;

  next_revision:=m.revision+1;
  INSERT INTO public.match_revisions(
    match_id,revision,previous_winner_id,previous_player_one_score,previous_player_two_score,
    corrected_winner_id,corrected_player_one_score,corrected_player_two_score,corrected_by,reason
  ) VALUES(
    m.id,next_revision,m.winner_id,m.player_one_score,m.player_two_score,
    CASE WHEN p_resolution='void' THEN NULL ELSE p_winner END,
    CASE WHEN p_resolution='void' THEN NULL ELSE p_player_one_score END,
    CASE WHEN p_resolution='void' THEN NULL ELSE p_player_two_score END,
    p_actor,p_reason
  );

  IF p_resolution='void' THEN
    UPDATE public.matches SET status='voided',revision=next_revision,finalized_at=NOW()
    WHERE id=m.id;
  ELSE
    UPDATE public.matches SET winner_id=p_winner,
      player_one_score=p_player_one_score,player_two_score=p_player_two_score,
      revision=next_revision
    WHERE id=m.id;
  END IF;
  SELECT public.replay_rankings_from_v3(m.confirmed_at,p_actor,p_reason,m.id) INTO replay;
  RETURN replay || jsonb_build_object('match_id',m.id,'status',CASE WHEN p_resolution='void' THEN 'voided' ELSE 'confirmed' END,'revision',next_revision);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_match_dispute_v3(
  p_match UUID,
  p_reason TEXT,
  p_requested_resolution TEXT,
  p_winner UUID DEFAULT NULL,
  p_winner_score INTEGER DEFAULT NULL,
  p_loser_score INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m public.matches;
  d public.disputes;
  cfg public.ranking_config;
  opponent UUID;
  p1s INTEGER;
  p2s INTEGER;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id=p_match FOR UPDATE;
  IF NOT FOUND OR m.status<>'confirmed' OR auth.uid() NOT IN (m.player_one_id,m.player_two_id) THEN
    RAISE EXCEPTION 'Confirmed match not found';
  END IF;
  SELECT * INTO cfg FROM public.ranking_config WHERE id;
  IF m.confirmed_at+make_interval(hours=>cfg.dispute_window_hours)<=NOW() THEN
    RAISE EXCEPTION 'The 48-hour dispute window has expired';
  END IF;
  IF p_reason NOT IN ('incorrect_score','incorrect_winner','match_never_happened','other') THEN
    RAISE EXCEPTION 'Invalid dispute reason';
  END IF;
  IF p_requested_resolution NOT IN ('correction','void') THEN RAISE EXCEPTION 'Invalid requested resolution'; END IF;
  IF p_reason='match_never_happened' AND p_requested_resolution<>'void' THEN
    RAISE EXCEPTION 'A match-never-happened dispute must request a void';
  END IF;
  IF EXISTS(SELECT 1 FROM public.disputes WHERE match_id=m.id AND status IN ('pending','admin_review')) THEN
    RAISE EXCEPTION 'This match already has an open dispute';
  END IF;

  IF p_requested_resolution='correction' THEN
    IF p_winner NOT IN (m.player_one_id,m.player_two_id) OR p_winner_score<=p_loser_score THEN
      RAISE EXCEPTION 'A valid corrected result is required';
    END IF;
    p1s:=CASE WHEN p_winner=m.player_one_id THEN p_winner_score ELSE p_loser_score END;
    p2s:=CASE WHEN p_winner=m.player_two_id THEN p_winner_score ELSE p_loser_score END;
    IF NOT public.is_valid_match_score_v2(p1s,p2s) THEN RAISE EXCEPTION 'Invalid corrected score'; END IF;
  ELSE
    p_winner:=m.winner_id;p1s:=m.player_one_score;p2s:=m.player_two_score;
  END IF;

  INSERT INTO public.disputes(
    match_id,opened_by,reason,requested_resolution,
    original_winner_id,original_player_one_score,original_player_two_score,
    proposed_winner_id,proposed_player_one_score,proposed_player_two_score,
    status,expires_at
  ) VALUES(
    m.id,auth.uid(),p_reason,p_requested_resolution,
    m.winner_id,m.player_one_score,m.player_two_score,
    p_winner,p1s,p2s,'pending',NOW()+INTERVAL '48 hours'
  ) RETURNING * INTO d;
  opponent:=CASE WHEN auth.uid()=m.player_one_id THEN m.player_two_id ELSE m.player_one_id END;
  PERFORM public.emit_domain_event(
    'match.dispute_opened',auth.uid(),m.id,m.challenge_id,
    jsonb_build_object('dispute_id',d.id,'reason',d.reason,'requested_resolution',d.requested_resolution,'expires_at',d.expires_at),
    ARRAY[opponent]
  );
  RETURN jsonb_build_object('dispute_id',d.id,'match_id',m.id,'status','pending','expires_at',d.expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_match_dispute_v3(p_dispute UUID,p_action TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d public.disputes;
  m public.matches;
  result JSONB;
BEGIN
  SELECT * INTO d FROM public.disputes WHERE id=p_dispute FOR UPDATE;
  IF NOT FOUND OR d.status<>'pending' THEN RAISE EXCEPTION 'Dispute is not actionable'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('beaver-smash-rating-replay-v3',0));
  SELECT * INTO m FROM public.matches WHERE id=d.match_id FOR UPDATE;
  IF auth.uid() NOT IN (m.player_one_id,m.player_two_id) OR auth.uid()=d.opened_by THEN
    RAISE EXCEPTION 'Only the opponent can respond';
  END IF;
  IF d.expires_at<=NOW() THEN
    UPDATE public.disputes SET status='admin_review',escalated_at=NOW() WHERE id=d.id;
    PERFORM public.emit_domain_event('match.dispute_escalated',auth.uid(),m.id,m.challenge_id,
      jsonb_build_object('dispute_id',d.id,'reason','response_timeout'),
      ARRAY(SELECT user_id FROM public.user_roles WHERE role='admin')||ARRAY[d.opened_by]);
    RETURN jsonb_build_object('dispute_id',d.id,'match_id',m.id,'status','admin_review','deadline_expired',TRUE);
  END IF;
  IF p_action='decline' THEN
    UPDATE public.disputes SET status='admin_review',response='declined',responded_by=auth.uid(),responded_at=NOW(),escalated_at=NOW()
    WHERE id=d.id;
    PERFORM public.emit_domain_event('match.dispute_escalated',auth.uid(),m.id,m.challenge_id,
      jsonb_build_object('dispute_id',d.id),
      ARRAY(SELECT user_id FROM public.user_roles WHERE role='admin')||ARRAY[d.opened_by]);
    RETURN jsonb_build_object('dispute_id',d.id,'match_id',m.id,'status','admin_review');
  ELSIF p_action<>'approve' THEN RAISE EXCEPTION 'Invalid dispute action'; END IF;

  SELECT public.apply_match_revision_v3(
    m.id,d.requested_resolution,d.proposed_winner_id,
    d.proposed_player_one_score,d.proposed_player_two_score,
    auth.uid(),'Mutually approved dispute '||d.id::TEXT
  ) INTO result;
  UPDATE public.disputes SET
    status=CASE WHEN d.requested_resolution='void' THEN 'voided' ELSE 'resolved' END,
    response='approved',responded_by=auth.uid(),responded_at=NOW(),
    resolved_by=auth.uid(),resolution=CASE WHEN d.requested_resolution='void' THEN 'voided' ELSE 'proposed' END,resolved_at=NOW()
  WHERE id=d.id;
  PERFORM public.emit_domain_event('match.dispute_approved',auth.uid(),m.id,m.challenge_id,
    jsonb_build_object('dispute_id',d.id,'resolution',d.requested_resolution,'revision',result->'revision'),
    ARRAY[m.player_one_id,m.player_two_id]);
  RETURN result || jsonb_build_object('dispute_id',d.id,'dispute_status',CASE WHEN d.requested_resolution='void' THEN 'voided' ELSE 'resolved' END);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute_v3(
  p_dispute UUID,p_resolution TEXT,p_winner UUID DEFAULT NULL,p_winner_score INTEGER DEFAULT NULL,
  p_loser_score INTEGER DEFAULT NULL,p_violation_user UUID DEFAULT NULL,p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d public.disputes;
  m public.matches;
  p1s INTEGER;
  p2s INTEGER;
  result JSONB := '{}'::JSONB;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;
  SELECT * INTO d FROM public.disputes WHERE id=p_dispute FOR UPDATE;
  IF NOT FOUND OR d.status NOT IN ('pending','admin_review') THEN RAISE EXCEPTION 'Dispute is not open'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('beaver-smash-rating-replay-v3',0));
  SELECT * INTO m FROM public.matches WHERE id=d.match_id FOR UPDATE;
  IF p_violation_user IS NOT NULL
     AND p_violation_user NOT IN (m.player_one_id,m.player_two_id) THEN
    RAISE EXCEPTION 'Violation user must be a match participant';
  END IF;
  IF p_resolution='no_violation' AND p_violation_user IS NOT NULL THEN
    RAISE EXCEPTION 'No-violation resolutions cannot assign a violation';
  END IF;

  IF p_resolution IN ('original','no_violation') THEN
    result:=jsonb_build_object('match_id',m.id,'status',m.status,'unchanged',TRUE);
  ELSIF p_resolution='proposed' THEN
    SELECT public.apply_match_revision_v3(m.id,d.requested_resolution,d.proposed_winner_id,
      d.proposed_player_one_score,d.proposed_player_two_score,auth.uid(),'Admin-approved dispute '||d.id::TEXT) INTO result;
  ELSIF p_resolution='voided' THEN
    SELECT public.apply_match_revision_v3(m.id,'void',m.winner_id,m.player_one_score,m.player_two_score,
      auth.uid(),'Admin-voided dispute '||d.id::TEXT) INTO result;
  ELSIF p_resolution='custom' THEN
    IF p_winner NOT IN (m.player_one_id,m.player_two_id) OR p_winner_score<=p_loser_score THEN RAISE EXCEPTION 'Invalid custom result'; END IF;
    p1s:=CASE WHEN p_winner=m.player_one_id THEN p_winner_score ELSE p_loser_score END;
    p2s:=CASE WHEN p_winner=m.player_two_id THEN p_winner_score ELSE p_loser_score END;
    SELECT public.apply_match_revision_v3(m.id,'correction',p_winner,p1s,p2s,auth.uid(),'Admin correction for dispute '||d.id::TEXT) INTO result;
  ELSE RAISE EXCEPTION 'Invalid resolution'; END IF;

  UPDATE public.disputes SET
    status=CASE WHEN p_resolution='voided' OR (p_resolution='proposed' AND requested_resolution='void') THEN 'voided' ELSE 'resolved' END,
    resolved_by=auth.uid(),resolution=p_resolution,violation_user_id=p_violation_user,
    admin_notes=p_notes,resolved_at=NOW()
  WHERE id=d.id;
  IF p_violation_user IS NOT NULL THEN
    UPDATE public.player_integrity SET confirmed_violations=confirmed_violations+1,updated_by=auth.uid(),updated_at=NOW()
    WHERE player_id=p_violation_user;
    INSERT INTO public.integrity_flags(player_id,match_id,flag_type,details,reviewed_by,reviewed_at)
    VALUES(p_violation_user,m.id,'confirmed_violation',jsonb_build_object('dispute_id',d.id),auth.uid(),NOW());
  END IF;
  PERFORM public.emit_domain_event('match.dispute_resolved',auth.uid(),m.id,m.challenge_id,
    jsonb_build_object('dispute_id',d.id,'resolution',p_resolution),ARRAY[m.player_one_id,m.player_two_id]);
  RETURN result || jsonb_build_object('dispute_id',d.id,'resolution',p_resolution);
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_mobile_ranking_items_v2()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  challenge_count INTEGER;
  match_count INTEGER;
  cancellation_count INTEGER;
  dispute_count INTEGER;
  stale RECORD;
BEGIN
  UPDATE public.challenges SET status='expired' WHERE status='pending' AND expires_at<=NOW();
  GET DIAGNOSTICS challenge_count=ROW_COUNT;
  WITH expired_matches AS (
    UPDATE public.matches SET status='expired',finalized_at=NOW()
    WHERE status='ready' AND expires_at IS NOT NULL AND expires_at<=NOW() RETURNING id
  ), expired_requests AS (
    UPDATE public.match_cancellation_requests r SET status='expired',responded_at=NOW()
    FROM expired_matches m WHERE r.match_id=m.id AND r.status='pending' RETURNING r.id
  )
  SELECT (SELECT COUNT(*) FROM expired_matches),(SELECT COUNT(*) FROM expired_requests)
  INTO match_count,cancellation_count;

  dispute_count:=0;
  FOR stale IN
    UPDATE public.disputes SET status='admin_review',escalated_at=NOW()
    WHERE status='pending' AND expires_at<=NOW()
    RETURNING id,match_id,opened_by
  LOOP
    dispute_count:=dispute_count+1;
    PERFORM public.emit_domain_event('match.dispute_escalated',NULL,stale.match_id,NULL,
      jsonb_build_object('dispute_id',stale.id,'reason','response_timeout'),
      ARRAY(SELECT user_id FROM public.user_roles WHERE role='admin')||ARRAY[stale.opened_by]);
  END LOOP;
  RETURN jsonb_build_object(
    'expired_challenges',challenge_count,'expired_matches',match_count,
    'expired_cancellation_requests',cancellation_count,'escalated_disputes',dispute_count
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rebuild_match_statistics_v3() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.replay_rankings_from_v3(TIMESTAMPTZ,UUID,TEXT,UUID) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.apply_match_revision_v3(UUID,TEXT,UUID,INTEGER,INTEGER,UUID,TEXT) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.submit_match_report_v2(UUID,UUID,INTEGER,INTEGER) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.submit_match_report_v2(UUID,UUID,INTEGER,INTEGER) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_match_dispute_v3(UUID,TEXT,TEXT,UUID,INTEGER,INTEGER) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_match_dispute_v3(UUID,TEXT,TEXT,UUID,INTEGER,INTEGER) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.respond_match_dispute_v3(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.respond_match_dispute_v3(UUID,TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_resolve_dispute_v3(UUID,TEXT,UUID,INTEGER,INTEGER,UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute_v3(UUID,TEXT,UUID,INTEGER,INTEGER,UUID,TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_resolve_dispute_v2(UUID,TEXT,UUID,INTEGER,INTEGER,UUID,TEXT) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.expire_mobile_ranking_items_v2() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.expire_mobile_ranking_items_v2() TO service_role;

COMMIT;
