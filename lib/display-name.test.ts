import { describe, expect, it } from 'vitest';
import { displayNameError, isValidDisplayName, normalizeDisplayName } from './display-name';

describe('Unicode display names', () => {
  it.each(['Almas 🏓', '🔥King', 'Player123', 'A', 'José🔥', 'বাংলা🏓'])(
    'accepts %s because it contains a Unicode letter',
    (name) => expect(isValidDisplayName(name)).toBe(true),
  );

  it.each(['12345', '🔥🏓', '123🔥', '!!!', '   '])(
    'rejects %s because it contains no letter',
    (name) => expect(isValidDisplayName(name)).toBe(false),
  );

  it('normalizes surrounding whitespace and counts emoji as Unicode code points', () => {
    expect(normalizeDisplayName('  José🔥  ')).toBe('José🔥');
    expect(isValidDisplayName(`A${'🔥'.repeat(19)}`)).toBe(true);
    expect(isValidDisplayName(`A${'🔥'.repeat(20)}`)).toBe(false);
    expect(displayNameError('123🔥')).toContain('at least one letter');
  });
});
