'use client';

import { usePathname, useSearchParams } from 'next/navigation';
import { useEffect, useState } from 'react';

export default function NavigationFeedback() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const search = searchParams.toString();
  const [navigating, setNavigating] = useState(false);

  useEffect(() => {
    setNavigating(false);
  }, [pathname, search]);

  useEffect(() => {
    const handleClick = (event: MouseEvent) => {
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const target = event.target instanceof Element ? event.target.closest('a') : null;
      if (!(target instanceof HTMLAnchorElement) || target.target || target.download) return;

      const url = new URL(target.href, window.location.href);
      if (url.origin !== window.location.origin) return;
      if (url.pathname === window.location.pathname && url.search === window.location.search) return;

      setNavigating(true);
    };

    document.addEventListener('click', handleClick, true);
    return () => document.removeEventListener('click', handleClick, true);
  }, []);

  useEffect(() => {
    if (!navigating) return;
    const fallback = window.setTimeout(() => setNavigating(false), 4000);
    return () => window.clearTimeout(fallback);
  }, [navigating]);

  return (
    <div aria-hidden="true" className={`navigation-progress-track pointer-events-none fixed inset-x-0 z-[100] h-[2px] overflow-hidden transition-opacity ${navigating ? 'opacity-100' : 'opacity-0'}`}>
      <div className="navigation-progress absolute inset-y-0 rounded-full bg-gradient-to-r from-transparent via-[#60A5FA] to-transparent" />
    </div>
  );
}

