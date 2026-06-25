import { render, screen, within } from '@testing-library/react';
import { CodeViewer } from './CodeViewer';
import type { Issue } from '@api/schemas';

const mockIssue = (overrides: Partial<Issue> = {}): Issue => ({
  id: 1,
  source: 'linter' as const,
  rule_id: 'Test/Rule',
  severity: 'low' as const,
  category: 'style' as const,
  file_path: 'app.rb',
  line_start: 1,
  line_end: 1,
  message: 'Test message',
  suggestion: null,
  confidence: null,
  ...overrides,
});

describe('CodeViewer', () => {
  it('renders the correct number of line rows', () => {
    render(<CodeViewer content={"a\nb\nc"} issues={[]} />);
    expect(screen.getByTestId('code-line-1')).toBeInTheDocument();
    expect(screen.getByTestId('code-line-2')).toBeInTheDocument();
    expect(screen.getByTestId('code-line-3')).toBeInTheDocument();
  });

  it('renders a line overlay at the correct line', () => {
    const issue = mockIssue({ id: 42, line_start: 2 });
    render(<CodeViewer content={"line one\nline two\nline three"} issues={[issue]} />);

    // Overlay for issue 42 exists
    expect(screen.getByTestId('issue-overlay-42')).toBeInTheDocument();

    // The overlay should be inside the wrapping div of line 2 (its sibling container)
    // Line 1's div should NOT contain the overlay
    const line1Row = screen.getByTestId('code-line-1');
    const line1Container = line1Row.parentElement!;
    expect(within(line1Container).queryByTestId('issue-overlay-42')).not.toBeInTheDocument();

    // Line 2's container should contain the overlay
    const line2Row = screen.getByTestId('code-line-2');
    const line2Container = line2Row.parentElement!;
    expect(within(line2Container).getByTestId('issue-overlay-42')).toBeInTheDocument();
  });

  it('renders multiple issues on the same line', () => {
    const issue1 = mockIssue({ id: 10, line_start: 1 });
    const issue2 = mockIssue({ id: 11, line_start: 1 });
    render(<CodeViewer content="only one line" issues={[issue1, issue2]} />);

    expect(screen.getByTestId('issue-overlay-10')).toBeInTheDocument();
    expect(screen.getByTestId('issue-overlay-11')).toBeInTheDocument();
  });

  it('renders without crashing for empty content', () => {
    expect(() => render(<CodeViewer content="" issues={[]} />)).not.toThrow();
  });

  it('renders the suggestion in italic when present', () => {
    const issue = mockIssue({ id: 5, suggestion: 'Use single quotes instead.' });
    render(<CodeViewer content="foo" issues={[issue]} />);

    const overlay = screen.getByTestId('issue-overlay-5');
    expect(within(overlay).getByText('Use single quotes instead.')).toBeInTheDocument();
  });

  it('renders just code lines with no overlays when there are no issues', () => {
    render(<CodeViewer content={"hello\nworld"} issues={[]} />);

    expect(screen.getByTestId('code-line-1')).toBeInTheDocument();
    expect(screen.getByTestId('code-line-2')).toBeInTheDocument();
    // No overlay elements should be in the document
    expect(document.querySelector('[data-testid^="issue-overlay-"]')).toBeNull();
  });
});
