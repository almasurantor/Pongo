import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

export default async function PlayPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect('/login');

  return (
    <main className="app-screen fixed-list-screen min-h-screen bg-gradient-to-br from-white via-accent-gray-50 to-primary-purple/5 px-4 py-7 sm:py-12">
      <div className="app-screen-shell mx-auto max-w-xl">
        <h1 className="screen-fixed text-4xl font-black text-accent-black">Play</h1>
        <div className="screen-flex grid min-h-0 grid-rows-[1fr_.82fr_1fr] gap-3 sm:mt-8 sm:block sm:space-y-4">
          <Link href="/players" className="flex min-h-0 items-center gap-4 rounded-3xl gradient-purple p-5 text-white shadow-xl transition active:scale-[.98] sm:block sm:p-7">
            <span className="text-4xl">🎯</span><h2 className="text-2xl font-black sm:mt-4">Challenge a player</h2>
          </Link>
          <Link
            href="/queue"
            aria-label="Join table and open the live queue"
            className="flex min-h-0 items-center gap-4 rounded-3xl border-2 border-primary-purple/25 bg-primary-purple/5 p-4 shadow-lg transition hover:border-primary-purple/40 active:scale-[.98] active:shadow-sm sm:block sm:p-6"
          >
            <span className="text-4xl">🏓</span><h2 className="text-2xl font-black text-accent-black sm:mt-3">Join Table &amp; Play</h2>
          </Link>
          <Link href="/play/casual" className="flex min-h-0 items-center gap-4 rounded-3xl border-2 border-cyan-200 bg-cyan-50 p-5 shadow-lg transition active:scale-[.98] sm:block sm:p-7">
            <span className="text-4xl">🧮</span><h2 className="text-2xl font-black text-cyan-950 sm:mt-4">Casual scorekeeper</h2>
          </Link>
        </div>
      </div>
    </main>
  );
}
