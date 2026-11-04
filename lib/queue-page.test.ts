import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const source = readFileSync(resolve(process.cwd(), 'app/queue/QueueClient.tsx'), 'utf8');
const styles = readFileSync(resolve(process.cwd(), 'app/queue/QueueClient.module.css'), 'utf8');

describe('queue page structure', () => {
  it('keeps the prominent waiting list separate from compact recent results', () => {
    expect(source.match(/data-queue-card=/g)).toHaveLength(4);
    expect(source).toContain('data-queue-card="live-table"');
    expect(source).toContain('data-queue-card="current-match"');
    expect(source).toContain('data-queue-card="waiting-list"');
    expect(source).toContain('data-queue-card="recent-results"');
    const cardOrder = [
      'data-queue-card="live-table"',
      'data-queue-card="current-match"',
      'data-queue-card="waiting-list"',
      'data-queue-card="recent-results"',
    ].map((card) => source.indexOf(card));
    expect(cardOrder).toEqual([...cardOrder].sort((a, b) => a - b));
    expect(source).toContain('.limit(10)');
    expect(source).not.toContain('You joined the queue.');
    expect(source).not.toContain('You left the queue.');
    expect(source).not.toContain('styles.statusLabel');
    expect(source).toContain('styles.queuedState');
    expect(source).toContain('styles.playingState');
    expect(source).toContain('In queue · #');
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

  it('keeps the flat Pongo queue color hierarchy in both themes', () => {
    expect(styles).toContain('--queue-blue: #3774ef');
    expect(styles).toContain('--queue-live: #e5ebf5');
    expect(styles).toContain('--queue-live: #151f3c');
    expect(styles).toContain('--queue-live-border: #29469d');
    expect(styles).toContain('--queue-match: #3774ef');
    expect(styles).toContain('--queue-match-status: #2c5fd1');
    expect(styles).toContain('--queue-match-inner: #172747');
    expect(styles).toContain('--queue-support: #e5ebf5');
    expect(styles).toContain('--queue-support: #172747');
    expect(styles).toContain('--queue-support-surface: #f2f5fb');
    expect(styles).toContain('--queue-support-surface: #10203f');
    expect(styles).toContain('--queue-orange: #ff7b1a');
    expect(styles).toContain('--queue-ball: #e38b3e');
    expect(styles).toContain('--queue-stars: #1a1a1a');
    expect(styles).toContain('--queue-win: #2e8b57');
    expect(styles).toContain('--queue-loss: #b5525c');
    expect(source).toContain('styles.matchPlayer');
    expect(source).not.toContain('styles.playerCard');
    expect(source.match(/★★★/g)).toHaveLength(2);
    expect(styles).toContain('border-radius: 999px');
    expect(styles).not.toMatch(/\.currentMatchCard \.avatar[^}]*queue-orange/s);
    expect(styles).not.toContain('linear-gradient');
    expect(styles).not.toContain('radial-gradient');
  });
});
