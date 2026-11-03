import HomePageClient from './HomePageClient';

export default function Home() {
  // Middleware has already resolved the session and redirected authenticated
  // launches before this public landing page can render.
  return <HomePageClient />;
}
