'use client';

import { useEffect, useState } from 'react';

type NavigatorWithStandalone = Navigator & { standalone?: boolean };

export default function InstallAppHint() {
  const [visible, setVisible] = useState(false);
  const [isIOS, setIsIOS] = useState(false);

  useEffect(() => {
    const standalone = window.matchMedia('(display-mode: standalone)').matches
      || Boolean((navigator as NavigatorWithStandalone).standalone);
    const ios = /iPad|iPhone|iPod/.test(navigator.userAgent)
      || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    setIsIOS(ios);
    setVisible(!standalone && localStorage.getItem('beaver-smash-install-hint-dismissed') !== 'true');
  }, []);

  if (!visible) return null;

  const dismiss = () => {
    localStorage.setItem('beaver-smash-install-hint-dismissed', 'true');
    setVisible(false);
  };

  return (
    <section className="rounded-3xl border-2 border-primary-purple/20 bg-white p-5 shadow-sm" aria-labelledby="install-beaver-smash">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 id="install-beaver-smash" className="text-lg font-black">Install app</h2>
          <p className="mt-1 text-sm text-accent-gray-600">
            {isIOS
              ? 'In Safari, tap Share, then Add to Home Screen.'
              : 'Use your browser menu and choose Install App or Add to Home Screen.'}
          </p>
        </div>
        <button type="button" onClick={dismiss} aria-label="Dismiss install instructions" className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-accent-gray-100 text-xl font-bold text-accent-gray-600">
          ×
        </button>
      </div>
    </section>
  );
}
