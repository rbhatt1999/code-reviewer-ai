import { screen } from '@testing-library/react';
import { renderWithProviders } from '@/tests/testUtils';
import { AdminDashboardPage } from './AdminDashboardPage';
import * as adminApi from '@api/admin';

jest.mock('@api/admin');
const mockedGetMetrics = adminApi.getAdminMetrics as jest.MockedFunction<typeof adminApi.getAdminMetrics>;

const mockMetrics = {
  submissions: { total: 5, by_status: { completed: 3, failed: 1 }, completed: 3, failed: 1 },
  issues: { total: 12, by_severity: { high: 4, low: 2 } },
  users: { total: 2, admins: 1 },
  sidekiq: { processed: 10, failed: 1, enqueued: 0, scheduled: 0, retries: 0 },
};

describe('AdminDashboardPage', () => {
  beforeEach(() => {
    mockedGetMetrics.mockResolvedValue(mockMetrics);
  });

  it('renders the dashboard with metrics', async () => {
    renderWithProviders(<AdminDashboardPage />);
    expect(await screen.findByTestId('admin-dashboard')).toBeInTheDocument();
    expect(await screen.findByText('10')).toBeInTheDocument(); // sidekiq.processed
    expect(await screen.findByText('5')).toBeInTheDocument();  // submissions.total
  });
});
