import client from './client';
import { SubmissionSchema, IssueSchema, ReviewSchema, FileListSchema, FileContentSchema } from './schemas';
import type { Submission, Issue, Review, SourceFile, FileContent } from './schemas';
import { z } from 'zod';

const MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024; // 5 MB

export class FileSizeLimitError extends Error {
  constructor() {
    super('File exceeds the 5 MB size limit.');
    this.name = 'FileSizeLimitError';
  }
}

interface CreateSubmissionParams {
  projectId: number;
  kind: 'paste' | 'single_file';
  file?: File;
  content?: string;
}

export async function createSubmission(params: CreateSubmissionParams): Promise<Submission> {
  if (params.file && params.file.size > MAX_FILE_SIZE_BYTES) {
    throw new FileSizeLimitError();
  }

  const formData = new FormData();
  formData.append('submission[kind]', params.kind);
  if (params.file) {
    formData.append('submission[file]', params.file);
  }
  if (params.content) {
    formData.append('submission[content]', params.content);
  }

  const response = await client.post(`/projects/${params.projectId}/submissions`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
  return SubmissionSchema.parse(response.data.submission);
}

export async function listSubmissions(projectId: number): Promise<Submission[]> {
  const response = await client.get(`/projects/${projectId}/submissions`);
  return z.array(SubmissionSchema).parse(response.data.submissions);
}

export async function getSubmission(id: number): Promise<Submission> {
  const response = await client.get(`/submissions/${id}`);
  return SubmissionSchema.parse(response.data.submission);
}

export async function getIssues(submissionId: number): Promise<Issue[]> {
  const response = await client.get(`/submissions/${submissionId}/issues`);
  return z.array(IssueSchema).parse(response.data.issues);
}

export async function getReview(submissionId: number): Promise<Review> {
  const response = await client.get(`/submissions/${submissionId}/review`);
  return ReviewSchema.parse(response.data.review);
}

export async function getSubmissionFiles(id: number): Promise<SourceFile[]> {
  const response = await client.get(`/submissions/${id}/files`);
  return FileListSchema.parse(response.data).files;
}

export async function getFileContent(id: number, path: string): Promise<FileContent> {
  // Encode each segment so spaces/#/?/% don't corrupt the URL; preserve / separators
  const encoded = path.split('/').map(encodeURIComponent).join('/');
  const response = await client.get(`/submissions/${id}/files/${encoded}`);
  return FileContentSchema.parse(response.data);
}
