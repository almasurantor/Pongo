import { describe, expect, it } from 'vitest';
import { RESULT_POPUP_VISIBLE_MS, rememberResultPopupDismissal, resultPopupStorageKey, wasResultPopupDismissed } from './result-popup';

describe('result popup lifecycle', () => {
  it('keeps the result visible for three seconds', () => {
    expect(RESULT_POPUP_VISIBLE_MS).toBe(3_000);
  });

  it('records dismissal per match', () => {
    const values = new Map<string, string>();
    const storage = {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => { values.set(key, value); },
    };
    expect(wasResultPopupDismissed('match-a', storage)).toBe(false);
    rememberResultPopupDismissal('match-a', storage);
    expect(values.get(resultPopupStorageKey('match-a'))).toBe('1');
    expect(wasResultPopupDismissed('match-a', storage)).toBe(true);
    expect(wasResultPopupDismissed('match-b', storage)).toBe(false);
  });
});
