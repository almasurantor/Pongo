import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const source = readFileSync(resolve(process.cwd(), 'app/queue/QueueClient.tsx'), 'utf8');

describe('queue page structure', () => {
  it('renders exactly the three requested principal cards', () => {
    expect(source.match(/data-queue-card=/g)).toHaveLength(3);
    expect(source).toContain('data-queue-card="live-table"');
    expect(source).toContain('data-queue-card="current-match"');
    expect(source).toContain('data-queue-card="queue-activity"');
  });

  it('uses outcome actions without numerical score inputs or a check-in overlay', () => {
    expect(source).toContain('I Won');
    expect(source).toContain('I Lost');
    expect(source).not.toContain('type="number"');
    expect(source).not.toContain('turnOverlay');
  });
});
