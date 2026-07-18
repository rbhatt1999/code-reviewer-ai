import { useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { getSubmission, getIssues, getReview, getSubmissionFiles, getFileContent } from '@api/submissions';
import type { Issue } from '@api/schemas';
import { useSubmissionChannel } from '@hooks/useSubmissionChannel';
import { CodeViewer } from './CodeViewer';
import { ReportDownloadButtons } from './ReportDownloadButtons';

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
      className={`text-xs px-2 py-1 rounded font-medium ${colors[status] ?? 'bg-gray-100 text-gray-600'}`}
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

  const { data: files } = useQuery({
    queryKey: ['sourceFiles', submissionId],
    queryFn: () => getSubmissionFiles(submissionId),
    enabled: Boolean(submissionId) && submission?.status === 'completed',
  });

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

  return (
    <div data-testid="submission-detail-page">
      <Link
        to={`/projects/${submission.project_id}`}
        className="text-sm text-indigo-600 hover:underline mb-4 inline-block"
      >
        &larr; Back to project
      </Link>

      <div className="flex items-start justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-800">
            {submission.source_ref ?? 'Submission'}
          </h1>
          <p className="text-gray-400 text-sm mt-1">
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
        <div className="bg-white border border-gray-200 rounded-lg p-5 mb-6" data-testid="review-summary">
          <h2 className="text-base font-semibold text-gray-700 mb-2">Review summary</h2>
          {review.summary && (
            <p className="text-sm text-gray-600 whitespace-pre-wrap">{review.summary}</p>
          )}
          <div className="mt-3 flex flex-wrap gap-4 text-sm">
            <span>
              <span className="text-gray-500">Mode:</span>{' '}
              <span className="font-medium">{review.mode}</span>
            </span>
            <span>
              <span className="text-gray-500">Total issues:</span>{' '}
              <span className="font-medium">{review.total_issues}</span>
            </span>
          </div>
        </div>
      )}

      {submission.status !== 'completed' && submission.status !== 'failed' && (
        <div
          className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6 text-blue-700 text-sm"
          data-testid="submission-in-progress"
        >
          <div className="flex items-center justify-between mb-2">
            <span>
              Review in progress — status: <strong>{submission.status}</strong>
            </span>
            <span className="text-xs text-blue-500" data-testid="submission-progress-pct">
              {live?.progress ?? 0}%
            </span>
          </div>
          <div className="w-full bg-blue-100 rounded-full h-1.5 mb-2 overflow-hidden">
            <div
              className="bg-blue-500 h-1.5 rounded-full transition-all duration-500"
              style={{ width: `${live?.progress ?? 0}%` }}
            />
          </div>
          {live?.message && (
            <p className="text-xs text-blue-600 italic" data-testid="submission-live-message">
              {live.message}
            </p>
          )}
        </div>
      )}

      {submission.status === 'failed' && (
        <div
          className="bg-red-50 border border-red-200 rounded-lg p-4 mb-6 text-red-700 text-sm"
          data-testid="submission-failed"
        >
          Review failed. Please try re-submitting.
        </div>
      )}

      {file && (
        <div data-testid="code-viewer-section" className="mb-6">
          {files && files.length > 1 && (
            <div className="flex gap-2 mb-2 flex-wrap">
              {files.map((f) => (
                <button
                  key={f.path}
                  onClick={() => setActivePath(f.path)}
                  className={`text-xs px-2 py-1 rounded border ${effectivePath === f.path ? 'bg-blue-600 text-white' : 'bg-white text-gray-700'}`}
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

      <h2 className="text-lg font-semibold text-gray-700 mb-3">Issues</h2>

      {issuesLoading && (
        <p className="text-gray-500">Loading issues...</p>
      )}

      {issues && issues.length === 0 && (
        <p className="text-gray-400" data-testid="issues-empty">
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
      <table className="min-w-full bg-white border border-gray-200 rounded-lg text-sm">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-4 py-3 text-left font-medium text-gray-600 w-24">Severity</th>
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
      className="border-t border-gray-100 hover:bg-gray-50"
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
