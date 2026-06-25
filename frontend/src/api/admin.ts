import client from './client';
import { AdminMetricsSchema } from './schemas';
import type { AdminMetrics } from './schemas';

export async function getAdminMetrics(): Promise<AdminMetrics> {
  const response = await client.get('/admin/metrics');
  return AdminMetricsSchema.parse(response.data.metrics);
}
