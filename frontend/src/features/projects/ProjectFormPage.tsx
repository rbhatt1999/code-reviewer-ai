import { useForm } from 'react-hook-form';
import { useNavigate } from 'react-router-dom';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { createProject } from '@api/projects';

const LANGUAGES = ['ruby', 'python', 'javascript', 'typescript', 'java'] as const;

interface ProjectForm {
  name: string;
  description: string;
  language: string;
  default_branch: string;
  repo_url: string;
}

export function ProjectFormPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const {
    register,
    handleSubmit,
    formState: { errors },
    setError,
  } = useForm<ProjectForm>({ defaultValues: { default_branch: 'main' } });

  const mutation = useMutation({
    mutationFn: (data: ProjectForm) =>
      createProject({
        name: data.name,
        description: data.description || undefined,
        language: data.language,
        default_branch: data.default_branch || 'main',
        repo_url: data.repo_url || undefined,
      }),
    onSuccess: (project) => {
      queryClient.invalidateQueries({ queryKey: ['projects'] });
      navigate(`/projects/${project.id}`);
    },
    onError: () => {
      setError('root', { message: 'Failed to create project. Please try again.' });
    },
  });

  const onSubmit = (data: ProjectForm) => mutation.mutate(data);

  return (
    <div className="max-w-2xl" data-testid="project-form-page">
      <p className="app-kicker">Workspace</p><h1 className="app-page-title mt-1 mb-2">New project</h1><p className="mb-7 text-sm text-zinc-500">Connect repository details before first review.</p>
      <div className="app-panel p-6 sm:p-8">
        <form onSubmit={handleSubmit(onSubmit)} noValidate data-testid="project-form">
          {errors.root && (
            <p className="text-red-600 text-sm mb-4" data-testid="project-form-error">
              {errors.root.message}
            </p>
          )}
          <div className="mb-4">
            <label htmlFor="name" className="block text-sm font-medium text-gray-600 mb-1">
              Name <span className="text-red-500">*</span>
            </label>
            <input
              id="name"
              type="text"
              className="w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              data-testid="project-form-name"
              {...register('name', { required: 'Project name is required' })}
            />
            {errors.name && (
              <p className="text-red-500 text-xs mt-1">{errors.name.message}</p>
            )}
          </div>

          <div className="mb-4">
            <label htmlFor="description" className="block text-sm font-medium text-gray-600 mb-1">
              Description
            </label>
            <textarea
              id="description"
              rows={3}
              className="w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              data-testid="project-form-description"
              {...register('description')}
            />
          </div>

          <div className="mb-4">
            <label htmlFor="language" className="block text-sm font-medium text-gray-600 mb-1">
              Language <span className="text-red-500">*</span>
            </label>
            <select
              id="language"
              className="w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              data-testid="project-form-language"
              {...register('language', { required: 'Language is required' })}
            >
              <option value="">Select a language</option>
              {LANGUAGES.map((lang) => (
                <option key={lang} value={lang}>
                  {lang.charAt(0).toUpperCase() + lang.slice(1)}
                </option>
              ))}
            </select>
            {errors.language && (
              <p className="text-red-500 text-xs mt-1">{errors.language.message}</p>
            )}
          </div>

          <div className="mb-4">
            <label
              htmlFor="default_branch"
              className="block text-sm font-medium text-gray-600 mb-1"
            >
              Default branch
            </label>
            <input
              id="default_branch"
              type="text"
              className="w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              data-testid="project-form-default-branch"
              {...register('default_branch')}
            />
          </div>

          <div className="mb-6">
            <label htmlFor="repo_url" className="block text-sm font-medium text-gray-600 mb-1">
              Repository URL
            </label>
            <input
              id="repo_url"
              type="url"
              className="w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              data-testid="project-form-repo-url"
              {...register('repo_url')}
            />
          </div>

          <div className="flex gap-3">
            <button
              type="submit"
              disabled={mutation.isPending}
              className="btn-primary"
              data-testid="project-form-submit"
            >
              {mutation.isPending ? 'Creating...' : 'Create project'}
            </button>
            <button
              type="button"
              onClick={() => navigate('/projects')}
              className="btn-secondary"
              data-testid="project-form-cancel"
            >
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
