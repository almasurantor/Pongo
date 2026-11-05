import { describe, expect, it } from 'vitest';
import { readJsonObject } from './api-response';

describe('readJsonObject', () => {
  it('accepts JSON objects', async () => {
    const request = new Request('https://example.test', {
      method: 'POST',
      body: JSON.stringify({ action: 'accept' }),
      headers: { 'content-type': 'application/json' },
    });

    await expect(readJsonObject(request)).resolves.toEqual({ action: 'accept' });
  });

  it('rejects malformed JSON and non-object bodies', async () => {
    const malformed = new Request('https://example.test', { method: 'POST', body: '{' });
    const array = new Request('https://example.test', { method: 'POST', body: '[]' });

    await expect(readJsonObject(malformed)).resolves.toBeNull();
    await expect(readJsonObject(array)).resolves.toBeNull();
  });
});
