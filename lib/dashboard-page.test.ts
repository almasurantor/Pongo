import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const source = readFileSync(resolve(process.cwd(), 'app/dashboard/DashboardClient.tsx'), 'utf8');
const rankedModal = readFileSync(resolve(process.cwd(), 'components/RankedDecisionModal.tsx'), 'utf8');

describe('dashboard challenge experience', () => {
  it('shows incoming challenges in a dismissible decision popup and keeps the pending card', () => {
    expect(source).toContain('incoming.find((challenge) => !dismissedChallengeIds.includes(challenge.id))');
    expect(source).toContain('<RankedDecisionModal');
    expect(source).toContain('challenger={popupChallenge.challenger}');
    expect(source).toContain('rememberDismissedChallenge');
    expect(source).toContain('dismissalsLoaded');
    expect(source).toContain("void respondChallenge(popupChallenge.id, 'decline')");
    expect(source).toContain("void respondChallenge(popupChallenge.id, 'accept')");
    expect(source).toContain('incoming.map((challenge)');
    expect(rankedModal).toContain('aria-label="Dismiss incoming challenge popup"');
    expect(rankedModal).not.toContain('DeadlineCountdown');
    expect(rankedModal).toContain('Incoming challenge');
    expect(rankedModal).toContain('Play a Ranked match?');
    expect(rankedModal).toContain('<RankBadge');
    expect(rankedModal).toContain('bg-[#2e8b57]');
  });

  it('orders dashboard cards as Friends, Pending, then Challenges with count indicators', () => {
    expect(source).toContain("['Friends', 'Pending', 'Challenges']");
    expect(source).toContain('data-dashboard-card="Friends"');
    expect(source).toContain('data-dashboard-card="Pending"');
    expect(source).toContain('data-dashboard-card="Challenges"');
    expect(source).toContain('>Pending</h2>');
    expect(source).toContain('const pendingCount =');
    expect(source).toContain('dashboardCounts[label]');
    expect(source).toContain('pending items`}');
    expect(source).toContain('sent challenges`}');
    expect(source).toContain('aria-label="Pending matches and requests"');
    expect(source).not.toContain('>Active Matches</h2>');
  });
});
