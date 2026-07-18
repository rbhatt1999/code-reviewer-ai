import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { listProjects } from '@api/projects';

export function ProjectListPage() {
  const { data: projects, isLoading, isError } = useQuery({
    queryKey: ['projects'],
    queryFn: listProjects,
  });

  return (
    <div data-testid="project-list-page">
      <div className="mb-8 flex items-end justify-between gap-4">
        <div><p className="app-kicker">Workspace</p><h1 className="app-page-title mt-1">Projects</h1><p className="mt-1 text-sm text-zinc-500">Repositories and review history.</p></div>
        <Link
          to="/projects/new"
          className="btn-primary shrink-0"
          data-testid="project-list-new-button"
        >
          New project
        </Link>
      </div>

      {isLoading && (
        <p className="text-gray-500" data-testid="project-list-loading">
          Loading projects...
        </p>
      )}

      {isError && (
        <p className="text-red-600" data-testid="project-list-error">
          Failed to load projects.
        </p>
      )}

      {projects && projects.length === 0 && (
        <div className="empty-state" data-testid="project-list-empty">
          <p className="text-base font-medium text-zinc-800">No projects yet.</p>
          <Link to="/projects/new" className="mt-2 inline-block font-medium text-blue-600 hover:text-blue-700">
            Create your first project
          </Link>
        </div>
      )}

      {projects && projects.length > 0 && (
        <ul className="overflow-hidden rounded-xl border border-zinc-200 bg-white" data-testid="project-list">
          {projects.map((project) => (
            <li
              key={project.id}
              className="border-b border-zinc-200 last:border-0 hover:bg-zinc-50/80"
              data-testid={`project-list-item-${project.id}`}
            >
              <Link to={`/projects/${project.id}`} className="block p-5 sm:p-6">
                <div className="flex items-start justify-between">
                  <div>
                    <h2 className="text-base font-semibold text-zinc-950">{project.name}</h2>
                    {project.description && (
                      <p className="mt-1 text-sm text-zinc-500">{project.description}</p>
                    )}
                  </div>
                  <span className="rounded-md border border-blue-100 bg-blue-50 px-2 py-1 font-mono text-xs text-blue-700">
                    {project.language}
                  </span>
                </div>
                <p className="mt-3 text-xs text-zinc-400">
                  {project.submissions_count} submission{project.submissions_count !== 1 ? 's' : ''}
                </p>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
