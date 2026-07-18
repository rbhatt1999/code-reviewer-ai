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
    <div className="app-shell">
      <header className="app-header">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="flex h-16 items-center justify-between gap-4">
            <Link
              to="/projects"
              className="flex items-center gap-2 text-[15px] font-semibold tracking-tight text-zinc-950"
            >
              <span className="grid h-7 w-7 place-items-center rounded-md bg-zinc-950 text-xs font-bold text-white">CR</span>
              CodeReviewer<span className="text-blue-600">.AI</span>
            </Link>
            <nav className="flex items-center gap-2">
              <Link to="/projects" className="hidden rounded-md px-3 py-1.5 text-sm font-medium text-zinc-600 hover:bg-zinc-100 hover:text-zinc-950 sm:block">Projects</Link>
              {user?.role === 'admin' && (
                <Link
                  to="/admin"
                  className="rounded-md px-3 py-1.5 text-sm font-medium text-zinc-600 hover:bg-zinc-100 hover:text-zinc-950"
                  data-testid="layout-admin-link"
                >
                  Admin
                </Link>
              )}
              {user && (
                <span className="hidden rounded-md border border-zinc-200 bg-zinc-50 px-2.5 py-1 text-xs text-zinc-600 md:block" data-testid="layout-user-email">
                  {user.email}
                </span>
              )}
              <button
                onClick={handleLogout}
                className="rounded-md px-2.5 py-1.5 text-sm font-medium text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900"
                data-testid="layout-logout-button"
              >
                Logout
              </button>
            </nav>
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">{children}</main>
    </div>
  );
}
