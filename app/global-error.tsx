'use client';

import { useEffect } from 'react';
import RecoveryScreen from '@/components/RecoveryScreen';

export default function GlobalError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <html lang="en">
      <body style={{ margin: 0 }}>
        <RecoveryScreen reset={reset} title="Pongo could not finish opening" />
      </body>
    </html>
  );
}
