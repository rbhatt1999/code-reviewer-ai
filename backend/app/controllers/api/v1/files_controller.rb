module Api
  module V1
    class FilesController < ApplicationController
      MAX_VIEW_BYTES = 1_000_000 # 1 MB per file to the viewer
      TEXT_EXTS = %w[.rb .py .js .jsx .ts .tsx .java .json .yml .yaml .md .txt].freeze

      before_action :set_submission

      def index
        render json: { files: servable_files.map { |rel| { path: rel } } }, status: :ok
      end

      def show
        rel = params[:path].to_s
        abs = resolve_within_root!(rel) # nil on traversal/escape/missing
        return render_not_found unless abs && File.file?(abs)
        return render_too_large if File.size(abs) > MAX_VIEW_BYTES
        return render_unsupported unless TEXT_EXTS.include?(File.extname(abs).downcase)

        render json: { path: rel, language: @submission.language,
                       content: File.read(abs, encoding: 'UTF-8') }, status: :ok
      rescue ArgumentError # invalid UTF-8 / binary
        render_unsupported
      end

      private

      def set_submission
        @submission = current_user.submissions.find(params[:id]) # 404 if not owned
      end

      def root_dir
        @root_dir ||= if File.directory?(@submission.blob_path)
                        @submission.blob_path
                      else
                        File.dirname(@submission.blob_path)
                      end
      end

      # Absolute path ONLY if it resolves inside root_dir (symlink-safe), else nil.
      def resolve_within_root!(rel)
        return nil if rel.include?("\0")

        root_real = File.realpath(root_dir)
        candidate = File.expand_path(File.join(root_dir, rel))
        return nil unless File.exist?(candidate)

        target_real = File.realpath(candidate)
        prefix = root_real.end_with?(File::SEPARATOR) ? root_real : root_real + File::SEPARATOR
        target_real.start_with?(prefix) ? target_real : nil
      rescue Errno::ENOENT
        nil
      end

      def servable_files
        return [File.basename(@submission.blob_path)] unless File.directory?(@submission.blob_path)

        Dir.glob('**/*', base: root_dir)
           .select { |rel| File.file?(File.join(root_dir, rel)) && TEXT_EXTS.include?(File.extname(rel).downcase) }
           .sort.first(500)
      end

      def render_not_found  = render(json: { error: 'not_found' }, status: :not_found)
      def render_too_large  = render(json: { error: 'too_large' }, status: :payload_too_large)
      def render_unsupported = render(json: { error: 'unsupported_media_type' }, status: :unsupported_media_type)
    end
  end
end
