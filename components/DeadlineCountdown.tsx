'use client';

import { useEffect, useState } from 'react';
import { formatCountdown, remainingMilliseconds } from '@/lib/deadlines';

export default function DeadlineCountdown({ deadline, prefix = 'Time left', className = '' }: { deadline: string; prefix?: string; className?: string }) {
  const [remaining, setRemaining] = useState(() => remainingMilliseconds(deadline));
  useEffect(() => {
    const update = () => setRemaining(remainingMilliseconds(deadline));
    update();
    const interval = setInterval(update, 1000);
    return () => clearInterval(interval);
  }, [deadline]);
  const urgent = remaining > 0 && remaining <= 60 * 60 * 1000;
  return <span className={`${urgent ? 'text-red-600' : ''} ${className}`} aria-live="polite">{prefix}: {formatCountdown(remaining)}</span>;
}
