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
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-800">Projects</h1>
        <Link
          to="/projects/new"
          className="bg-indigo-600 text-white px-4 py-2 rounded text-sm font-medium hover:bg-indigo-700"
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
        <div className="text-center py-16 text-gray-400" data-testid="project-list-empty">
          <p className="text-lg">No projects yet.</p>
          <Link to="/projects/new" className="text-indigo-600 hover:underline mt-2 inline-block">
            Create your first project
          </Link>
        </div>
      )}

      {projects && projects.length > 0 && (
        <ul className="space-y-3" data-testid="project-list">
          {projects.map((project) => (
            <li
              key={project.id}
              className="bg-white rounded-lg border border-gray-200 shadow-sm hover:shadow-md transition-shadow"
              data-testid={`project-list-item-${project.id}`}
            >
              <Link to={`/projects/${project.id}`} className="block p-5">
                <div className="flex items-start justify-between">
                  <div>
                    <h2 className="text-base font-semibold text-gray-800">{project.name}</h2>
                    {project.description && (
                      <p className="text-sm text-gray-500 mt-1">{project.description}</p>
                    )}
                  </div>
                  <span className="text-xs bg-indigo-100 text-indigo-700 px-2 py-1 rounded font-mono">
                    {project.language}
                  </span>
                </div>
                <p className="text-xs text-gray-400 mt-3">
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
