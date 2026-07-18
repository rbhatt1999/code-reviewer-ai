import { screen, waitFor } from '@testing-library/react';
import { renderWithProviders } from '@/tests/testUtils';
import { ProjectListPage } from './ProjectListPage';
import * as projectsApi from '@api/projects';

jest.mock('@api/projects');
const mockedListProjects = projectsApi.listProjects as jest.MockedFunction<
  typeof projectsApi.listProjects
>;

const mockProjects = [
  {
    id: 1,
    name: 'my-ruby-app',
    description: 'A Ruby application',
    language: 'ruby' as const,
    default_branch: 'main',
    repo_url: null,
    webhook_secret: null,
    submissions_count: 2,
    created_at: '2024-01-01T00:00:00.000Z',
    updated_at: '2024-01-01T00:00:00.000Z',
  },
  {
    id: 2,
    name: 'my-python-app',
    description: null,
    language: 'python' as const,
    default_branch: 'main',
    repo_url: 'https://github.com/user/repo',
    webhook_secret: 'abc123',
    submissions_count: 0,
    created_at: '2024-01-02T00:00:00.000Z',
    updated_at: '2024-01-02T00:00:00.000Z',
  },
];

describe('ProjectListPage', () => {
  beforeEach(() => {
    mockedListProjects.mockResolvedValue(mockProjects);
  });

  it('renders a loading state initially', () => {
    // Delay the mock so we can see the loading state
    mockedListProjects.mockImplementationOnce(
      () => new Promise((resolve) => setTimeout(() => resolve(mockProjects), 500))
    );
    renderWithProviders(<ProjectListPage />);
    expect(screen.getByTestId('project-list-loading')).toBeInTheDocument();
  });

  it('renders a list of projects from the API', async () => {
    renderWithProviders(<ProjectListPage />);

    await waitFor(() => {
      expect(screen.getByTestId('project-list')).toBeInTheDocument();
    });

    expect(screen.getByText('my-ruby-app')).toBeInTheDocument();
    expect(screen.getByText('my-python-app')).toBeInTheDocument();
  });

  it('shows the language badge for each project', async () => {
    renderWithProviders(<ProjectListPage />);

    await waitFor(() => {
      expect(screen.getByText('ruby')).toBeInTheDocument();
    });

    expect(screen.getByText('python')).toBeInTheDocument();
  });

  it('renders a link to create a new project', async () => {
    renderWithProviders(<ProjectListPage />);

    await waitFor(() => {
      expect(screen.getByTestId('project-list-new-button')).toBeInTheDocument();
    });
  });

  it('renders project submission counts', async () => {
    renderWithProviders(<ProjectListPage />);

    await waitFor(() => {
      expect(screen.getByText(/2 submissions/i)).toBeInTheDocument();
    });
  });

  it('shows empty state when no projects exist', async () => {
    mockedListProjects.mockResolvedValueOnce([]);
    renderWithProviders(<ProjectListPage />);

    await waitFor(() => {
      expect(screen.getByTestId('project-list-empty')).toBeInTheDocument();
    });
  });
});
