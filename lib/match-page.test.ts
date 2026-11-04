import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const source = readFileSync(resolve(process.cwd(), 'app/match/[id]/MatchClient.tsx'), 'utf8');

describe('ranked match score controls', () => {
  it('resets the score defaults when a winner is selected', () => {
    expect(source).toContain('defaultMatchScores(nextWinnerId === currentUserId)');
    expect(source).toContain('onClick={() => chooseWinner(choice.id)}');
    expect(source).toContain('onClick={() => chooseCorrectionWinner(currentUserId)}');
    expect(source).toContain("onClick={() => chooseCorrectionWinner(opponent?.id || '')}");
  });
});
