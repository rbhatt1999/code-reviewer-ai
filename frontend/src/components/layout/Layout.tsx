import { Link, useNavigate } from 'react-router-dom';
import { useAuthStore } from '@stores/authStore';
import { signOut } from '@api/auth';

interface LayoutProps {
  children: React.ReactNode;
}

export function Layout({ children }: LayoutProps) {
  const { user, clear } = useAuthStore();
  const navigate = useNavigate();

  const handleLogout = async () => {
    try {
      await signOut();
    } catch {
      // ignore network error on sign out — token is already expired or invalid
    } finally {
      clear();
      navigate('/login');
    }
  };

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b border-gray-200 shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            <Link
              to="/projects"
              className="text-lg font-semibold text-indigo-600 hover:text-indigo-800"
            >
              CodeReviewer.AI
            </Link>
            <div className="flex items-center gap-4">
              {user?.role === 'admin' && (
                <Link
                  to="/admin"
                  className="text-sm text-indigo-600 hover:text-indigo-800"
                  data-testid="layout-admin-link"
                >
                  Admin
                </Link>
              )}
              {user && (
                <span className="text-sm text-gray-600" data-testid="layout-user-email">
                  {user.email}
                </span>
              )}
              <button
                onClick={handleLogout}
                className="text-sm text-gray-500 hover:text-gray-700 underline"
                data-testid="layout-logout-button"
              >
                Logout
              </button>
            </div>
          </div>
        </div>
      </header>
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">{children}</main>
    </div>
  );
}
