import { act, screen, waitFor } from '@testing-library/react';
import { renderWithProviders } from '@/tests/testUtils';
import { SubmissionDetailPage } from './SubmissionDetailPage';
import * as submissionsApi from '@api/submissions';

jest.mock('@api/submissions');
jest.mock('@api/reports');

// ---------------------------------------------------------------------------
// Mock the ActionCable consumer so tests never open a real WebSocket.
// We capture the `received` callback so individual tests can fire it manually.
// ---------------------------------------------------------------------------
type ReceivedFn = (data: Record<string, unknown>) => void;
let capturedReceived: ReceivedFn | null = null;

jest.mock('@cable/consumer', () => ({
  getConsumer: jest.fn(() => ({
    subscriptions: {
      create: jest.fn(
        (_params: unknown, callbacks: { received?: ReceivedFn }) => {
          capturedReceived = callbacks.received ?? null;
          return { unsubscribe: jest.fn() };
        }
      ),
    },
  })),
  teardown: jest.fn(),
}));
const mockedGetSubmission = submissionsApi.getSubmission as jest.MockedFunction<
  typeof submissionsApi.getSubmission
>;
const mockedGetIssues = submissionsApi.getIssues as jest.MockedFunction<
  typeof submissionsApi.getIssues
>;
const mockedGetReview = submissionsApi.getReview as jest.MockedFunction<
  typeof submissionsApi.getReview
>;
const mockedGetSubmissionFiles = submissionsApi.getSubmissionFiles as jest.MockedFunction<
  typeof submissionsApi.getSubmissionFiles
>;
const mockedGetFileContent = submissionsApi.getFileContent as jest.MockedFunction<
  typeof submissionsApi.getFileContent
>;

const mockSubmission = {
  id: 10,
  project_id: 1,
  kind: 'single_file' as const,
  status: 'completed' as const,
  language: 'ruby',
  size_bytes: 1024,
  source_ref: 'app.rb',
  issues_count: 2,
  finished_at: '2024-01-01T01:00:00.000Z',
  created_at: '2024-01-01T00:00:00.000Z',
};

const mockIssues = [
  {
    id: 1,
    source: 'linter' as const,
    rule_id: 'Style/StringLiterals',
    severity: 'low' as const,
    category: 'style' as const,
    file_path: 'app.rb',
    line_start: 5,
    line_end: 5,
    message: 'Prefer single-quoted strings.',
    suggestion: null,
    confidence: null,
  },
  {
    id: 2,
    source: 'linter' as const,
    rule_id: 'Layout/TrailingWhitespace',
    severity: 'info' as const,
    category: 'style' as const,
    file_path: 'app.rb',
    line_start: 10,
    line_end: 10,
    message: 'Trailing whitespace detected.',
    suggestion: null,
    confidence: null,
  },
];

const mockReview = {
  id: 1,
  mode: 'linter_only' as const,
  summary: 'Found 2 style issues in app.rb',
  scores: null,
  total_issues: 2,
  review_log: [],
};

// All tests use route pattern so useParams can extract id
const routeOptions = {
  initialEntries: ['/submissions/10'],
  routePattern: '/submissions/:id',
};

describe('SubmissionDetailPage', () => {
  beforeEach(() => {
    mockedGetSubmission.mockResolvedValue(mockSubmission);
    mockedGetIssues.mockResolvedValue(mockIssues);
    mockedGetReview.mockResolvedValue(mockReview);
    mockedGetSubmissionFiles.mockResolvedValue([{ path: 'app.rb' }]);
    mockedGetFileContent.mockResolvedValue({ path: 'app.rb', language: 'ruby', content: 'puts "hello"\n' });
  });

  it('renders a loading state initially', () => {
    mockedGetSubmission.mockImplementationOnce(
      () => new Promise((resolve) => setTimeout(() => resolve(mockSubmission), 500))
    );
    renderWithProviders(<SubmissionDetailPage />, routeOptions);
    expect(screen.getByText('Loading submission...')).toBeInTheDocument();
  });

  it('renders the submission filename once loaded', async () => {
    renderWithProviders(<SubmissionDetailPage />, routeOptions);

    await waitFor(() => {
      expect(screen.getByTestId('submission-detail-page')).toBeInTheDocument();
    });

    expect(screen.getByText('app.rb')).toBeInTheDocument();
  });

  it('renders the issues table for a completed submission', async () => {
    renderWithProviders(<SubmissionDetailPage />, routeOptions);

    await waitFor(() => {
      expect(screen.getByTestId('issues-table')).toBeInTheDocument();
    });
  });

  it('renders issue rows with severity, file, line, rule, and message', async () => {
    renderWithProviders(<SubmissionDetailPage />, routeOptions);

    await waitFor(() => {
      expect(screen.getByTestId('issue-row-1')).toBeInTheDocument();
    });

    const row = screen.getByTestId('issue-row-1');
    expect(row).toHaveTextContent('low');
    expect(row).toHaveTextContent('app.rb');
    expect(row).toHaveTextContent('5');
    expect(row).toHaveTextContent('Style/StringLiterals');
    expect(row).toHaveTextContent('Prefer single-quoted strings.');
  });

  it('renders the review summary when available', async () => {
    renderWithProviders(<SubmissionDetailPage />, routeOptions);

    await waitFor(() => {
      expect(screen.getByTestId('review-summary')).toBeInTheDocument();
    });

    expect(screen.getByText('Found 2 style issues in app.rb')).toBeInTheDocument();
  });

  it('updates live when the WebSocket fires a completed event', async () => {
    // First render: submission is still analyzing; issues/review queries are gated.
    mockedGetSubmission
      .mockResolvedValueOnce({ ...mockSubmission, status: 'analyzing' as const })
      .mockResolvedValue(mockSubmission); // subsequent refetch returns completed

    renderWithProviders(<SubmissionDetailPage />, routeOptions);

    // Initial in-progress banner should appear (status: analyzing).
    await waitFor(() => {
      expect(screen.getByTestId('submission-in-progress')).toBeInTheDocument();
    });
    expect(screen.queryByTestId('issues-table')).not.toBeInTheDocument();

    // Simulate the ActionCable broadcast for the completed transition.
    await act(async () => {
      capturedReceived?.({
        submission_id: 10,
        status: 'completed',
        issues_count: 2,
      });
    });

    // After invalidation + refetch the issues table should appear.
    await waitFor(() => {
      expect(screen.getByTestId('issues-table')).toBeInTheDocument();
    });
  });

  it('renders the code-viewer-section for a completed submission', async () => {
    renderWithProviders(<SubmissionDetailPage />, routeOptions);

    const section = await screen.findByTestId('code-viewer-section');
    expect(section).toBeInTheDocument();
  });

  it('does not render file-picker buttons when there is only one file', async () => {
    renderWithProviders(<SubmissionDetailPage />, routeOptions);

    const section = await screen.findByTestId('code-viewer-section');
    const buttons = section.querySelectorAll('button');
    expect(buttons).toHaveLength(0);
  });

  it('renders the code content inside the CodeViewer', async () => {
    renderWithProviders(<SubmissionDetailPage />, routeOptions);

    await screen.findByTestId('code-viewer-section');
    expect(screen.getByText('puts "hello"')).toBeInTheDocument();
  });

  it('shows download buttons for a completed submission', async () => {
    renderWithProviders(<SubmissionDetailPage />, routeOptions);

    const jsonBtn = await screen.findByTestId('report-download-json');
    expect(jsonBtn).toBeInTheDocument();
    expect(screen.getByTestId('report-download-md')).toBeInTheDocument();
    expect(screen.getByTestId('report-download-pdf')).toBeInTheDocument();
  });

  it('does not show download buttons for a pending submission', async () => {
    mockedGetSubmission.mockResolvedValue({ ...mockSubmission, status: 'pending' as const });
    renderWithProviders(<SubmissionDetailPage />, routeOptions);

    // Wait for the page to finish loading (the in-progress banner appears for pending)
    await screen.findByTestId('submission-in-progress');
    expect(screen.queryByTestId('report-download-json')).not.toBeInTheDocument();
  });

  it('does not render the review process card when review_log is empty', async () => {
    renderWithProviders(<SubmissionDetailPage />, routeOptions);

    await waitFor(() => {
      expect(screen.getByTestId('review-summary')).toBeInTheDocument();
    });
    expect(screen.queryByTestId('review-process')).not.toBeInTheDocument();
  });

  it('renders the review process steps when review_log has entries', async () => {
    mockedGetReview.mockResolvedValue({
      ...mockReview,
      review_log: [
        { type: 'diff', file: 'app.rb', status: 'modified', additions: 2, deletions: 1 },
        { type: 'read_file', file: 'app/models/user.rb', bytes: 200 },
        { type: 'final_answer', issues_found: 2 },
      ],
    });

    renderWithProviders(<SubmissionDetailPage />, routeOptions);

    const section = await screen.findByTestId('review-process');
    expect(section).toHaveTextContent('Changed in PR: app.rb');
    expect(section).toHaveTextContent('Read for context: app/models/user.rb');
    expect(section).toHaveTextContent('Finished — 2 issue(s) reported');
  });

  it('restricts file tabs to only files the AI reviewed, dropping untouched repo files', async () => {
    mockedGetReview.mockResolvedValue({
      ...mockReview,
      review_log: [
        { type: 'diff', file: 'app.rb', status: 'modified', additions: 2, deletions: 1 },
        { type: 'read_file', file: 'app/models/user.rb', bytes: 200 },
      ],
    });
    mockedGetSubmissionFiles.mockResolvedValue([
      { path: 'app.rb' },
      { path: 'README.md' },
      { path: 'config/routes.rb' },
      { path: 'app/models/user.rb' },
    ]);

    renderWithProviders(<SubmissionDetailPage />, routeOptions);

    const section = await screen.findByTestId('code-viewer-section');
    await waitFor(() => expect(section.querySelectorAll('button')).toHaveLength(2));
    expect(section).toHaveTextContent('app.rb');
    expect(section).toHaveTextContent('app/models/user.rb');
    expect(section).not.toHaveTextContent('README.md');
    expect(section).not.toHaveTextContent('config/routes.rb');
  });
});
