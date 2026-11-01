-- Beaver Smash V3 Phase 8: audit immutability, privilege hardening, and optional dual verification.
BEGIN;

-- Preserve only the newest active revision if legacy correction code left more
-- than one active event for the same match/player pair.
WITH duplicate_events AS (
  SELECT id,ROW_NUMBER() OVER (
    PARTITION BY match_id,player_id
    ORDER BY revision DESC,created_at DESC,id DESC
  ) AS active_order
  FROM public.rating_events
  WHERE match_id IS NOT NULL AND is_active
)
UPDATE public.rating_events re SET is_active=FALSE
FROM duplicate_events duplicate
WHERE re.id=duplicate.id AND duplicate.active_order>1;

CREATE UNIQUE INDEX IF NOT EXISTS one_active_rating_event_per_match_player_v3
  ON public.rating_events(match_id,player_id)
  WHERE match_id IS NOT NULL AND is_active;

CREATE OR REPLACE FUNCTION public.protect_rating_event_ledger_v3()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Rating events cannot be deleted'; END IF;
  IF NEW.id<>OLD.id
    OR NEW.match_id IS DISTINCT FROM OLD.match_id
    OR NEW.player_id<>OLD.player_id
    OR NEW.event_kind<>OLD.event_kind
    OR NEW.rating_before<>OLD.rating_before
    OR NEW.rating_change<>OLD.rating_change
    OR NEW.rating_after<>OLD.rating_after
    OR NEW.revision<>OLD.revision
    OR NEW.calculation IS DISTINCT FROM OLD.calculation
    OR NEW.rank_before IS DISTINCT FROM OLD.rank_before
    OR NEW.rank_after IS DISTINCT FROM OLD.rank_after
    OR NEW.created_at<>OLD.created_at
  THEN RAISE EXCEPTION 'Rating event facts are immutable'; END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS protect_rating_event_ledger_v3 ON public.rating_events;
CREATE TRIGGER protect_rating_event_ledger_v3
BEFORE UPDATE OR DELETE ON public.rating_events
FOR EACH ROW EXECUTE FUNCTION public.protect_rating_event_ledger_v3();

CREATE OR REPLACE FUNCTION public.prevent_audit_row_changes_v3()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION '% rows are append-only',TG_TABLE_NAME;
END;
$$;
DROP TRIGGER IF EXISTS protect_match_revisions_v3 ON public.match_revisions;
CREATE TRIGGER protect_match_revisions_v3 BEFORE UPDATE OR DELETE ON public.match_revisions
FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_row_changes_v3();
DROP TRIGGER IF EXISTS protect_domain_events_v3 ON public.domain_events;
CREATE TRIGGER protect_domain_events_v3 BEFORE UPDATE OR DELETE ON public.domain_events
FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_row_changes_v3();
DROP TRIGGER IF EXISTS protect_match_submissions_v3 ON public.match_submissions;
CREATE TRIGGER protect_match_submissions_v3 BEFORE UPDATE OR DELETE ON public.match_submissions
FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_row_changes_v3();

CREATE OR REPLACE FUNCTION public.apply_integrity_threshold_v3()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Two admin-confirmed violations make the account visible as monitored.
  -- Dual verification and ranked restriction remain deliberate admin choices.
  IF NEW.confirmed_violations>=2 AND NEW.verification_level='normal' THEN
    NEW.verification_level:='monitored';
    NEW.restriction_reason:=COALESCE(NEW.restriction_reason,'Automatically monitored after repeated confirmed violations.');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS apply_integrity_threshold_v3 ON public.player_integrity;
CREATE TRIGGER apply_integrity_threshold_v3
BEFORE INSERT OR UPDATE OF confirmed_violations ON public.player_integrity
FOR EACH ROW EXECUTE FUNCTION public.apply_integrity_threshold_v3();

-- Turn the existing admin-controlled dual_verification level into a real match
-- safeguard without changing the normal first-valid-score lifecycle.
CREATE OR REPLACE FUNCTION public.assign_match_verification_mode_v3()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.ranked AND EXISTS(
    SELECT 1 FROM public.player_integrity integrity
    WHERE integrity.player_id IN (NEW.player_one_id,NEW.player_two_id)
      AND integrity.verification_level='dual_verification'
  ) THEN NEW.verification_mode:='dual';
  ELSE NEW.verification_mode:='normal';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS assign_match_verification_mode_v3 ON public.matches;
CREATE TRIGGER assign_match_verification_mode_v3
BEFORE INSERT ON public.matches
FOR EACH ROW EXECUTE FUNCTION public.assign_match_verification_mode_v3();

UPDATE public.matches active_match SET verification_mode='dual'
WHERE active_match.status='ready' AND active_match.ranked
  AND EXISTS(
    SELECT 1 FROM public.player_integrity integrity
    WHERE integrity.player_id IN (active_match.player_one_id,active_match.player_two_id)
      AND integrity.verification_level='dual_verification'
  );

DROP POLICY IF EXISTS "Admins read all matches" ON public.matches;
CREATE POLICY "Admins read all matches" ON public.matches
FOR SELECT TO authenticated USING(public.is_admin());

CREATE OR REPLACE FUNCTION public.monitor_confirmed_match_integrity_v3()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pair_games INTEGER;
  player_games INTEGER;
  participant UUID;
BEGIN
  IF NEW.status<>'confirmed' OR OLD.status='confirmed' OR NOT NEW.ranked THEN RETURN NEW; END IF;

  SELECT COUNT(*) INTO pair_games FROM public.matches candidate
  WHERE candidate.status='confirmed' AND candidate.ranked
    AND candidate.ranked_day=NEW.ranked_day
    AND LEAST(candidate.player_one_id,candidate.player_two_id)=LEAST(NEW.player_one_id,NEW.player_two_id)
    AND GREATEST(candidate.player_one_id,candidate.player_two_id)=GREATEST(NEW.player_one_id,NEW.player_two_id);
  IF pair_games>=3 THEN
    INSERT INTO public.integrity_flags(match_id,flag_type,details)
    VALUES(NEW.id,'pair_daily_ceiling',jsonb_build_object('ranked_day',NEW.ranked_day,'confirmed_pair_games',pair_games));
  END IF;

  FOREACH participant IN ARRAY ARRAY[NEW.player_one_id,NEW.player_two_id] LOOP
    SELECT COUNT(*) INTO player_games FROM public.matches candidate
    WHERE candidate.status='confirmed' AND candidate.ranked
      AND candidate.ranked_day=NEW.ranked_day
      AND participant IN (candidate.player_one_id,candidate.player_two_id);
    IF player_games>=8 THEN
      INSERT INTO public.integrity_flags(player_id,match_id,flag_type,details)
      VALUES(participant,NEW.id,'high_daily_ranked_volume',jsonb_build_object('ranked_day',NEW.ranked_day,'confirmed_games',player_games));
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS monitor_confirmed_match_integrity_v3 ON public.matches;
CREATE TRIGGER monitor_confirmed_match_integrity_v3
AFTER UPDATE OF status ON public.matches
FOR EACH ROW EXECUTE FUNCTION public.monitor_confirmed_match_integrity_v3();

CREATE OR REPLACE FUNCTION public.admin_review_integrity_flag_v3(p_flag UUID)
RETURNS public.integrity_flags
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE reviewed public.integrity_flags;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;
  UPDATE public.integrity_flags SET reviewed_by=COALESCE(reviewed_by,auth.uid()),reviewed_at=COALESCE(reviewed_at,NOW())
  WHERE id=p_flag RETURNING * INTO reviewed;
  IF NOT FOUND THEN RAISE EXCEPTION 'Integrity flag not found'; END IF;
  RETURN reviewed;
END;
$$;

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
  first_report public.match_submissions;
  second_report public.match_submissions;
  result JSONB;
  opponent UUID;
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

  IF m.verification_mode='dual' THEN
    SELECT * INTO first_report FROM public.match_submissions
    WHERE match_id=m.id ORDER BY created_at,id LIMIT 1 FOR UPDATE;
    IF NOT FOUND THEN
      INSERT INTO public.match_submissions(match_id,submitted_by,winner_id,player_one_score,player_two_score)
      VALUES(m.id,auth.uid(),p_winner,p1s,p2s)
      RETURNING * INTO first_report;
      opponent:=CASE WHEN auth.uid()=m.player_one_id THEN m.player_two_id ELSE m.player_one_id END;
      PERFORM public.emit_domain_event('match.independent_report_needed',auth.uid(),m.id,m.challenge_id,
        jsonb_build_object('expires_at',m.expires_at),ARRAY[opponent]);
      RETURN jsonb_build_object('match_id',m.id,'submission_id',first_report.id,'status','awaiting_independent_report','ratings_changed',FALSE);
    END IF;
    IF first_report.submitted_by=auth.uid() THEN
      RETURN jsonb_build_object('match_id',m.id,'status','awaiting_independent_report','idempotent',TRUE,'ratings_changed',FALSE);
    END IF;
    INSERT INTO public.match_submissions(match_id,submitted_by,winner_id,player_one_score,player_two_score)
    VALUES(m.id,auth.uid(),p_winner,p1s,p2s)
    RETURNING * INTO second_report;
    IF first_report.winner_id<>second_report.winner_id
       OR first_report.player_one_score<>second_report.player_one_score
       OR first_report.player_two_score<>second_report.player_two_score THEN
      UPDATE public.matches SET status='expired',finalized_at=NOW() WHERE id=m.id;
      UPDATE public.match_cancellation_requests SET status='expired',responded_at=NOW()
      WHERE match_id=m.id AND status='pending';
      INSERT INTO public.integrity_flags(match_id,flag_type,details)
      VALUES(m.id,'dual_report_conflict',jsonb_build_object(
        'first_submission_id',first_report.id,'second_submission_id',second_report.id
      ));
      PERFORM public.emit_domain_event('match.dual_conflict',auth.uid(),m.id,m.challenge_id,
        jsonb_build_object('first_submission_id',first_report.id),
        ARRAY[m.player_one_id,m.player_two_id]||ARRAY(SELECT user_id FROM public.user_roles WHERE role='admin'));
      RETURN jsonb_build_object('match_id',m.id,'status','expired','conflicting_reports',TRUE,'ratings_changed',FALSE);
    END IF;
    UPDATE public.matches SET
      winner_id=p_winner,player_one_score=p1s,player_two_score=p2s,
      reported_by=first_report.submitted_by,reported_at=first_report.created_at,
      confirmed_by=auth.uid(),status='result_reported'
    WHERE id=m.id;
  ELSE
    UPDATE public.matches SET
      winner_id=p_winner,player_one_score=p1s,player_two_score=p2s,
      reported_by=auth.uid(),reported_at=NOW(),status='result_reported'
    WHERE id=m.id;
  END IF;

  UPDATE public.match_cancellation_requests SET status='expired',responded_at=NOW()
  WHERE match_id=m.id AND status='pending';
  SELECT public.finalize_match_v2(m.id,auth.uid()) INTO result;
  RETURN result||jsonb_build_object('status','confirmed');
END;
$$;

-- Revoke direct mutations on every sensitive lifecycle/audit table even if an
-- earlier project default grant was broader than the repository baseline.
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON
  public.matches,public.challenges,public.match_cancellation_requests,
  public.match_submissions,public.disputes,public.match_revisions,
  public.rating_events,public.domain_events,public.notifications,
  public.integrity_flags,public.player_integrity,public.user_roles
FROM authenticated,anon;
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON
  public.ranking_config,public.profile_stat_baselines,public.weekly_player_stats,
  public.seasons,public.player_season_stats,public.competitive_rank_tiers
FROM authenticated,anon;
REVOKE INSERT,DELETE,TRUNCATE ON public.profiles FROM authenticated,anon;
REVOKE UPDATE ON public.profiles FROM authenticated,anon;
GRANT UPDATE(display_name) ON public.profiles TO authenticated;

REVOKE EXECUTE ON FUNCTION public.protect_rating_event_ledger_v3() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.prevent_audit_row_changes_v3() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.apply_integrity_threshold_v3() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.assign_match_verification_mode_v3() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.monitor_confirmed_match_integrity_v3() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.check_daily_match_limit(UUID,UUID) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_review_integrity_flag_v3(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_review_integrity_flag_v3(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.submit_match_report_v2(UUID,UUID,INTEGER,INTEGER) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.submit_match_report_v2(UUID,UUID,INTEGER,INTEGER) TO authenticated;

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.matches;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.challenges;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.rating_events;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.disputes;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.match_cancellation_requests;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.player_integrity;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.integrity_flags;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMIT;
