export default function DashboardLoading() {
  return (
    <main className="min-h-screen bg-accent-gray-50 px-4 py-6 sm:py-10" aria-label="Loading dashboard">
      <div className="mx-auto max-w-5xl space-y-6 animate-pulse">
        <div className="h-10 w-48 rounded-xl bg-accent-gray-200" />
        <div className="h-72 rounded-3xl bg-primary-purple/20" />
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="h-32 rounded-2xl bg-white" />
          <div className="h-32 rounded-2xl bg-white" />
        </div>
      </div>
    </main>
  );
}

