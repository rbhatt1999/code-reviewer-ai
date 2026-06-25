require 'zip'

module Ingestion
  # Raised when the decompressed content would exceed the byte limit.
  class SizeLimitExceeded < StandardError; end

  class ZipExtractor
    Result = Struct.new(:file_count, :total_bytes, :files, keyword_init: true)

    DEFAULT_MAX_BYTES = ENV.fetch('MAX_UPLOAD_BYTES', 5_242_880).to_i

    def initialize(zip_path:, dest_dir:, max_bytes: DEFAULT_MAX_BYTES)
      @zip_path  = zip_path.to_s
      @dest_dir  = File.expand_path(dest_dir.to_s)
      @max_bytes = max_bytes
    end

    def call
      FileUtils.mkdir_p(@dest_dir)

      total_bytes = 0
      extracted   = []

      Zip::File.open(@zip_path) do |zip_file|
        zip_file.each do |entry|
          next if skip_entry?(entry)

          dest_path = safe_dest_path!(entry.name)

          # Zip-bomb defense: declared uncompressed size + running total.
          if entry.size + total_bytes > @max_bytes
            raise SizeLimitExceeded,
                  "Extraction would exceed #{@max_bytes} bytes (entry: #{entry.name})"
          end

          FileUtils.mkdir_p(File.dirname(dest_path))
          entry.extract(dest_path)

          total_bytes += entry.size
          relative    = Pathname.new(dest_path).relative_path_from(Pathname.new(@dest_dir)).to_s
          extracted << relative
        end
      end

      Result.new(file_count: extracted.size, total_bytes: total_bytes, files: extracted)
    end

    private

    def skip_entry?(entry)
      return true if entry.directory?
      return true if entry.symlink?

      basename = File.basename(entry.name)
      return true if basename.start_with?('.')          # dotfiles like .DS_Store
      return true if entry.name.include?('__MACOSX/')   # macOS resource-fork dirs

      false
    end

    def safe_dest_path!(entry_name)
      # Normalize so that path traversal like ../../etc/passwd is resolved.
      resolved = File.expand_path(entry_name, @dest_dir)

      # Guard both the exact dest_dir and any path starting with dest_dir + separator.
      # Without the separator check a sibling directory like /tmp/dest_evil/ would
      # pass the start_with? test when dest_dir is /tmp/dest.
      unless resolved.start_with?(@dest_dir + File::SEPARATOR) ||
             resolved == @dest_dir
        raise "Path traversal attempt: #{entry_name}"
      end

      resolved
    end
  end
end
