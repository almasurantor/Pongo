import type { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Pongo',
    short_name: 'Pongo',
    id: '/',
    description: 'Challenge players, track matches, and climb the table tennis ranks.',
    // The root performs a server-side session check: returning users reach the
    // dashboard, while signed-out users receive the public landing page.
    start_url: '/',
    scope: '/',
    display: 'standalone',
    background_color: '#F8FAFC',
    theme_color: '#2563EB',
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
      { name: 'Live table queue', short_name: 'Queue', url: '/queue', icons: [{ src: '/icons/icon-192.png', sizes: '192x192' }] },
      { name: 'Leaderboard', short_name: 'Ranks', url: '/leaderboard', icons: [{ src: '/icons/icon-192.png', sizes: '192x192' }] },
      { name: 'Casual scorekeeper', short_name: 'Casual', url: '/play/casual', icons: [{ src: '/icons/icon-192.png', sizes: '192x192' }] },
    ],
  };
}
