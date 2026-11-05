import type { MetadataRoute } from 'next';
import { getSiteUrl } from '@/lib/site-url';

export default function robots(): MetadataRoute.Robots {
  const siteUrl = getSiteUrl();

  return {
    rules: {
      userAgent: '*',
      allow: ['/', '/landing'],
      disallow: [
        '/admin',
        '/api/',
        '/dashboard',
        '/leaderboard',
        '/match/',
        '/play',
        '/players',
        '/profile/',
        '/queue',
        '/weekly',
      ],
    },
    sitemap: new URL('/sitemap.xml', siteUrl).toString(),
    host: siteUrl.origin,
  };
}
