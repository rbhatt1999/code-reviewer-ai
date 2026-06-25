import client from './client';
import { ProjectSchema } from './schemas';
import type { Project } from './schemas';
import { z } from 'zod';

interface CreateProjectParams {
  name: string;
  description?: string;
  language: string;
  default_branch?: string;
  repo_url?: string;
}

interface UpdateProjectParams {
  name?: string;
  description?: string;
  language?: string;
  default_branch?: string;
  repo_url?: string;
}

export async function listProjects(): Promise<Project[]> {
  const response = await client.get('/projects');
  return z.array(ProjectSchema).parse(response.data.projects);
}

export async function getProject(id: number): Promise<Project> {
  const response = await client.get(`/projects/${id}`);
  return ProjectSchema.parse(response.data.project);
}

export async function createProject(params: CreateProjectParams): Promise<Project> {
  const response = await client.post('/projects', { project: params });
  return ProjectSchema.parse(response.data.project);
}

export async function updateProject(id: number, params: UpdateProjectParams): Promise<Project> {
  const response = await client.patch(`/projects/${id}`, { project: params });
  return ProjectSchema.parse(response.data.project);
}

export async function deleteProject(id: number): Promise<void> {
  await client.delete(`/projects/${id}`);
}
