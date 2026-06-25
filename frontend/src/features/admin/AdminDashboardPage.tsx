import { useQuery } from '@tanstack/react-query';
import { getAdminMetrics } from '@api/admin';

export function AdminDashboardPage() {
  const { data: metrics, isLoading, isError } = useQuery({
    queryKey: ['adminMetrics'],
    queryFn: getAdminMetrics,
  });

  if (isLoading) return <div>Loading...</div>;
  if (isError || !metrics) return <div>Error loading metrics.</div>;

  return (
    <div data-testid="admin-dashboard" className="space-y-6">
      <h1 className="text-2xl font-bold text-gray-900">Admin Dashboard</h1>
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
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
    <div className="rounded-lg border border-gray-200 p-4">
      <p className="text-sm text-gray-500">{label}</p>
      <p className="mt-1 text-2xl font-semibold text-gray-900">{value}</p>
    </div>
  );
}
