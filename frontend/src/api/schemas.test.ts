import { UserSchema, ProjectSchema, SubmissionSchema, IssueSchema, ReviewSchema, FileContentSchema, FileListSchema, AdminMetricsSchema } from './schemas';
import { ZodError } from 'zod';

describe('UserSchema', () => {
  it('parses a valid user', () => {
    const result = UserSchema.parse({
      id: 1,
      email: 'test@example.com',
      name: 'Test User',
      role: 'reviewer',
    });
    expect(result.id).toBe(1);
    expect(result.role).toBe('reviewer');
  });

  it('rejects an invalid role', () => {
    expect(() =>
      UserSchema.parse({ id: 1, email: 'x@x.com', name: 'X', role: 'member' })
    ).toThrow(ZodError);
  });

  it('rejects a missing email', () => {
    expect(() =>
      UserSchema.parse({ id: 1, name: 'X', role: 'admin' })
    ).toThrow(ZodError);
  });
});

describe('ProjectSchema', () => {
  const validProject = {
    id: 1,
    name: 'test-project',
    description: null,
    language: 'ruby',
    default_branch: 'main',
    repo_url: null,
    webhook_secret: null,
    submissions_count: 0,
    created_at: '2024-01-01T00:00:00.000Z',
    updated_at: '2024-01-01T00:00:00.000Z',
  };

  it('parses a valid project', () => {
    const result = ProjectSchema.parse(validProject);
    expect(result.language).toBe('ruby');
  });

  it('rejects an unsupported language', () => {
    expect(() =>
      ProjectSchema.parse({ ...validProject, language: 'go' })
    ).toThrow(ZodError);
  });
});

describe('SubmissionSchema', () => {
  const validSubmission = {
    id: 10,
    project_id: 1,
    kind: 'single_file',
    status: 'completed',
    language: 'ruby',
    size_bytes: 2048,
    source_ref: 'app.rb',
    issues_count: 2,
    finished_at: null,
    created_at: '2024-01-01T00:00:00.000Z',
  };

  it('parses a valid submission', () => {
    const result = SubmissionSchema.parse(validSubmission);
    expect(result.kind).toBe('single_file');
    expect(result.status).toBe('completed');
  });

  it('rejects an invalid status', () => {
    expect(() =>
      SubmissionSchema.parse({ ...validSubmission, status: 'running' })
    ).toThrow(ZodError);
  });
});

describe('IssueSchema', () => {
  const validIssue = {
    id: 1,
    source: 'linter',
    rule_id: 'Style/StringLiterals',
    severity: 'low',
    category: 'style',
    file_path: 'app.rb',
    line_start: 5,
    line_end: 5,
    message: 'Prefer single-quoted strings.',
    suggestion: null,
    confidence: null,
  };

  it('parses a valid issue', () => {
    const result = IssueSchema.parse(validIssue);
    expect(result.severity).toBe('low');
    expect(result.source).toBe('linter');
  });

  it('rejects an unknown severity', () => {
    expect(() =>
      IssueSchema.parse({ ...validIssue, severity: 'fatal' })
    ).toThrow(ZodError);
  });

  it('parses a string confidence (real Rails output — BigDecimal serialises as a quoted string)', () => {
    const result = IssueSchema.parse({ ...validIssue, confidence: '0.85' });
    expect(result.confidence).toBe(0.85);
    expect(typeof result.confidence).toBe('number');
  });

  it('parses a numeric confidence unchanged', () => {
    const result = IssueSchema.parse({ ...validIssue, confidence: 0.9 });
    expect(result.confidence).toBe(0.9);
  });

  it('keeps a null confidence as null', () => {
    const result = IssueSchema.parse({ ...validIssue, confidence: null });
    expect(result.confidence).toBeNull();
  });
});

describe('ReviewSchema', () => {
  it('parses a linter_only review', () => {
    const result = ReviewSchema.parse({
      id: 1,
      mode: 'linter_only',
      summary: 'Some issues found.',
      scores: null,
      total_issues: 3,
    });
    expect(result.mode).toBe('linter_only');
  });

  it('parses a hybrid review with per-severity scores', () => {
    const result = ReviewSchema.parse({
      id: 2,
      mode: 'hybrid',
      summary: null,
      scores: { high: 2, low: 1, total: 3 },
      total_issues: 5,
    });
    expect(result.scores?.['high']).toBe(2);
    expect(result.scores?.['total']).toBe(3);
  });

  it('parses a review with null scores', () => {
    const result = ReviewSchema.parse({
      id: 3,
      mode: 'hybrid',
      summary: null,
      scores: null,
      total_issues: 0,
    });
    expect(result.scores).toBeNull();
  });
});

describe('FileContentSchema', () => {
  it('parses a valid file content object', () => {
    const result = FileContentSchema.parse({ path: 'a.rb', content: 'x=1', language: 'ruby' });
    expect(result.path).toBe('a.rb');
    expect(result.language).toBe('ruby');
  });

  it('throws when required fields are missing', () => {
    expect(() => FileContentSchema.parse({ path: 'a.rb' })).toThrow(ZodError);
  });
});

describe('FileListSchema', () => {
  it('parses a valid file list', () => {
    const result = FileListSchema.parse({ files: [{ path: 'a.rb' }] });
    expect(result.files[0].path).toBe('a.rb');
  });
});

describe('AdminMetricsSchema', () => {
  const validMetrics = {
    submissions: {
      total: 5,
      by_status: { completed: 3, failed: 1 },  // string LABEL keys, not integer codes
      completed: 3,
      failed: 1,
    },
    issues: {
      total: 12,
      by_severity: { high: 4, low: 2 },
    },
    users: { total: 2, admins: 1 },
    sidekiq: { processed: 10, failed: 1, enqueued: 0, scheduled: 0, retries: 0 },
  };

  it('parses valid metrics', () => {
    expect(() => AdminMetricsSchema.parse(validMetrics)).not.toThrow();
  });

  it('parses string-label keyed by_status (real Rails output)', () => {
    const result = AdminMetricsSchema.parse(validMetrics);
    expect(result.submissions.by_status['completed']).toBe(3);
    expect(result.submissions.by_status['failed']).toBe(1);
  });

  it('parses string-label keyed by_severity', () => {
    const result = AdminMetricsSchema.parse(validMetrics);
    expect(result.issues.by_severity['high']).toBe(4);
  });
});
