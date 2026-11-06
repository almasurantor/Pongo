'use client';

import { useEffect } from 'react';
import RecoveryScreen from '@/components/RecoveryScreen';

export default function AppError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return <RecoveryScreen reset={reset} />;
}
