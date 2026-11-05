import { createClient } from '@supabase/supabase-js';

const url = process.env.PONGO_HOSTED_SUPABASE_URL;
const anonKey = process.env.PONGO_HOSTED_ANON_KEY;
const tokenA = process.env.PONGO_TEST_ACCESS_TOKEN_A;
const tokenB = process.env.PONGO_TEST_ACCESS_TOKEN_B;

if (!url || !anonKey || !tokenA || !tokenB) {
  throw new Error('Set PONGO_HOSTED_SUPABASE_URL, PONGO_HOSTED_ANON_KEY, and two disposable user access tokens');
}
if (/localhost|127\.0\.0\.1/.test(url)) throw new Error('This script is for a hosted verification target');

const headers = (token) => ({ apikey: anonKey, Authorization: `Bearer ${token}` });
const request = async (path, token, init = {}) => {
  const response = await fetch(`${url}${path}`, {
    ...init,
    headers: { ...headers(token), ...(init.headers || {}) },
  });
  const text = await response.text();
  let body = text;
  try { body = text ? JSON.parse(text) : null; } catch {}
  return { response, body };
};
const assert = (condition, message) => { if (!condition) throw new Error(message); };

const [authA, authB] = await Promise.all([
  request('/auth/v1/user', tokenA),
  request('/auth/v1/user', tokenB),
]);
assert(authA.response.ok && authB.response.ok, 'Both disposable tokens must authenticate');
assert(authA.body.id && authB.body.id && authA.body.id !== authB.body.id, 'Tokens must represent two different users');

const [queueHealth, rankedHealth, privateTable, otherNotifications] = await Promise.all([
  request('/rest/v1/rpc/pongo_queue_maintenance_health_v1', tokenA, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }),
  request('/rest/v1/rpc/pongo_ranked_maintenance_health_v1', tokenA, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }),
  request('/rest/v1/pongo_maintenance_state?select=*', tokenA),
  request(`/rest/v1/notifications?select=id,user_id&user_id=neq.${authA.body.id}`, tokenA),
]);
assert(queueHealth.response.ok && queueHealth.body?.healthy === true, 'Queue scheduler health RPC is not healthy');
assert(rankedHealth.response.ok && rankedHealth.body?.healthy === true, 'Ranked scheduler health RPC is not healthy');
assert(privateTable.response.status === 401 || privateTable.response.status === 403, 'Authenticated clients can read the private maintenance table');
assert(otherNotifications.response.ok && Array.isArray(otherNotifications.body) && otherNotifications.body.length === 0, 'Notification RLS exposed another user row');

const makeRealtimeClient = (token) => {
  const client = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  client.realtime.setAuth(token);
  return client;
};
const realtimeClients = [makeRealtimeClient(tokenA), makeRealtimeClient(tokenB)];
const subscribe = (client, suffix) => new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error(`Realtime subscription ${suffix} timed out`)), 12_000);
  const channel = client.channel(`pongo-readonly-${Date.now()}-${suffix}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_table' }, () => {})
    .subscribe((status) => {
      if (status === 'SUBSCRIBED') { clearTimeout(timer); resolve(channel); }
      if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') { clearTimeout(timer); reject(new Error(`Realtime ${suffix}: ${status}`)); }
    });
});
const channels = await Promise.all(realtimeClients.map((client, index) => subscribe(client, index)));
await Promise.all(channels.map((channel, index) => realtimeClients[index].removeChannel(channel)));

const timings = [];
let failures = 0;
await Promise.all(Array.from({ length: 100 }, async () => {
  const started = performance.now();
  const result = await request('/rest/v1/beaver_queue_table?select=id,phase,updated_at&id=eq.1', tokenA);
  timings.push(performance.now() - started);
  if (!result.response.ok || !Array.isArray(result.body) || result.body.length !== 1) failures += 1;
}));
timings.sort((a, b) => a - b);
assert(failures === 0, `${failures} of 100 concurrent read-only queue requests failed`);

console.log(JSON.stringify({
  authenticated_users: 2,
  rls_checks: 'passed',
  realtime_subscriptions: 2,
  concurrent_reads: 100,
  failures,
  p95_ms: Number(timings[Math.floor(timings.length * 0.95) - 1].toFixed(2)),
  queue_health: queueHealth.body,
  ranked_health: rankedHealth.body,
}, null, 2));
