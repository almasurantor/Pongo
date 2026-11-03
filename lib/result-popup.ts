export const RESULT_POPUP_VISIBLE_MS = 3_000;
export const RESULT_POPUP_FADE_MS = 240;

export function resultPopupStorageKey(matchId: string) {
  return `pongo-result-popup-dismissed:${matchId}`;
}

export function wasResultPopupDismissed(matchId: string, storage: Pick<Storage, 'getItem'> = sessionStorage) {
  return storage.getItem(resultPopupStorageKey(matchId)) === '1';
}

export function rememberResultPopupDismissal(matchId: string, storage: Pick<Storage, 'setItem'> = sessionStorage) {
  storage.setItem(resultPopupStorageKey(matchId), '1');
}
