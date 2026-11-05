const url = process.env.PONGO_HOSTED_SUPABASE_URL;
const anonKey = process.env.PONGO_HOSTED_ANON_KEY;
const token = process.env.PONGO_QUEUE_TEST_ACCESS_TOKEN;

if (process.env.PONGO_ALLOW_HOSTED_QUEUE_TEST !== 'YES_USE_DISPOSABLE_USER_ON_EMPTY_QUEUE') {
  throw new Error('Refusing a data-mutating hosted queue test without the explicit safety acknowledgement');
}
if (!url || !anonKey || !token) throw new Error('Set hosted URL, anon key, and a disposable queue-test user access token');
if (/localhost|127\.0\.0\.1/.test(url)) throw new Error('Use the local SQL suite for local testing');

const headers = { apikey: anonKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
const call = async (path, init = {}) => {
  const response = await fetch(`${url}${path}`, { ...init, headers: { ...headers, ...(init.headers || {}) } });
  const text = await response.text();
  let body = text;
  try { body = text ? JSON.parse(text) : null; } catch {}
  if (!response.ok) throw new Error(`${path} returned ${response.status}: ${text}`);
  return body;
};

const user = await call('/auth/v1/user');
const active = await call('/rest/v1/beaver_queue_members?select=user_id,status&status=in.(waiting,called,king,playing)');
if (active.length !== 0) throw new Error('Queue is not empty; refusing to interfere with active players');

const before = await call('/rest/v1/rpc/pongo_queue_maintenance_health_v1', { method: 'POST', body: '{}' });
if (!before?.healthy) throw new Error('Queue maintenance is not healthy before the smoke test');

let joined = false;
try {
  await call('/rest/v1/rpc/beaver_queue_join_v1', { method: 'POST', body: '{}' });
  joined = true;
  console.log('Joined as the only player. No heartbeat or tick will be sent; waiting 75 seconds for database Cron.');
  await new Promise((resolve) => setTimeout(resolve, 75_000));

  const rows = await call(`/rest/v1/beaver_queue_members?select=status,updated_at&user_id=eq.${user.id}`);
  if (rows.length !== 1 || rows[0].status !== 'left') {
    throw new Error(`Cron did not expire the browserless solo player: ${JSON.stringify(rows)}`);
  }
  const after = await call('/rest/v1/rpc/pongo_queue_maintenance_health_v1', { method: 'POST', body: '{}' });
  if (!after?.healthy || after?.overdue_queue_deadline) throw new Error(`Unhealthy scheduler after expiry: ${JSON.stringify(after)}`);
  console.log(JSON.stringify({ browserless_expiry: 'passed', member: rows[0], health: after }, null, 2));
} finally {
  if (joined) {
    try { await call('/rest/v1/rpc/beaver_queue_leave_v1', { method: 'POST', body: '{}' }); } catch {}
  }
}
