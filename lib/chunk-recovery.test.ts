import { describe, expect, it } from 'vitest';
import { isChunkLoadFailure } from './chunk-recovery';

describe('stale chunk recovery', () => {
  it('recognizes Next and dynamic import chunk failures', () => {
    expect(isChunkLoadFailure(new Error('Loading chunk 733 failed.'))).toBe(true);
    expect(isChunkLoadFailure('ChunkLoadError: Loading chunk app/match failed')).toBe(true);
    expect(isChunkLoadFailure(new Error('Failed to fetch dynamically imported module'))).toBe(true);
  });

  it('does not reload for unrelated application errors', () => {
    expect(isChunkLoadFailure(new Error('Supabase request failed'))).toBe(false);
  });
});
