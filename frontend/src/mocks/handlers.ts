import { http, HttpResponse } from 'msw';

const BASE = 'http://localhost:3000/api/v1';

const mockUser = { id: 1, email: 'test@example.com', name: 'Test User', role: 'reviewer' };

const mockProjects = [
  {
    id: 1,
    name: 'my-ruby-app',
    description: 'A Ruby application',
    language: 'ruby',
    default_branch: 'main',
    repo_url: null,
    submissions_count: 2,
    created_at: '2024-01-01T00:00:00.000Z',
    updated_at: '2024-01-01T00:00:00.000Z',
  },
  {
    id: 2,
    name: 'my-python-app',
    description: null,
    language: 'python',
    default_branch: 'main',
    repo_url: 'https://github.com/user/repo',
    submissions_count: 0,
    created_at: '2024-01-02T00:00:00.000Z',
    updated_at: '2024-01-02T00:00:00.000Z',
  },
];

const mockSubmission = {
  id: 10,
  project_id: 1,
  kind: 'single_file',
  status: 'completed',
  language: 'ruby',
  size_bytes: 1024,
  source_ref: 'app.rb',
  issues_count: 3,
  finished_at: '2024-01-01T01:00:00.000Z',
  created_at: '2024-01-01T00:00:00.000Z',
};

const mockIssues = [
  {
    id: 1,
    source: 'linter',
    rule_id: 'Style/StringLiterals',
    severity: 'low',
    category: 'style',
    file_path: 'app.rb',
    line_start: 5,
    line_end: 5,
    message: 'Prefer single-quoted strings when you don\'t need string interpolation.',
    suggestion: null,
    confidence: null,
  },
  {
    id: 2,
    source: 'linter',
    rule_id: 'Layout/TrailingWhitespace',
    severity: 'info',
    category: 'style',
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
  mode: 'linter_only',
  summary: 'Found 2 style issues in app.rb',
  scores: null,
  total_issues: 2,
};

export const handlers = [
  // Auth
  http.post(`${BASE}/auth/sign_in`, () => {
    return HttpResponse.json({ user: mockUser }, {
      headers: { Authorization: 'Bearer mock-jwt-token' },
    });
  }),

  http.post(`${BASE}/auth`, () => {
    return HttpResponse.json({ user: mockUser }, {
      headers: { Authorization: 'Bearer mock-jwt-token' },
    });
  }),

  http.delete(`${BASE}/auth/sign_out`, () => {
    return new HttpResponse(null, { status: 204 });
  }),

  http.get(`${BASE}/auth/me`, () => {
    return HttpResponse.json({ user: mockUser });
  }),

  // Projects
  http.get(`${BASE}/projects`, () => {
    return HttpResponse.json({ projects: mockProjects });
  }),

  http.get(`${BASE}/projects/:id`, ({ params }) => {
    const project = mockProjects.find((p) => p.id === Number(params.id));
    if (!project) return new HttpResponse(null, { status: 404 });
    return HttpResponse.json({ project });
  }),

  http.post(`${BASE}/projects`, async ({ request }) => {
    const body = await request.json() as { project: Record<string, unknown> };
    const newProject = {
      id: 99,
      name: String(body.project.name ?? 'new-project'),
      description: String(body.project.description ?? ''),
      language: String(body.project.language ?? 'ruby'),
      default_branch: String(body.project.default_branch ?? 'main'),
      repo_url: null,
      submissions_count: 0,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    return HttpResponse.json({ project: newProject }, { status: 201 });
  }),

  http.patch(`${BASE}/projects/:id`, ({ params }) => {
    const project = mockProjects.find((p) => p.id === Number(params.id));
    if (!project) return new HttpResponse(null, { status: 404 });
    return HttpResponse.json({ project });
  }),

  http.delete(`${BASE}/projects/:id`, () => {
    return new HttpResponse(null, { status: 204 });
  }),

  // Submissions
  http.get(`${BASE}/projects/:projectId/submissions`, () => {
    return HttpResponse.json({ submissions: [mockSubmission] });
  }),

  http.post(`${BASE}/projects/:projectId/submissions`, () => {
    return HttpResponse.json({ submission: mockSubmission }, { status: 201 });
  }),

  http.get(`${BASE}/submissions/:id`, () => {
    return HttpResponse.json({ submission: mockSubmission });
  }),

  http.get(`${BASE}/submissions/:id/issues`, () => {
    return HttpResponse.json({ issues: mockIssues });
  }),

  http.get(`${BASE}/submissions/:id/review`, () => {
    return HttpResponse.json({ review: mockReview });
  }),

  http.get(`${BASE}/submissions/:id/files`, () =>
    HttpResponse.json({ files: [{ path: 'app.rb' }] })),

  http.get(`${BASE}/submissions/:id/files/*`, () =>
    HttpResponse.json({ path: 'app.rb', language: 'ruby', content: 'x = "hi"\nputs x\n' })),

  // Admin metrics
  http.get(`${BASE}/admin/metrics`, () =>
    HttpResponse.json({
      metrics: {
        submissions: { total: 5, by_status: { completed: 3, failed: 1 }, completed: 3, failed: 1 },
        issues: { total: 12, by_severity: { high: 4, low: 2 } },
        users: { total: 2, admins: 1 },
        sidekiq: { processed: 10, failed: 1, enqueued: 0, scheduled: 0, retries: 0 },
      },
    })
  ),

  // Report exports
  http.get(`${BASE}/submissions/:id/report.json`, () =>
    HttpResponse.json({ ok: true })
  ),
  http.get(`${BASE}/submissions/:id/report.md`, () =>
    new HttpResponse('# Report', { headers: { 'Content-Type': 'text/markdown' } })
  ),
  http.get(`${BASE}/submissions/:id/report.pdf`, () =>
    new HttpResponse('%PDF-1.4', { headers: { 'Content-Type': 'application/pdf' } })
  ),
];
