import { screen } from '@testing-library/react';
import { renderWithProviders } from '@/tests/testUtils';
import { ProtectedRoute } from './ProtectedRoute';
import { useAuthStore } from '@stores/authStore';

// Helper to set auth store state directly
function setAuthState(token: string | null, role?: 'reviewer' | 'admin') {
  useAuthStore.setState({
    token,
    user: token && role ? { id: 1, email: 'test@test.com', name: 'Test', role } : null,
  });
}

describe('ProtectedRoute', () => {
  afterEach(() => {
    useAuthStore.setState({ token: null, user: null });
  });

  it('redirects to /login when no token', () => {
    setAuthState(null);
    renderWithProviders(<ProtectedRoute><div>content</div></ProtectedRoute>);
    // Navigate renders nothing for the content; the redirect should suppress it
    expect(screen.queryByText('content')).not.toBeInTheDocument();
  });

  it('renders children when token is set (non-admin route)', () => {
    setAuthState('tok123', 'reviewer');
    renderWithProviders(<ProtectedRoute><div>content</div></ProtectedRoute>);
    expect(screen.getByText('content')).toBeInTheDocument();
  });

  it('renders children for adminOnly when user is admin', () => {
    setAuthState('tok123', 'admin');
    renderWithProviders(<ProtectedRoute adminOnly><div>admin content</div></ProtectedRoute>);
    expect(screen.getByText('admin content')).toBeInTheDocument();
  });

  it('redirects to / for adminOnly when user is reviewer', () => {
    setAuthState('tok123', 'reviewer');
    renderWithProviders(<ProtectedRoute adminOnly><div>admin content</div></ProtectedRoute>);
    expect(screen.queryByText('admin content')).not.toBeInTheDocument();
  });

  it('redirects to / for adminOnly when user is null (token + no user)', () => {
    // Simulate abnormal state: token present but user null
    useAuthStore.setState({ token: 'tok123', user: null });
    renderWithProviders(<ProtectedRoute adminOnly><div>admin content</div></ProtectedRoute>);
    expect(screen.queryByText('admin content')).not.toBeInTheDocument();
  });
});
