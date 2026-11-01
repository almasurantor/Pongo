import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

export default async function PlayPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect('/login');

  return (
    <main className="min-h-screen bg-gradient-to-br from-white via-accent-gray-50 to-primary-purple/5 px-4 py-7 sm:py-12">
      <div className="mx-auto max-w-xl">
        <p className="text-sm font-bold uppercase tracking-widest text-primary-purple">Ranked play</p>
        <h1 className="mt-2 text-4xl font-black text-accent-black">Start with a challenge</h1>
        <p className="mt-3 text-accent-gray-600">Choose an opponent and send a challenge. Your ranked match begins only after they accept.</p>
        <div className="mt-8 space-y-4">
          <Link href="/players" className="block rounded-3xl gradient-purple p-7 text-white shadow-xl transition active:scale-[.98]">
            <span className="text-4xl">🎯</span><h2 className="mt-4 text-2xl font-black">Challenge a player</h2>
            <p className="mt-1 text-white/85">Find a club member and invite them to a ranked match.</p>
          </Link>
          <Link href="/dashboard" className="block rounded-3xl border-2 border-primary-purple/20 bg-white p-7 shadow-lg transition active:scale-[.98]">
            <span className="text-4xl">🏓</span><h2 className="mt-4 text-2xl font-black text-accent-black">Open active matches</h2>
            <p className="mt-1 text-accent-gray-600">Submit a score or respond to a cancellation request.</p>
          </Link>
          <Link href="/play/casual" className="block rounded-3xl border-2 border-cyan-200 bg-cyan-50 p-7 shadow-lg transition active:scale-[.98]">
            <span className="text-4xl">🧮</span><h2 className="mt-4 text-2xl font-black text-cyan-950">Casual scorekeeper</h2>
            <p className="mt-1 text-cyan-800">Keep score for a game to 11. No account records, limits, or ELO changes.</p>
          </Link>
        </div>
      </div>
    </main>
  );
}
