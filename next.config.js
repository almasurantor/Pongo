/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Keep `next dev` artifacts separate from production builds. Running
  // `next build` while the dev server is open otherwise replaces files in
  // `.next`, leaving the browser with chunk URLs that the server can no
  // longer serve.
  distDir: process.env.NODE_ENV === 'development' ? '.next-dev' : '.next',
  async headers() {
    return [
      {
        source: '/sw.js',
        headers: [
          { key: 'Cache-Control', value: 'no-cache, no-store, must-revalidate' },
          { key: 'Service-Worker-Allowed', value: '/' },
        ],
      },
      {
        source: '/manifest.webmanifest',
        headers: [{ key: 'Cache-Control', value: 'no-cache, must-revalidate' }],
      },
      {
        source: '/icons/:path*',
        headers: [{ key: 'Cache-Control', value: 'public, max-age=31536000, immutable' }],
      },
      {
        source: '/pongo.webp',
        headers: [{ key: 'Cache-Control', value: 'public, max-age=86400, stale-while-revalidate=604800' }],
      },
    ]
  },
}

module.exports = nextConfig
