import { z } from 'zod';

export const UserSchema = z.object({
  id: z.number(),
  email: z.string().email(),
  name: z.string(),
  role: z.enum(['reviewer', 'admin']),
});
export type User = z.infer<typeof UserSchema>;

export const ProjectSchema = z.object({
  id: z.number(),
  name: z.string(),
  description: z.string().nullable(),
  language: z.enum(['ruby', 'python', 'javascript', 'typescript', 'java']),
  default_branch: z.string(),
  repo_url: z.string().nullable(),
  submissions_count: z.number(),
  created_at: z.string(),
  updated_at: z.string(),
});
export type Project = z.infer<typeof ProjectSchema>;

export const SubmissionSchema = z.object({
  id: z.number(),
  project_id: z.number(),
  kind: z.enum(['paste', 'single_file', 'zip', 'git_url', 'github_webhook']),
  status: z.enum(['pending', 'ingesting', 'analyzing', 'reviewing', 'aggregating', 'completed', 'failed']),
  language: z.string(),
  size_bytes: z.number(),
  source_ref: z.string().nullable(),
  issues_count: z.number(),
  finished_at: z.string().nullable(),
  created_at: z.string(),
});
export type Submission = z.infer<typeof SubmissionSchema>;

export const IssueSchema = z.object({
  id: z.number(),
  source: z.enum(['linter', 'llm', 'hybrid']),
  rule_id: z.string(),
  severity: z.enum(['info', 'low', 'medium', 'high', 'critical']),
  category: z.enum(['code_quality', 'bug', 'style', 'security', 'refactor']),
  file_path: z.string(),
  line_start: z.number(),
  line_end: z.number(),
  message: z.string(),
  suggestion: z.string().nullable(),
  confidence: z.number().nullable(),
});
export type Issue = z.infer<typeof IssueSchema>;

export const ReviewSchema = z.object({
  id: z.number(),
  mode: z.enum(['hybrid', 'linter_only']),
  summary: z.string().nullable(),
  scores: z.record(z.string(), z.number()).nullable(),
  total_issues: z.number(),
});
export type Review = z.infer<typeof ReviewSchema>;

export const SourceFileSchema = z.object({ path: z.string() });
export const FileListSchema = z.object({ files: z.array(SourceFileSchema) });
export const FileContentSchema = z.object({
  path: z.string(),
  content: z.string(),
  language: z.string(),
});
export type SourceFile = z.infer<typeof SourceFileSchema>;
export type FileContent = z.infer<typeof FileContentSchema>;

export const AdminMetricsSchema = z.object({
  submissions: z.object({
    total: z.number(),
    by_status: z.record(z.string(), z.number()), // string enum-LABEL keys, e.g. {"completed":3,"failed":1}
    completed: z.number(),
    failed: z.number(),
  }),
  issues: z.object({
    total: z.number(),
    by_severity: z.record(z.string(), z.number()),
  }),
  users: z.object({ total: z.number(), admins: z.number() }),
  sidekiq: z.object({
    processed: z.number(),
    failed: z.number(),
    enqueued: z.number(),
    scheduled: z.number(),
    retries: z.number(),
  }),
});
export type AdminMetrics = z.infer<typeof AdminMetricsSchema>;
