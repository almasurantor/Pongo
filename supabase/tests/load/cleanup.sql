\set ON_ERROR_STOP on

UPDATE public.beaver_queue_table SET
  phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
  game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,
  updated_at=clock_timestamp()
WHERE id=1;
DELETE FROM public.beaver_queue_ranked_requests;
DELETE FROM public.beaver_queue_swap_requests;
DELETE FROM public.beaver_queue_games;
DELETE FROM public.beaver_queue_members;
DROP TABLE IF EXISTS public.queue_load_position_snapshot;
DELETE FROM auth.users WHERE email LIKE 'queue-load-%@example.test';
