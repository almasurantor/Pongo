import { createHmac } from 'node:crypto';
import { performance } from 'node:perf_hooks';

const apiUrl = process.env.API_URL;
const jwtSecret = process.env.JWT_SECRET;
const anonKey = process.env.ANON_KEY;
const clients = 100;
const rounds = 5;

if (!apiUrl || !jwtSecret || !anonKey) {
  throw new Error('API_URL, JWT_SECRET, and ANON_KEY must come from local Supabase status');
}

const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
const tokenFor = (index) => {
  const now = Math.floor(Date.now() / 1000);
  const header = encode({ alg: 'HS256', typ: 'JWT' });
  const payload = encode({
    aud: 'authenticated',
    exp: now + 3600,
    iat: now,
    iss: 'supabase-demo',
    role: 'authenticated',
    sub: `f9000000-0000-4000-8000-${String(index).padStart(12, '0')}`,
  });
  const signature = createHmac('sha256', jwtSecret)
    .update(`${header}.${payload}`)
    .digest('base64url');
  return `${header}.${payload}.${signature}`;
};

const latencies = [];
let failures = 0;

for (let round = 0; round < rounds; round += 1) {
  await Promise.all(Array.from({ length: clients }, async (_, offset) => {
    const started = performance.now();
    const token = tokenFor(offset + 1);
    const response = await fetch(
      `${apiUrl}/rest/v1/beaver_queue_table?select=id,phase,king_id,challenger_id`,
      { headers: { apikey: anonKey, authorization: `Bearer ${token}` } },
    );
    await response.arrayBuffer();
    latencies.push(performance.now() - started);
    if (!response.ok) failures += 1;
  }));
}

latencies.sort((left, right) => left - right);
const percentile = (value) => latencies[Math.min(
  latencies.length - 1,
  Math.ceil(latencies.length * value) - 1,
)];
const average = latencies.reduce((sum, latency) => sum + latency, 0) / latencies.length;

console.log(JSON.stringify({
  requests: latencies.length,
  failures,
  average_ms: Number(average.toFixed(2)),
  p95_ms: Number(percentile(0.95).toFixed(2)),
  p99_ms: Number(percentile(0.99).toFixed(2)),
}));

if (failures > 0) process.exitCode = 1;
