import type { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Beaver Smash',
    short_name: 'Beaver Smash',
    description: 'A competitive table tennis ranking and match-tracking app for the CCNY Table Tennis Club.',
    start_url: '/',
    scope: '/',
    display: 'standalone',
    background_color: '#F9FAFB',
    theme_color: '#5B21B6',
    categories: ['sports', 'social'],
    icons: [
      {
        src: '/icons/icon-192.png',
        sizes: '192x192',
        type: 'image/png',
        purpose: 'any',
      },
      {
        src: '/icons/icon-512.png',
        sizes: '512x512',
        type: 'image/png',
        purpose: 'any',
      },
      {
        src: '/icons/icon-maskable-512.png',
        sizes: '512x512',
        type: 'image/png',
        purpose: 'maskable',
      },
    ],
    shortcuts: [
      { name: 'Home', short_name: 'Home', url: '/dashboard', icons: [{ src: '/icons/icon-192.png', sizes: '192x192' }] },
      { name: 'Challenge a player', short_name: 'Play', url: '/players', icons: [{ src: '/icons/icon-192.png', sizes: '192x192' }] },
      { name: 'Leaderboard', short_name: 'Ranks', url: '/leaderboard', icons: [{ src: '/icons/icon-192.png', sizes: '192x192' }] },
      { name: 'Casual scorekeeper', short_name: 'Casual', url: '/play/casual', icons: [{ src: '/icons/icon-192.png', sizes: '192x192' }] },
    ],
  };
}
