export const DISPLAY_NAME_MAX_LENGTH = 20;

export function normalizeDisplayName(name: string) {
  return name.trim();
}

export function isValidDisplayName(name: string) {
  const normalized = normalizeDisplayName(name);
  const length = Array.from(normalized).length;
  return length >= 1
    && length <= DISPLAY_NAME_MAX_LENGTH
    && /\p{L}/u.test(normalized);
}

export function displayNameError(name: string) {
  const normalized = normalizeDisplayName(name);
  if (!normalized) return 'Enter a display name.';
  if (Array.from(normalized).length > DISPLAY_NAME_MAX_LENGTH) {
    return `Display name must be ${DISPLAY_NAME_MAX_LENGTH} characters or fewer.`;
  }
  if (!/\p{L}/u.test(normalized)) return 'Display name must include at least one letter.';
  return '';
}
