import { createBrowserRouter } from 'react-router-dom';
import { Layout } from '@components/layout/Layout';
import { ProtectedRoute } from './ProtectedRoute';
import { LoginPage } from '@features/auth/LoginPage';
import { RegisterPage } from '@features/auth/RegisterPage';
import { ProjectListPage } from '@features/projects/ProjectListPage';
import { ProjectFormPage } from '@features/projects/ProjectFormPage';
import { ProjectDetailPage } from '@features/projects/ProjectDetailPage';
import { NewSubmissionPage } from '@features/submissions/NewSubmissionPage';
import { SubmissionDetailPage } from '@features/submissions/SubmissionDetailPage';
import { AdminDashboardPage } from '@features/admin/AdminDashboardPage';

export const router = createBrowserRouter([
  {
    path: '/login',
    element: <LoginPage />,
  },
  {
    path: '/register',
    element: <RegisterPage />,
  },
  {
    path: '/',
    element: (
      <ProtectedRoute>
        <Layout>
          {/* nested route outlet not needed — Layout wraps children directly */}
          <ProjectListPage />
        </Layout>
      </ProtectedRoute>
    ),
  },
  {
    path: '/projects',
    element: (
      <ProtectedRoute>
        <Layout>
          <ProjectListPage />
        </Layout>
      </ProtectedRoute>
    ),
  },
  {
    path: '/projects/new',
    element: (
      <ProtectedRoute>
        <Layout>
          <ProjectFormPage />
        </Layout>
      </ProtectedRoute>
    ),
  },
  {
    path: '/projects/:id',
    element: (
      <ProtectedRoute>
        <Layout>
          <ProjectDetailPage />
        </Layout>
      </ProtectedRoute>
    ),
  },
  {
    path: '/projects/:id/submissions/new',
    element: (
      <ProtectedRoute>
        <Layout>
          <NewSubmissionPage />
        </Layout>
      </ProtectedRoute>
    ),
  },
  {
    path: '/submissions/:id',
    element: (
      <ProtectedRoute>
        <Layout>
          <SubmissionDetailPage />
        </Layout>
      </ProtectedRoute>
    ),
  },
  {
    path: '/admin',
    element: (
      <ProtectedRoute adminOnly>
        <Layout>
          <AdminDashboardPage />
        </Layout>
      </ProtectedRoute>
    ),
  },
]);
