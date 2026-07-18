import { useQuery } from '@tanstack/react-query';
import { getAdminMetrics } from '@api/admin';

export function AdminDashboardPage() {
  const { data: metrics, isLoading, isError } = useQuery({
    queryKey: ['adminMetrics'],
    queryFn: getAdminMetrics,
  });

  if (isLoading) return <div className="empty-state">Loading workspace metrics…</div>;
  if (isError || !metrics) return <div className="empty-state text-red-700">Error loading metrics.</div>;

  return (
    <div data-testid="admin-dashboard" className="space-y-6">
      <div><p className="app-kicker">Operations</p><h1 className="app-page-title mt-1">System overview</h1><p className="mt-1 text-sm text-zinc-500">Live review workload and worker health.</p></div>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <MetricCard label="Submissions" value={metrics.submissions.total} />
        <MetricCard label="Issues" value={metrics.issues.total} />
        <MetricCard label="Users" value={metrics.users.total} />
        <MetricCard label="Jobs processed" value={metrics.sidekiq.processed} />
      </div>
    </div>
  );
}

function MetricCard({ label, value }: { label: string; value: number }) {
  return (
    <div className="app-panel p-4 sm:p-5">
      <p className="text-xs font-medium uppercase tracking-[.12em] text-zinc-500">{label}</p>
      <p className="mt-2 text-2xl font-semibold tracking-tight text-zinc-950">{value}</p>
    </div>
  );
}
