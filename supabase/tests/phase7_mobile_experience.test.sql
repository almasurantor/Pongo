-- Run only against a disposable Supabase database after all migrations.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
SELECT id,email,jsonb_build_object('display_name',name),NOW(),NOW()
FROM (VALUES
  ('f7000000-0000-0000-0000-000000000001'::UUID,'phase7-a@example.test','Phase Seven A'),
  ('f7000000-0000-0000-0000-000000000002'::UUID,'phase7-b@example.test','Phase Seven B')
) fixtures(id,email,name);

SELECT public.emit_domain_event(
  'challenge.received',
  'f7000000-0000-0000-0000-000000000002',
  NULL,
  NULL,
  '{}'::JSONB,
  ARRAY['f7000000-0000-0000-0000-000000000001'::UUID]
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000002',TRUE);
SELECT pg_temp.assert_true((SELECT COUNT(*)=0 FROM public.domain_events),'users must not read another player''s domain events');
SELECT set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000001',TRUE);
SELECT pg_temp.assert_true((SELECT COUNT(*)=1 FROM public.domain_events),'recipient rows must grant access to the associated domain event');
RESET ROLE;

SELECT pg_temp.assert_true(
  EXISTS(SELECT 1 FROM public.notifications WHERE user_id='f7000000-0000-0000-0000-000000000001'),
  'server-side event emission must retain its internal recipient row'
);

ROLLBACK;
