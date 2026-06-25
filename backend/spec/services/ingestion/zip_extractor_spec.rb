require 'rails_helper'
require 'zip'

RSpec.describe Ingestion::ZipExtractor do
  subject(:extractor) do
    described_class.new(zip_path: zip_path, dest_dir: dest_dir, max_bytes: max_bytes)
  end

  let(:tmp_root)  { Rails.root.join('tmp', 'zip_extractor_spec') }
  let(:dest_dir)  { File.join(tmp_root, 'extracted') }
  let(:max_bytes) { 1_048_576 } # 1 MB

  # Builds a zip archive in memory and writes it to a tempfile.
  # block receives a Zip::OutputStream so callers can add entries.
  def build_zip(&block)
    io = Zip::OutputStream.write_buffer(&block)
    path = File.join(tmp_root, 'test.zip')
    FileUtils.mkdir_p(tmp_root)
    File.binwrite(path, io.string)
    path
  end

  let(:zip_path) do
    build_zip do |zos|
      zos.put_next_entry('src/hello.rb')
      zos.write("puts 'hello'\n")

      zos.put_next_entry('src/world.py')
      zos.write("print('world')\n")
    end
  end

  after { FileUtils.rm_rf(tmp_root) }

  describe 'happy path' do
    it 'returns a Result with correct file count and extracted file list' do
      result = extractor.call

      expect(result.file_count).to eq(2)
      expect(result.files).to contain_exactly('src/hello.rb', 'src/world.py')
    end

    it 'actually writes files to dest_dir' do
      extractor.call

      expect(File).to exist(File.join(dest_dir, 'src', 'hello.rb'))
      expect(File).to exist(File.join(dest_dir, 'src', 'world.py'))
    end

    it 'returns a positive total_bytes' do
      result = extractor.call
      expect(result.total_bytes).to be > 0
    end
  end

  describe 'zip-bomb defense' do
    let(:max_bytes) { 20 } # tiny cap to trigger on a realistic entry

    it 'raises SizeLimitExceeded before the limit is crossed' do
      expect { extractor.call }.to raise_error(Ingestion::SizeLimitExceeded)
    end
  end

  describe 'path traversal protection' do
    let(:zip_path) do
      build_zip do |zos|
        # Entry whose normalized path escapes the dest_dir.
        zos.put_next_entry('../escape/evil.rb')
        zos.write("evil\n")
        # A legitimate entry to confirm we don't abort the whole archive.
        zos.put_next_entry('safe.rb')
        zos.write("safe\n")
      end
    end

    it 'rejects the traversal entry by raising a RuntimeError' do
      expect { extractor.call }.to raise_error(RuntimeError, /traversal/)
    end

    context 'with a sibling-directory traversal (shared prefix, no separator)' do
      # `extracted` is dest_dir basename; `extracted_evil` shares the prefix without a separator.
      # A naive start_with?(dest_dir) would allow this; the separator guard rejects it.
      let(:zip_path) do
        build_zip do |zos|
          zos.put_next_entry('../extracted_evil/x.rb')
          zos.write("evil sibling\n")
        end
      end

      it 'rejects the sibling-dir traversal entry' do
        expect { extractor.call }.to raise_error(RuntimeError, /traversal/)
      end
    end
  end

  describe 'dotfile filtering' do
    let(:zip_path) do
      build_zip do |zos|
        zos.put_next_entry('.DS_Store')
        zos.write("garbage\n")

        zos.put_next_entry('__MACOSX/._Metadata')
        zos.write("macos-junk\n")

        zos.put_next_entry('real_file.rb')
        zos.write("puts 1\n")
      end
    end

    it 'skips dotfiles and __MACOSX entries' do
      result = extractor.call

      expect(result.files).to eq(['real_file.rb'])
      expect(File).not_to exist(File.join(dest_dir, '.DS_Store'))
    end
  end
end
