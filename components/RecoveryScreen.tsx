'use client';

type RecoveryScreenProps = {
  reset?: () => void;
  title?: string;
};

export default function RecoveryScreen({ reset, title = 'Pongo hit a problem' }: RecoveryScreenProps) {
  return (
    <main
      role="alert"
      style={{
        minHeight: '100dvh',
        display: 'grid',
        placeItems: 'center',
        padding: '24px',
        background: '#2563EB',
        color: '#0F172A',
        fontFamily: 'system-ui, -apple-system, sans-serif',
      }}
    >
      <section style={{ width: 'min(100%, 420px)', borderRadius: 28, background: '#FFF', padding: 32, textAlign: 'center', boxShadow: '0 24px 70px rgba(30, 58, 138, 0.5)' }}>
        <p style={{ margin: 0, color: '#2563EB', fontSize: 12, fontWeight: 900, letterSpacing: '.08em', textTransform: 'uppercase' }}>Pongo</p>
        <h1 style={{ margin: '8px 0 0', fontSize: 30 }}>{title}</h1>
        <p style={{ margin: '12px 0 24px', color: '#475569', lineHeight: 1.55 }}>
          Your session has not been cleared. Try this screen again, or reload Pongo if the connection was interrupted.
        </p>
        <div style={{ display: 'grid', gap: 12 }}>
          {reset && <button type="button" onClick={reset} style={{ minHeight: 48, border: 0, borderRadius: 14, background: '#F97316', color: '#FFF', font: 'inherit', fontWeight: 800 }}>Try again</button>}
          <button type="button" onClick={() => window.location.reload()} style={{ minHeight: 48, border: '2px solid #2563EB', borderRadius: 14, background: '#FFF', color: '#1D4ED8', font: 'inherit', fontWeight: 800 }}>Reload Pongo</button>
          {/* A document navigation remains usable when the App Router itself is the failed boundary. */}
          {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
          <a href="/" style={{ padding: 10, color: '#1D4ED8', fontWeight: 800 }}>Open the start page</a>
        </div>
      </section>
    </main>
  );
}
