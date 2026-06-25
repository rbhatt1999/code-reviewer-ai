require 'open3'

module Ast
  class Extractor
    EXTENSION_MAP = {
      'ruby'       => %w[.rb],
      'python'     => %w[.py],
      'javascript' => %w[.js .jsx],
      'typescript' => %w[.ts .tsx],
      'java'       => %w[.java]
    }.freeze

    # Node type patterns that signal a top-level definition for each language.
    DEFINITION_PATTERNS = {
      'ruby'       => /\(method|\(class|\(module/,
      'python'     => /\(function_definition|\(class_definition/,
      'javascript' => /\(function_declaration|\(function_expression|\(arrow_function|\(class_declaration/,
      'typescript' => /\(function_declaration|\(function_expression|\(arrow_function|\(class_declaration|\(interface_declaration/,
      'java'       => /\(method_declaration|\(class_declaration|\(interface_declaration/
    }.freeze

    def initialize(root_path:, language:)
      @root_path = root_path.to_s
      @language  = language.to_s.downcase
    end

    def call
      return nil unless File.exist?(@root_path)

      source_files = collect_source_files
      # Return nil for an empty directory — no source to analyse.
      return nil if source_files.empty?

      file_summaries = source_files.filter_map do |abs_path|
        parse_file(abs_path)
      end

      # Return nil when every file failed to parse (e.g. CLI missing or grammar absent).
      return nil if file_summaries.empty?

      { 'files' => file_summaries }
    rescue StandardError => e
      Rails.logger.warn("[Ast::Extractor] unexpected error: #{e.class} — #{e.message}")
      nil
    end

    private

    def collect_source_files
      extensions = EXTENSION_MAP.fetch(@language, [])
      return [] if extensions.empty?

      if File.directory?(@root_path)
        Dir.glob('**/*', base: @root_path)
           .select { |rel| extensions.include?(File.extname(rel)) }
           .map { |rel| File.join(@root_path, rel) }
      else
        ext = File.extname(@root_path)
        extensions.include?(ext) ? [@root_path] : []
      end
    end

    def parse_file(abs_path)
      stdout, _stderr, status = Open3.capture3('tree-sitter', 'parse', abs_path)

      unless status.exitstatus == 0
        Rails.logger.warn("[Ast::Extractor] tree-sitter non-zero exit for #{abs_path}")
        return nil
      end

      relative = relative_path(abs_path)

      {
        'path'        => relative,
        'language'    => @language,
        'node_counts' => count_nodes(stdout),
        'definitions' => extract_definitions(stdout)
      }
    rescue Errno::ENOENT
      # tree-sitter CLI not installed — warn and propagate nil for this file.
      Rails.logger.warn('[Ast::Extractor] tree-sitter CLI not found — AST extraction skipped')
      nil
    rescue StandardError => e
      Rails.logger.warn("[Ast::Extractor] failed to parse #{abs_path}: #{e.message}")
      nil
    end

    def count_nodes(sexp)
      # Match all node-type identifiers in the S-expression output.
      sexp.scan(/\((\w+)/).map(&:first).tally
    end

    def extract_definitions(sexp)
      pattern = DEFINITION_PATTERNS[@language]
      return [] unless pattern

      # Extract lines that contain a top-level definition node.
      sexp.each_line.select { |line| line.match?(pattern) }.map(&:strip)
    end

    def relative_path(abs_path)
      if File.directory?(@root_path)
        Pathname.new(abs_path).relative_path_from(Pathname.new(@root_path)).to_s
      else
        File.basename(abs_path)
      end
    end
  end
end
