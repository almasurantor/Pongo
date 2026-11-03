export const CHUNK_RECOVERY_KEY = 'pongo-chunk-recovery-attempted';

export function isChunkLoadFailure(value: unknown) {
  const message = value instanceof Error
    ? `${value.name} ${value.message}`
    : typeof value === 'string'
      ? value
      : String((value as { message?: unknown } | null)?.message ?? '');
  return /ChunkLoadError|Loading chunk [\w-]+ failed|Failed to fetch dynamically imported module/i.test(message);
}
