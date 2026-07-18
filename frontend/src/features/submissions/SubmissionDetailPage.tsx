import { useMemo, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { getSubmission, getIssues, getReview, getSubmissionFiles, getFileContent } from '@api/submissions';
import type { Issue, Review, SourceFile, SubmissionActivity } from '@api/schemas';
import { useSubmissionChannel } from '@hooks/useSubmissionChannel';
import { CodeViewer } from './CodeViewer';
import { ReportDownloadButtons } from './ReportDownloadButtons';

// Paths the AI actually looked at: files that seeded the diff-first prompt,
// plus any it explicitly asked to read via the read_file tool. Deliberately
// excludes read_file_error entries — the model asked, but never got content
// back, so there's nothing to show in the code viewer for that path.
function reviewedPaths(review: Review | undefined): Set<string> {
  const paths = new Set<string>();
  for (const entry of review?.review_log ?? []) {
    if ((entry.type === 'diff' || entry.type === 'read_file') && entry.file) {
      paths.add(entry.file);
    }
  }
  return paths;
}

function ActivityTimeline({ activities, active }: { activities: SubmissionActivity[]; active: boolean }) {
  if (activities.length === 0 && !active) return null;
  const currentIndex = active ? activities.length - 1 : -1;

  return (
    <div className="app-panel mb-6 overflow-hidden" data-testid="submission-activity">
      <div className="border-b border-zinc-100 px-5 py-4"><p className="app-kicker">Live pipeline</p><h2 className="mt-1 text-base font-semibold text-zinc-950" data-testid={active ? 'submission-in-progress' : undefined}>Review activity</h2></div>
      <ol className="space-y-2 px-5 py-4">
        {activities.length === 0 && active && (
          <li className="flex items-start gap-3 rounded-lg bg-blue-50 px-3 py-2.5 text-sm" data-testid="activity-current">
            <span className="text-blue-600">●</span>
            <span className="text-gray-700">Review is starting</span>
          </li>
        )}
        {activities.map((entry, index) => (
          <li key={entry.created_at} className={`flex items-start gap-3 rounded-lg px-3 py-2 text-sm ${index === currentIndex ? 'bg-blue-50 text-zinc-950' : 'text-zinc-600'}`} data-testid={index === currentIndex ? 'activity-current' : undefined}>
            <span className={index === currentIndex ? 'text-blue-600' : 'text-emerald-600'}>{index === currentIndex ? '●' : '✓'}</span>
            <span>{entry.message}</span>
          </li>
        ))}
      </ol>
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const colors: Record<string, string> = {
    pending: 'bg-gray-100 text-gray-600',
    ingesting: 'bg-blue-100 text-blue-600',
    analyzing: 'bg-yellow-100 text-yellow-600',
    reviewing: 'bg-orange-100 text-orange-600',
    aggregating: 'bg-purple-100 text-purple-600',
    completed: 'bg-green-100 text-green-700',
    failed: 'bg-red-100 text-red-600',
  };
  return (
    <span
      className={`rounded-md px-2 py-1 text-xs font-medium capitalize ${colors[status] ?? 'bg-gray-100 text-gray-600'}`}
    >
      {status}
    </span>
  );
}

const SEVERITY_COLORS: Record<string, string> = {
  info: 'text-gray-500 bg-gray-100',
  low: 'text-blue-600 bg-blue-50',
  medium: 'text-yellow-700 bg-yellow-50',
  high: 'text-orange-700 bg-orange-50',
  critical: 'text-red-700 bg-red-100',
};

export function SubmissionDetailPage() {
  const { id } = useParams<{ id: string }>();
  const submissionId = Number(id);

  const live = useSubmissionChannel(submissionId);

  const { data: submission, isLoading: subLoading } = useQuery({
    queryKey: ['submission', submissionId],
    queryFn: () => getSubmission(submissionId),
    enabled: Boolean(submissionId),
  });

  const { data: issues, isLoading: issuesLoading } = useQuery({
    queryKey: ['issues', submissionId],
    queryFn: () => getIssues(submissionId),
    enabled: Boolean(submissionId) && submission?.status === 'completed',
  });

  const { data: review } = useQuery({
    queryKey: ['review', submissionId],
    queryFn: () => getReview(submissionId),
    enabled: Boolean(submissionId) && submission?.status === 'completed',
  });

  const { data: allFiles } = useQuery({
    queryKey: ['sourceFiles', submissionId],
    queryFn: () => getSubmissionFiles(submissionId),
    enabled: Boolean(submissionId) && submission?.status === 'completed',
  });

  // Restrict the file tabs to only what the AI actually reviewed (diff files
  // + anything it read via read_file). Falls back to the full repo file list
  // when there's no log yet — older reviews predating this feature, or a
  // linter-only run where the LLM step never ran at all.
  const files = useMemo<SourceFile[] | undefined>(() => {
    if (!allFiles) return allFiles;
    const reviewed = reviewedPaths(review);
    if (reviewed.size === 0) return allFiles;
    const filtered = allFiles.filter((f) => reviewed.has(f.path));
    return filtered.length > 0 ? filtered : allFiles;
  }, [allFiles, review]);

  const [activePath, setActivePath] = useState<string | null>(null);
  const effectivePath = activePath ?? files?.[0]?.path ?? null;

  const { data: file } = useQuery({
    queryKey: ['fileContent', submissionId, effectivePath],
    queryFn: () => getFileContent(submissionId, effectivePath!),
    enabled: Boolean(submissionId) && Boolean(effectivePath),
  });

  if (subLoading) {
    return <p className="text-gray-500">Loading submission...</p>;
  }

  if (!submission) {
    return <p className="text-red-600">Submission not found.</p>;
  }

  const activities = [...submission.activity_log];
  if (live?.activity && !activities.some((entry) => entry.created_at === live.activity?.created_at)) {
    activities.push(live.activity);
  }
  const active = submission.status !== 'completed' && submission.status !== 'failed';

  return (
    <div data-testid="submission-detail-page">
      <Link
        to={`/projects/${submission.project_id}`}
        className="mb-5 inline-block text-sm font-medium text-zinc-500 hover:text-zinc-900"
      >
        &larr; Back to project
      </Link>

      <div className="mb-8 flex items-start justify-between gap-4">
        <div>
          <p className="app-kicker">Submission</p><h1 className="app-page-title mt-1">
            {submission.source_ref ?? 'Submission'}
          </h1>
          <p className="mt-1 text-sm text-zinc-500">
            {submission.language} &middot; {(submission.size_bytes / 1024).toFixed(1)} KB
          </p>
        </div>
        <StatusBadge status={submission.status} />
      </div>

      {submission.status === 'completed' && (
        <div className="mb-6">
          <ReportDownloadButtons submissionId={submission.id} />
        </div>
      )}

      {review && (
        <div className="app-panel mb-6 p-5" data-testid="review-summary">
          <p className="app-kicker">Result</p><h2 className="mt-1 text-base font-semibold text-zinc-950">Review summary</h2>
          {review.summary && (
            <p className="mt-2 whitespace-pre-wrap text-sm leading-6 text-zinc-600">{review.summary}</p>
          )}
          <div className="mt-4 flex flex-wrap gap-2 text-sm">
            <span className="rounded-md bg-zinc-100 px-2.5 py-1 text-zinc-600">
              <span className="text-zinc-500">Mode:</span>{' '}
              <span className="font-medium">{review.mode}</span>
            </span>
            <span className="rounded-md bg-zinc-100 px-2.5 py-1 text-zinc-600">
              <span className="text-zinc-500">Issues:</span>{' '}
              <span className="font-medium">{review.total_issues}</span>
            </span>
          </div>
        </div>
      )}

      <ActivityTimeline activities={activities} active={active} />

      {submission.status === 'failed' && (
        <div
          className="bg-red-50 border border-red-200 rounded-lg p-4 mb-6 text-red-700 text-sm"
          data-testid="submission-failed"
        >
          <p>Review failed. Please try re-submitting.</p>
          {submission.error_message && (
            <p className="mt-2 font-mono text-xs break-all" data-testid="submission-error-message">
              {submission.error_message}
            </p>
          )}
        </div>
      )}

      {file && (
        <div data-testid="code-viewer-section" className="mb-6">
          {files && files.length > 1 && (
            <div className="mb-3 flex flex-wrap gap-2">
              {files.map((f) => (
                <button
                  key={f.path}
                  onClick={() => setActivePath(f.path)}
                  className={`rounded-md border px-2.5 py-1.5 font-mono text-xs ${effectivePath === f.path ? 'border-zinc-900 bg-zinc-900 text-white' : 'border-zinc-200 bg-white text-zinc-600 hover:bg-zinc-50'}`}
                >
                  {f.path}
                </button>
              ))}
            </div>
          )}
          <CodeViewer
            content={file.content}
            issues={(issues ?? []).filter((i) => i.file_path === effectivePath)}
          />
        </div>
      )}

      <div className="mb-3 flex items-center justify-between"><h2 className="text-lg font-semibold tracking-tight text-zinc-950">Issues</h2>{issues && <span className="text-sm text-zinc-500">{issues.length} found</span>}</div>

      {issuesLoading && (
        <p className="text-gray-500">Loading issues...</p>
      )}

      {issues && issues.length === 0 && (
        <p className="empty-state" data-testid="issues-empty">
          No issues found.
        </p>
      )}

      {issues && issues.length > 0 && (
        <IssuesTable issues={issues} />
      )}
    </div>
  );
}

function IssuesTable({ issues }: { issues: Issue[] }) {
  return (
    <div className="overflow-x-auto" data-testid="issues-table">
      <table className="min-w-full overflow-hidden rounded-xl border border-zinc-200 bg-white text-sm">
        <thead className="bg-zinc-50">
          <tr>
            <th className="w-24 px-4 py-3 text-left text-xs font-medium uppercase tracking-[.1em] text-zinc-500">Severity</th>
            <th className="px-4 py-3 text-left font-medium text-gray-600">File</th>
            <th className="px-4 py-3 text-left font-medium text-gray-600 w-16">Line</th>
            <th className="px-4 py-3 text-left font-medium text-gray-600">Rule</th>
            <th className="px-4 py-3 text-left font-medium text-gray-600">Message</th>
          </tr>
        </thead>
        <tbody>
          {issues.map((issue) => (
            <IssueRow key={issue.id} issue={issue} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

function IssueRow({ issue }: { issue: Issue }) {
  return (
    <tr
      className="border-t border-zinc-100 hover:bg-zinc-50/70"
      data-testid={`issue-row-${issue.id}`}
    >
      <td className="px-4 py-3">
        <span
          className={`px-2 py-0.5 rounded text-xs font-medium ${SEVERITY_COLORS[issue.severity] ?? ''}`}
        >
          {issue.severity}
        </span>
      </td>
      <td className="px-4 py-3 font-mono text-xs text-gray-600 max-w-[200px] truncate">
        {issue.file_path}
      </td>
      <td className="px-4 py-3 text-gray-600">{issue.line_start}</td>
      <td className="px-4 py-3 font-mono text-xs text-gray-700 max-w-[180px] truncate">
        {issue.rule_id}
      </td>
      <td className="px-4 py-3 text-gray-700">{issue.message}</td>
    </tr>
  );
}
