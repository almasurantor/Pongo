import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const source = readFileSync(resolve(process.cwd(), 'app/queue/QueueClient.tsx'), 'utf8');

describe('queue page structure', () => {
  it('keeps the prominent waiting list separate from compact recent results', () => {
    expect(source.match(/data-queue-card=/g)).toHaveLength(4);
    expect(source).toContain('data-queue-card="live-table"');
    expect(source).toContain('data-queue-card="current-match"');
    expect(source).toContain('data-queue-card="waiting-list"');
    expect(source).toContain('data-queue-card="recent-results"');
    expect(source.indexOf('data-queue-card="waiting-list"')).toBeLessThan(source.indexOf('data-queue-card="current-match"'));
    expect(source).toContain('.limit(10)');
    expect(source).not.toContain('You joined the queue.');
    expect(source).not.toContain('You left the queue.');
  });

  it('uses outcome actions without numerical score inputs or a check-in overlay', () => {
    expect(source).toContain('I Won');
    expect(source).toContain('I Lost');
    expect(source).not.toContain('type="number"');
    expect(source).not.toContain('turnOverlay');
    expect(source).not.toContain('window.confirm');
    expect(source).toContain('Confirm Win');
    expect(source).toContain('Confirm Loss');
    expect(source).toContain('Report AFK');
    expect(source).toContain('Are you here?');
    expect(source).not.toContain('Only match participants can report the result.');
    expect(source).not.toContain('Result submitted.');
  });
});
