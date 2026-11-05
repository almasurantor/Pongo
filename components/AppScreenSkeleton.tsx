export default function AppScreenSkeleton({ titleWidth = 'w-40', rows = 3 }: { titleWidth?: string; rows?: number }) {
  return (
    <main className="app-screen min-h-screen bg-accent-gray-50 px-4 py-7" aria-label="Loading page">
      <div className="app-screen-shell mx-auto w-full max-w-4xl animate-pulse">
        <div className={`screen-fixed h-10 ${titleWidth} rounded-xl bg-accent-gray-200 dark:bg-accent-gray-700`} />
        <div className="screen-flex space-y-3 sm:mt-6">
          {Array.from({ length: rows }, (_, index) => (
            <div key={index} className="h-28 rounded-3xl border border-accent-gray-200 bg-white dark:border-accent-gray-700 dark:bg-accent-gray-800" />
          ))}
        </div>
      </div>
    </main>
  );
}
