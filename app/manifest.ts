import type { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Pongo',
    short_name: 'Pongo',
    id: '/',
    description: 'Pongo is the CCNY Table Tennis Club ladder, live queue, and match-day app.',
    // The root performs a server-side session check: returning users reach the
    // dashboard, while signed-out users receive the public landing page.
    start_url: '/',
    scope: '/',
    display: 'standalone',
    background_color: '#2563EB',
    theme_color: '#2563EB',
    categories: ['sports', 'social'],
    icons: [
      {
        src: '/icons/icon-192.png?v=4',
        sizes: '192x192',
        type: 'image/png',
        purpose: 'any',
      },
      {
        src: '/icons/icon-512.png?v=4',
        sizes: '512x512',
        type: 'image/png',
        purpose: 'any',
      },
      {
        src: '/icons/icon-maskable-512.png?v=4',
        sizes: '512x512',
        type: 'image/png',
        purpose: 'maskable',
      },
    ],
    shortcuts: [
      { name: 'Home', short_name: 'Home', url: '/dashboard', icons: [{ src: '/icons/icon-192.png?v=4', sizes: '192x192' }] },
      { name: 'Challenge a player', short_name: 'Play', url: '/players', icons: [{ src: '/icons/icon-192.png?v=4', sizes: '192x192' }] },
      { name: 'Live table queue', short_name: 'Queue', url: '/queue', icons: [{ src: '/icons/icon-192.png?v=4', sizes: '192x192' }] },
      { name: 'Leaderboard', short_name: 'Ranks', url: '/leaderboard', icons: [{ src: '/icons/icon-192.png?v=4', sizes: '192x192' }] },
      { name: 'Casual scorekeeper', short_name: 'Casual', url: '/play/casual', icons: [{ src: '/icons/icon-192.png?v=4', sizes: '192x192' }] },
    ],
  };
}
