-- Run only after the mobile-ranking application is deployed and smoke-tested.
BEGIN;

UPDATE public.matches SET status='ready' WHERE status='active';
UPDATE public.matches SET status='result_reported' WHERE status='pending_confirmation';
UPDATE public.matches SET status='correction_proposed' WHERE status='disputed';
UPDATE public.matches SET status='expired' WHERE status='auto_expired';

ALTER TABLE public.matches DROP CONSTRAINT IF EXISTS matches_status_check;
ALTER TABLE public.matches ADD CONSTRAINT matches_status_check CHECK (status IN (
  'ready','result_reported','awaiting_independent_report','correction_proposed','admin_review','confirmed','expired','voided'
));
ALTER TABLE public.matches DROP COLUMN IF EXISTS player_one_submission;
ALTER TABLE public.matches DROP COLUMN IF EXISTS player_two_submission;

DROP FUNCTION IF EXISTS public.confirm_match_result(UUID);
DROP FUNCTION IF EXISTS public.report_match_result(UUID,INTEGER,INTEGER);
DROP FUNCTION IF EXISTS public.dispute_match_result(UUID,TEXT);
DROP FUNCTION IF EXISTS public.update_match_stats(UUID,UUID,UUID,INTEGER,INTEGER,BOOLEAN);
DROP FUNCTION IF EXISTS public.expire_pending_confirmation_matches();
DROP FUNCTION IF EXISTS public.expire_unsubmitted_matches();

DROP POLICY IF EXISTS "Users can update matches they're involved in" ON public.matches;
DROP POLICY IF EXISTS "Users can create matches" ON public.matches;
DROP POLICY IF EXISTS "Users can create active matches" ON public.matches;
DROP POLICY IF EXISTS "Users can create challenges" ON public.challenges;
DROP POLICY IF EXISTS "Users can update own challenges or challenges they're involved in" ON public.challenges;
REVOKE INSERT,UPDATE,DELETE ON public.matches FROM authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.challenges FROM authenticated;

CREATE OR REPLACE VIEW public.match_history WITH (security_invoker=TRUE) AS
SELECT m.id,m.player_one_id,m.player_two_id,m.player_one_score,m.player_two_score,
  m.player_one_elo_change,m.player_two_elo_change,m.confirmed_at,m.created_at,m.winner_id,
  m.source,m.ranked,m.revision
FROM public.matches m WHERE m.status='confirmed';

COMMIT;
