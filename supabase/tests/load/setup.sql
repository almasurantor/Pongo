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
DELETE FROM auth.users WHERE email LIKE 'queue-load-%@example.test';

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
SELECT
  ('f9000000-0000-4000-8000-'||lpad(index::text,12,'0'))::UUID,
  'queue-load-'||index||'@example.test',
  jsonb_build_object('display_name','Load Player '||index),
  clock_timestamp(),clock_timestamp()
FROM generate_series(1,100) AS fixture(index);

DROP TABLE IF EXISTS public.queue_load_position_snapshot;
CREATE TABLE public.queue_load_position_snapshot(
  user_id UUID PRIMARY KEY,
  queue_position BIGINT NOT NULL
);
