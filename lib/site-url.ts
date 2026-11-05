export const PRODUCTION_SITE_URL = 'https://playpongo.vercel.app';

export function getSiteUrl() {
  const configured = process.env.NEXT_PUBLIC_SITE_URL;
  const vercelHost = process.env.VERCEL_PROJECT_PRODUCTION_URL;
  const candidate = configured || (vercelHost ? `https://${vercelHost}` : undefined);

  if (candidate) {
    try {
      return new URL(candidate);
    } catch {
      // Fall through to the environment-appropriate safe default.
    }
  }

  return new URL(process.env.NODE_ENV === 'production' ? PRODUCTION_SITE_URL : 'http://localhost:3000');
}
