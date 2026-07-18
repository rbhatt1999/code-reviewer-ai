import { screen, waitFor, fireEvent } from '@testing-library/react';
import { renderWithProviders } from '@/tests/testUtils';
import { ProjectDetailPage } from './ProjectDetailPage';
import * as projectsApi from '@api/projects';
import * as submissionsApi from '@api/submissions';

jest.mock('@api/projects');
jest.mock('@api/submissions');

const mockedGetProject = projectsApi.getProject as jest.MockedFunction<typeof projectsApi.getProject>;
const mockedRegenerate = projectsApi.regenerateWebhookSecret as jest.MockedFunction<
  typeof projectsApi.regenerateWebhookSecret
>;
const mockedListSubmissions = submissionsApi.listSubmissions as jest.MockedFunction<
  typeof submissionsApi.listSubmissions
>;

const baseProject = {
  id: 1,
  name: 'my-ruby-app',
  description: 'A Ruby application',
  language: 'ruby' as const,
  default_branch: 'main',
  submissions_count: 0,
  created_at: '2024-01-01T00:00:00.000Z',
  updated_at: '2024-01-01T00:00:00.000Z',
};

beforeAll(() => {
  Object.assign(navigator, { clipboard: { writeText: jest.fn().mockResolvedValue(undefined) } });
});

beforeEach(() => {
  mockedListSubmissions.mockResolvedValue([]);
});

function renderPage() {
  return renderWithProviders(<ProjectDetailPage />, {
    initialEntries: ['/projects/1'],
    routePattern: '/projects/:id',
  });
}

describe('ProjectDetailPage — webhook panel', () => {
  it('does not render the webhook panel when the project has no repo_url', async () => {
    mockedGetProject.mockResolvedValue({ ...baseProject, repo_url: null, webhook_secret: null });
    renderPage();

    await waitFor(() => {
      expect(screen.getByTestId('project-detail-page')).toBeInTheDocument();
    });
    expect(screen.queryByTestId('webhook-panel')).not.toBeInTheDocument();
  });

  it('renders the payload URL and prompts to generate a secret when repo_url is set but no secret exists', async () => {
    mockedGetProject.mockResolvedValue({
      ...baseProject,
      repo_url: 'https://github.com/acme/widget',
      webhook_secret: null,
    });
    renderPage();

    await waitFor(() => {
      expect(screen.getByTestId('webhook-panel')).toBeInTheDocument();
    });
    expect(screen.getByTestId('webhook-url-input')).toHaveValue(
      'http://localhost:3000/api/v1/webhooks/github'
    );
    expect(screen.getByTestId('webhook-secret-missing')).toBeInTheDocument();
    expect(screen.getByTestId('webhook-regenerate')).toHaveTextContent('Generate secret');
  });

  it('warns that localhost is unreachable and updates the payload URL when a public base URL is pasted in', async () => {
    mockedGetProject.mockResolvedValue({
      ...baseProject,
      repo_url: 'https://github.com/acme/widget',
      webhook_secret: 'shh-secret-value',
    });
    renderPage();

    await waitFor(() => {
      expect(screen.getByTestId('webhook-base-url-input')).toBeInTheDocument();
    });
    expect(screen.getByTestId('webhook-localhost-warning')).toBeInTheDocument();

    fireEvent.change(screen.getByTestId('webhook-base-url-input'), {
      target: { value: 'https://abcd1234.ngrok-free.app' },
    });

    expect(screen.queryByTestId('webhook-localhost-warning')).not.toBeInTheDocument();
    expect(screen.getByTestId('webhook-url-input')).toHaveValue(
      'https://abcd1234.ngrok-free.app/api/v1/webhooks/github'
    );
  });

  it('masks the secret by default and reveals it on click', async () => {
    mockedGetProject.mockResolvedValue({
      ...baseProject,
      repo_url: 'https://github.com/acme/widget',
      webhook_secret: 'shh-secret-value',
    });
    renderPage();

    await waitFor(() => {
      expect(screen.getByTestId('webhook-secret-input')).toBeInTheDocument();
    });

    const secretInput = screen.getByTestId('webhook-secret-input') as HTMLInputElement;
    expect(secretInput.type).toBe('password');

    fireEvent.click(screen.getByTestId('webhook-secret-reveal'));
    expect(secretInput.type).toBe('text');
  });

  it('copies the secret to the clipboard', async () => {
    mockedGetProject.mockResolvedValue({
      ...baseProject,
      repo_url: 'https://github.com/acme/widget',
      webhook_secret: 'shh-secret-value',
    });
    renderPage();

    await waitFor(() => {
      expect(screen.getByTestId('webhook-secret-copy')).toBeInTheDocument();
    });
    fireEvent.click(screen.getByTestId('webhook-secret-copy'));

    expect(navigator.clipboard.writeText).toHaveBeenCalledWith('shh-secret-value');
    await waitFor(() => {
      expect(screen.getByTestId('webhook-secret-copy')).toHaveTextContent('Copied!');
    });
  });

  it('regenerates the secret without a confirm prompt when none exists yet', async () => {
    mockedGetProject.mockResolvedValue({
      ...baseProject,
      repo_url: 'https://github.com/acme/widget',
      webhook_secret: null,
    });
    mockedRegenerate.mockResolvedValue({
      ...baseProject,
      repo_url: 'https://github.com/acme/widget',
      webhook_secret: 'brand-new-secret',
    });
    renderPage();

    await waitFor(() => {
      expect(screen.getByTestId('webhook-regenerate')).toBeInTheDocument();
    });
    fireEvent.click(screen.getByTestId('webhook-regenerate'));

    await waitFor(() => {
      expect(mockedRegenerate).toHaveBeenCalledWith(1);
    });
  });

  it('asks for confirmation before regenerating an existing secret', async () => {
    const confirmSpy = jest.spyOn(window, 'confirm').mockReturnValue(false);
    mockedGetProject.mockResolvedValue({
      ...baseProject,
      repo_url: 'https://github.com/acme/widget',
      webhook_secret: 'shh-secret-value',
    });
    renderPage();

    await waitFor(() => {
      expect(screen.getByTestId('webhook-regenerate')).toBeInTheDocument();
    });
    fireEvent.click(screen.getByTestId('webhook-regenerate'));

    expect(confirmSpy).toHaveBeenCalled();
    expect(mockedRegenerate).not.toHaveBeenCalled();
    confirmSpy.mockRestore();
  });
});
