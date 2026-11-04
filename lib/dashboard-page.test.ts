import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const source = readFileSync(resolve(process.cwd(), 'app/dashboard/DashboardClient.tsx'), 'utf8');
const rankedModal = readFileSync(resolve(process.cwd(), 'components/RankedDecisionModal.tsx'), 'utf8');

describe('dashboard challenge experience', () => {
  it('shows incoming challenges in a dismissible decision popup and keeps the pending card', () => {
    expect(source).toContain("const popupChallenge = incoming.find");
    expect(source).toContain('<RankedDecisionModal');
    expect(source).toContain('challenger={popupChallenge.challenger}');
    expect(source).toContain('setDismissedChallengeIds');
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

  it('labels the first dashboard card as Pending Matches', () => {
    expect(source).toContain("['Pending Matches', 'Friends', 'Challenges']");
    expect(source).toContain('>Pending Matches</h2>');
    expect(source).toContain('aria-label="Pending matches and requests"');
    expect(source).not.toContain('>Active Matches</h2>');
  });
});
