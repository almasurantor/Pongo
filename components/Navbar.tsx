'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { useEffect, useMemo, useRef, useState } from 'react';
import PongoWordmark from './PongoWordmark';
import PongoLogo from './PongoLogo';
import { isActiveQueueStatus, isQueueBackendHealthy, isRetryableQueueError, shouldSendQueueHeartbeat, type QueueSyncTrigger } from '@/lib/queue-client';

const icons: Record<string, React.ReactNode> = {
  home: <path d="M3 10.5 12 3l9 7.5V21a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1V10.5Z" />,
  leaderboard: <path d="M4 20V10h4v10H4Zm6 0V4h4v16h-4Zm6 0v-7h4v7h-4Z" />,
  play: <path d="m9 7 8 5-8 5V7Z" />,
  queue: <><path d="M5 6h14M5 12h14M5 18h9" /><circle cx="3" cy="6" r=".6" fill="currentColor" stroke="none" /><circle cx="3" cy="12" r=".6" fill="currentColor" stroke="none" /><circle cx="3" cy="18" r=".6" fill="currentColor" stroke="none" /></>,
  profile: <><circle cx="12" cy="8" r="4" /><path d="M4 22a8 8 0 0 1 16 0" /></>,
};

function NavIcon({ name, className = 'h-6 w-6' }: { name: string; className?: string }) {
  return <svg aria-hidden="true" viewBox="0 0 24 24" className={className} fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">{icons[name]}</svg>;
}

export default function Navbar() {
  const pathname = usePathname();
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [userId, setUserId] = useState<string | null>(null);
  const [queueCalled, setQueueCalled] = useState(false);
  const heartbeatFailures = useRef(0);

  useEffect(() => {
    let mounted = true;
    supabase.auth.getSession().then(({ data }) => {
      if (mounted) setUserId(data.session?.user.id ?? null);
    });
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      if (mounted) setUserId(session?.user.id ?? null);
    });
    return () => { mounted = false; subscription.unsubscribe(); };
  }, [supabase]);

  useEffect(() => {
    if (!userId) {
      setQueueCalled(false);
      return;
    }
    let backendReady = false;
    const syncQueue = async (trigger: QueueSyncTrigger) => {
      const memberResponse = await supabase.from('beaver_queue_members').select('status').eq('user_id', userId).maybeSingle();
      const status = memberResponse.data?.status ?? null;
      setQueueCalled(status === 'called');
      if (!isActiveQueueStatus(status)) heartbeatFailures.current = 0;
      if (backendReady && !pathname.startsWith('/queue') && shouldSendQueueHeartbeat(status, trigger, heartbeatFailures.current)) {
        const heartbeat = await supabase.rpc('beaver_queue_heartbeat_v1');
        if (heartbeat.error) {
          heartbeatFailures.current = isRetryableQueueError(heartbeat.error)
            ? heartbeatFailures.current + 1
            : 3;
        } else {
          heartbeatFailures.current = 0;
        }
      }
    };
    const start = async () => {
      const health = await supabase.rpc('beaver_queue_health_v5');
      backendReady = !health.error && isQueueBackendHealthy(health.data);
      await syncQueue('initial');
    };
    void start();
    const heartbeat = window.setInterval(() => void syncQueue('interval'), 30_000);
    const focus = () => void syncQueue('focus');
    window.addEventListener('focus', focus);
    const channel = supabase.channel(`queue-nav-${userId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_members', filter: `user_id=eq.${userId}` }, () => void syncQueue('realtime'))
      .subscribe();
    return () => {
      window.clearInterval(heartbeat);
      window.removeEventListener('focus', focus);
      void supabase.removeChannel(channel);
    };
  }, [pathname, supabase, userId]);

  const profileHref = userId ? `/profile/${userId}` : '/dashboard';
  const items = [
    { href: '/dashboard', label: 'Home', icon: 'home' },
    { href: '/leaderboard', label: 'Leaderboard', icon: 'leaderboard' },
    { href: '/play', label: 'Play', icon: 'play', primary: true },
    { href: '/queue', label: 'Queue', icon: 'queue' },
    { href: profileHref, label: 'Profile', icon: 'profile' },
  ];
  const active = (href: string) => href === '/dashboard' ? pathname === href : pathname.startsWith(href);

  return (
    <>
      <nav className="glass-effect sticky top-0 z-40 hidden border-b border-accent-gray-200 sm:block">
        <div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-6">
          <Link href="/dashboard" className="flex items-center gap-2 rounded-xl pr-2 text-xl transition active:scale-[0.98]" aria-label="Pongo home">
            <PongoLogo size="sm" priority />
            <PongoWordmark />
          </Link>
          <div className="flex items-center gap-5 lg:gap-7">
            {items.map((item) => <Link key={item.label} href={item.href}
              className={`text-sm font-bold transition ${active(item.href) ? 'text-primary-purple' : 'text-accent-gray-600 hover:text-primary-purple'} ${item.primary ? 'rounded-full bg-brand-orange px-5 py-2.5 text-white hover:bg-brand-orangeDark hover:text-white' : ''}`}>
              {item.label}
            </Link>)}
          </div>
        </div>
      </nav>
      <nav aria-label="Primary" className="mobile-bottom-nav fixed inset-x-0 z-50 px-2 sm:hidden">
        <div className="mobile-nav-island mx-auto grid max-w-md grid-cols-5 items-center">
          {items.map((item) => {
            const isActive = active(item.href);
            return (
              <Link
                key={item.label}
                href={item.href}
                aria-label={item.label}
                aria-current={isActive ? 'page' : undefined}
                onClick={(event) => {
                  if (event.detail > 0) event.currentTarget.blur();
                  if (item.href === '/dashboard' && pathname === '/dashboard') {
                    event.preventDefault();
                    router.refresh();
                  }
                }}
                className={`mobile-nav-item relative mx-auto flex items-center justify-center focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#2563EB] dark:focus-visible:outline-[#60A5FA] ${item.primary ? 'mobile-nav-play text-white' : isActive ? 'mobile-nav-active text-[#2563EB] dark:text-[#93C5FD]' : 'text-accent-gray-500 dark:text-accent-gray-300'}`}
              >
                <NavIcon name={item.icon} className={item.primary ? 'h-[1.35rem] w-[1.35rem]' : 'h-5 w-5'} />
                {item.label === 'Queue' && queueCalled && (
                  <span aria-hidden="true" className="absolute right-1.5 top-1.5 h-3 w-3 rounded-full border-2 border-white bg-[#F97316] dark:border-[#0B1120]" />
                )}
                <span className="sr-only">{item.label}</span>
              </Link>
            );
          })}
        </div>
      </nav>
    </>
  );
}
