import { randomBytes } from 'node:crypto';
import { spawn } from 'node:child_process';
import { createClient } from '@supabase/supabase-js';

const expectedRef = 'dqkmtbrzhqearrqpmlwd';
const expectedUrl = `https://${expectedRef}.supabase.co`;
const url = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? '').replace(/\/$/, '');
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (process.env.PONGO_ALLOW_HOSTED_RELEASE_TEST !== 'YES_CREATE_AND_DELETE_TWO_TEST_USERS') {
  throw new Error('Set PONGO_ALLOW_HOSTED_RELEASE_TEST=YES_CREATE_AND_DELETE_TWO_TEST_USERS.');
}
if (url !== expectedUrl) throw new Error(`Refusing target ${url || '(missing URL)'}; expected ${expectedUrl}.`);
if (!anonKey || !serviceRoleKey) throw new Error('The hosted anon and service-role keys are required.');

const admin = createClient(url, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const publicClient = () => createClient(url, anonKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const suffix = `${Date.now()}${randomBytes(3).toString('hex')}`;
const password = `Pongo-${randomBytes(24).toString('base64url')}!9a`;
const fixtures = [
  { email: `release-a-${suffix}@pongo.test`, display_name: `ReleaseA${suffix.slice(-5)}` },
  { email: `release-b-${suffix}@pongo.test`, display_name: `ReleaseB${suffix.slice(-5)}` },
];
const created = [];
let cleanupFailed = false;

async function assertMaintenanceHealthy(stage) {
  const [queue, ranked] = await Promise.all([
    admin.rpc('pongo_queue_maintenance_health_v1'),
    admin.rpc('pongo_ranked_maintenance_health_v1'),
  ]);
  if (queue.error || !queue.data?.healthy || queue.data?.overdue_queue_deadline) {
    throw new Error(`Queue maintenance is unhealthy ${stage}: ${queue.error?.message || JSON.stringify(queue.data)}`);
  }
  if (ranked.error || !ranked.data?.healthy) {
    throw new Error(`Ranked maintenance is unhealthy ${stage}: ${ranked.error?.message || JSON.stringify(ranked.data)}`);
  }
  return { queue: queue.data, ranked: ranked.data };
}

const run = (script, extraEnv) => new Promise((resolve, reject) => {
  const child = spawn(process.execPath, [script], {
    stdio: 'inherit',
    env: { ...process.env, ...extraEnv },
  });
  child.on('error', reject);
  child.on('exit', (code) => code === 0 ? resolve() : reject(new Error(`${script} exited ${code}`)));
});

try {
  await assertMaintenanceHealthy('before hosted release verification');

  for (const fixture of fixtures) {
    const { data, error } = await admin.auth.admin.createUser({
      email: fixture.email,
      password,
      email_confirm: true,
      user_metadata: { display_name: fixture.display_name, release_fixture: true },
    });
    if (error || !data.user) throw new Error(`Could not create release fixture: ${error?.message}`);
    created.push({ ...fixture, id: data.user.id });
  }

  const tokens = [];
  for (const fixture of created) {
    const { data, error } = await publicClient().auth.signInWithPassword({
      email: fixture.email,
      password,
    });
    if (error || !data.session?.access_token) throw new Error(`Could not authenticate release fixture: ${error?.message}`);
    tokens.push(data.session.access_token);
  }

  await run('scripts/hosted-readonly-verification.mjs', {
    PONGO_HOSTED_SUPABASE_URL: url,
    PONGO_HOSTED_ANON_KEY: anonKey,
    PONGO_TEST_ACCESS_TOKEN_A: tokens[0],
    PONGO_TEST_ACCESS_TOKEN_B: tokens[1],
  });
  await run('scripts/hosted-queue-expiry-smoke.mjs', {
    PONGO_HOSTED_SUPABASE_URL: url,
    PONGO_HOSTED_ANON_KEY: anonKey,
    PONGO_QUEUE_TEST_ACCESS_TOKEN: tokens[0],
    PONGO_ALLOW_HOSTED_QUEUE_TEST: 'YES_USE_DISPOSABLE_USER_ON_EMPTY_QUEUE',
  });
  const maintenanceHealth = await assertMaintenanceHealthy('after browserless queue expiry');
  console.log(JSON.stringify({ maintenance_health: maintenanceHealth }, null, 2));
} finally {
  if (created.length > 0) {
    const ids = created.map((fixture) => fixture.id);
    const { error: queueError } = await admin.from('beaver_queue_members').delete().in('user_id', ids);
    if (queueError) {
      cleanupFailed = true;
      console.error(`Queue fixture cleanup failed: ${queueError.message}`);
    }
  }
  for (const fixture of created.reverse()) {
    const { error } = await admin.auth.admin.deleteUser(fixture.id, false);
    if (error) {
      cleanupFailed = true;
      console.error(`Auth fixture cleanup failed for ${fixture.id}: ${error.message}`);
    }
  }
}

if (cleanupFailed) throw new Error('Hosted verification passed, but fixture cleanup was incomplete.');
console.log('Hosted Auth/RLS/Realtime/concurrency/closed-browser queue verification passed; fixtures removed.');
