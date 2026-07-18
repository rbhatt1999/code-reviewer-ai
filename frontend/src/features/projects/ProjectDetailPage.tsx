import { useState } from 'react';
import { Link, useParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getProject, deleteProject, regenerateWebhookSecret } from '@api/projects';
import { listSubmissions } from '@api/submissions';
import type { Project } from '@api/schemas';

// The webhook endpoint is a single shared route — GitHub's payload is matched back
// to a project by repo_url + HMAC signature, not by a per-project URL segment.
const WEBHOOK_PATH = '/api/v1/webhooks/github';

// VITE_API_BASE_URL is host-oriented (e.g. http://localhost:3000/api/v1) and
// is NOT reachable from GitHub's servers — it only resolves on this machine.
// Strip the /api/v1 suffix to get a plain origin the user can swap for a
// public tunnel URL (ngrok, Cloudflare Tunnel, etc.) during a live demo.
const DEFAULT_BASE_URL = (import.meta.env.VITE_API_BASE_URL as string)
  .replace(/\/api\/v1\/?$/, '')
  .replace(/\/$/, '');

export function ProjectDetailPage() {
  const { id } = useParams<{ id: string }>();
  const projectId = Number(id);
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const { data: project, isLoading: projectLoading } = useQuery({
    queryKey: ['project', projectId],
    queryFn: () => getProject(projectId),
    enabled: Boolean(projectId),
  });

  const { data: submissions, isLoading: submissionsLoading } = useQuery({
    queryKey: ['submissions', projectId],
    queryFn: () => listSubmissions(projectId),
    enabled: Boolean(projectId),
  });

  const deleteMutation = useMutation({
    mutationFn: () => deleteProject(projectId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['projects'] });
      navigate('/projects');
    },
  });

  const regenerateMutation = useMutation({
    mutationFn: () => regenerateWebhookSecret(projectId),
    onSuccess: (updated) => {
      queryClient.setQueryData(['project', projectId], updated);
    },
  });

  const handleDelete = () => {
    if (window.confirm('Delete this project and all its submissions?')) {
      deleteMutation.mutate();
    }
  };

  if (projectLoading) {
    return <p className="text-gray-500">Loading project...</p>;
  }

  if (!project) {
    return <p className="text-red-600">Project not found.</p>;
  }

  return (
    <div data-testid="project-detail-page">
      <div className="flex items-start justify-between mb-6">
        <div>
          <Link to="/projects" className="text-sm text-indigo-600 hover:underline mb-2 inline-block">
            &larr; Back to projects
          </Link>
          <h1 className="text-2xl font-bold text-gray-800">{project.name}</h1>
          {project.description && (
            <p className="text-gray-500 mt-1">{project.description}</p>
          )}
        </div>
        <div className="flex gap-2">
          <Link
            to={`/projects/${projectId}/submissions/new`}
            className="bg-indigo-600 text-white px-4 py-2 rounded text-sm font-medium hover:bg-indigo-700"
            data-testid="project-detail-new-submission"
          >
            New submission
          </Link>
          <button
            onClick={handleDelete}
            disabled={deleteMutation.isPending}
            className="border border-red-300 text-red-600 px-4 py-2 rounded text-sm font-medium hover:bg-red-50 disabled:opacity-50"
            data-testid="project-detail-delete"
          >
            Delete
          </button>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg p-4 mb-6 text-sm text-gray-600 grid grid-cols-2 gap-4">
        <div>
          <span className="font-medium text-gray-700">Language:</span>{' '}
          <span className="font-mono">{project.language}</span>
        </div>
        <div>
          <span className="font-medium text-gray-700">Default branch:</span>{' '}
          <span className="font-mono">{project.default_branch}</span>
        </div>
        {project.repo_url && (
          <div className="col-span-2">
            <span className="font-medium text-gray-700">Repo URL:</span>{' '}
            <a href={project.repo_url} className="text-indigo-600 hover:underline break-all">
              {project.repo_url}
            </a>
          </div>
        )}
      </div>

      {project.repo_url && (
        <WebhookPanel
          project={project}
          onRegenerate={() => regenerateMutation.mutate()}
          isRegenerating={regenerateMutation.isPending}
        />
      )}

      <h2 className="text-lg font-semibold text-gray-700 mb-3">Submissions</h2>

      {submissionsLoading && (
        <p className="text-gray-500" data-testid="submissions-loading">
          Loading submissions...
        </p>
      )}

      {submissions && submissions.length === 0 && (
        <div className="text-center py-10 text-gray-400" data-testid="submissions-empty">
          <p>No submissions yet.</p>
          <Link
            to={`/projects/${projectId}/submissions/new`}
            className="text-indigo-600 hover:underline mt-1 inline-block"
          >
            Upload your first file
          </Link>
        </div>
      )}

      {submissions && submissions.length > 0 && (
        <ul className="space-y-2" data-testid="submissions-list">
          {submissions.map((sub) => (
            <li
              key={sub.id}
              className="bg-white border border-gray-200 rounded-lg p-4 hover:shadow-sm transition-shadow"
              data-testid={`submission-item-${sub.id}`}
            >
              <Link to={`/submissions/${sub.id}`} className="block">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium text-gray-800">
                    {sub.source_ref ?? 'paste'}
                  </span>
                  <StatusBadge status={sub.status} />
                </div>
                <div className="text-xs text-gray-400 mt-1">
                  {sub.issues_count} issue{sub.issues_count !== 1 ? 's' : ''} &middot;{' '}
                  {(sub.size_bytes / 1024).toFixed(1)} KB &middot;{' '}
                  {new Date(sub.created_at).toLocaleDateString()}
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

interface WebhookPanelProps {
  project: Project;
  onRegenerate: () => void;
  isRegenerating: boolean;
}

function WebhookPanel({ project, onRegenerate, isRegenerating }: WebhookPanelProps) {
  const [revealed, setRevealed] = useState(false);
  const [copied, setCopied] = useState<'url' | 'secret' | null>(null);
  const [baseUrl, setBaseUrl] = useState(DEFAULT_BASE_URL);

  const secret = project.webhook_secret;
  const isLocalhost = /^https?:\/\/(localhost|127\.0\.0\.1)/.test(baseUrl);
  const payloadUrl = `${baseUrl.replace(/\/$/, '')}${WEBHOOK_PATH}`;

  const copy = async (text: string, which: 'url' | 'secret') => {
    await navigator.clipboard.writeText(text);
    setCopied(which);
    setTimeout(() => setCopied(null), 1500);
  };

  const handleRegenerate = () => {
    if (
      !secret ||
      window.confirm('Regenerating will invalidate the current secret — update it on GitHub too. Continue?')
    ) {
      onRegenerate();
    }
  };

  return (
    <div
      className="bg-white border border-gray-200 rounded-lg p-4 mb-6 text-sm"
      data-testid="webhook-panel"
    >
      <h2 className="text-sm font-semibold text-gray-700 mb-2">GitHub webhook (auto PR review)</h2>
      <p className="text-gray-500 text-xs mb-3">
        In your repo, go to Settings &rarr; Webhooks &rarr; Add webhook. Set Content type to{' '}
        <code className="bg-gray-100 px-1 rounded">application/json</code> and trigger on{' '}
        <strong>Pull requests</strong> only.
      </p>

      <div className="mb-3">
        <label className="block text-xs font-medium text-gray-600 mb-1">
          Public base URL
        </label>
        <input
          value={baseUrl}
          onChange={(e) => setBaseUrl(e.target.value)}
          placeholder="https://abcd1234.ngrok-free.app"
          className="w-full border border-gray-300 rounded px-2 py-1 font-mono text-xs"
          data-testid="webhook-base-url-input"
        />
        {isLocalhost && (
          <p className="text-xs text-amber-600 mt-1" data-testid="webhook-localhost-warning">
            GitHub's servers can't reach localhost. Run a tunnel (e.g.{' '}
            <code className="bg-gray-100 px-1 rounded">docker compose --profile demo up</code>{' '}
            for the bundled ngrok service) and paste the public URL here — see the README.
          </p>
        )}
      </div>

      <div className="mb-3">
        <label className="block text-xs font-medium text-gray-600 mb-1">Payload URL</label>
        <div className="flex gap-2">
          <input
            readOnly
            value={payloadUrl}
            className="flex-1 border border-gray-300 rounded px-2 py-1 font-mono text-xs bg-gray-50"
            data-testid="webhook-url-input"
          />
          <button
            type="button"
            onClick={() => copy(payloadUrl, 'url')}
            className="border border-gray-300 rounded px-2 py-1 text-xs text-gray-600 hover:bg-gray-50"
            data-testid="webhook-url-copy"
          >
            {copied === 'url' ? 'Copied!' : 'Copy'}
          </button>
        </div>
      </div>

      <div className="mb-3">
        <label className="block text-xs font-medium text-gray-600 mb-1">Secret</label>
        {secret ? (
          <div className="flex gap-2">
            <input
              readOnly
              type={revealed ? 'text' : 'password'}
              value={secret}
              className="flex-1 border border-gray-300 rounded px-2 py-1 font-mono text-xs bg-gray-50"
              data-testid="webhook-secret-input"
            />
            <button
              type="button"
              onClick={() => setRevealed((r) => !r)}
              className="border border-gray-300 rounded px-2 py-1 text-xs text-gray-600 hover:bg-gray-50"
              data-testid="webhook-secret-reveal"
            >
              {revealed ? 'Hide' : 'Show'}
            </button>
            <button
              type="button"
              onClick={() => copy(secret, 'secret')}
              className="border border-gray-300 rounded px-2 py-1 text-xs text-gray-600 hover:bg-gray-50"
              data-testid="webhook-secret-copy"
            >
              {copied === 'secret' ? 'Copied!' : 'Copy'}
            </button>
          </div>
        ) : (
          <p className="text-xs text-amber-600" data-testid="webhook-secret-missing">
            No secret yet — generate one below before configuring the webhook.
          </p>
        )}
      </div>

      <button
        type="button"
        onClick={handleRegenerate}
        disabled={isRegenerating}
        className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded text-xs font-medium hover:bg-gray-50 disabled:opacity-50"
        data-testid="webhook-regenerate"
      >
        {isRegenerating ? 'Generating...' : secret ? 'Regenerate secret' : 'Generate secret'}
      </button>
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
      className={`text-xs px-2 py-1 rounded font-medium ${colors[status] ?? 'bg-gray-100 text-gray-600'}`}
    >
      {status}
    </span>
  );
}
