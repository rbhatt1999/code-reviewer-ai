module Api
  module V1
    class ProjectsController < ApplicationController
      before_action :set_project, only: %i[show update destroy regenerate_webhook_secret]

      def index
        projects = current_user.projects.order(created_at: :desc)
        render json: { projects: projects.map { |p| project_payload(p) } }, status: :ok
      end

      def create
        project = current_user.projects.build(project_params)
        project.save!
        render json: { project: project_payload(project) }, status: :created
      end

      def show
        render json: { project: project_payload(@project) }, status: :ok
      end

      def update
        @project.update!(project_params)
        render json: { project: project_payload(@project) }, status: :ok
      end

      def destroy
        @project.destroy!
        head :no_content
      end

      def regenerate_webhook_secret
        @project.regenerate_webhook_secret!
        render json: { project: project_payload(@project) }, status: :ok
      end

      private

      def set_project
        @project = current_user.projects.find(params[:id])
      end

      def project_params
        params.require(:project).permit(:name, :description, :language, :default_branch, :repo_url)
      end

      def project_payload(project)
        {
          id: project.id,
          name: project.name,
          description: project.description,
          language: project.language,
          default_branch: project.default_branch,
          repo_url: project.repo_url,
          webhook_secret: project.webhook_secret,
          submissions_count: project.submissions_count,
          created_at: project.created_at,
          updated_at: project.updated_at
        }
      end
    end
  end
end
