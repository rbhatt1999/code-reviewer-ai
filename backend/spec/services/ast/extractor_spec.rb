require 'rails_helper'

RSpec.describe Ast::Extractor do
  let(:tmp_root) { Rails.root.join('tmp', 'ast_extractor_spec') }

  def ok_status
    instance_double(Process::Status, exitstatus: 0)
  end

  def fail_status(code = 1)
    instance_double(Process::Status, exitstatus: code)
  end

  after { FileUtils.rm_rf(tmp_root) }

  # A minimal but realistic S-expression produced by tree-sitter for Ruby.
  let(:ruby_sexp) do
    <<~SEXP
      (source_file [0, 0] - [5, 0]
        (method [0, 0] - [2, 3]
          name: (identifier [0, 4] - [0, 7])
          body: (body_statement [1, 2] - [1, 13]
            (call [1, 2] - [1, 13]
              method: (identifier [1, 2] - [1, 6])
              arguments: (argument_list [1, 6] - [1, 13]
                (string [1, 7] - [1, 12])))))
        (class [3, 0] - [4, 3]
          name: (constant [3, 6] - [3, 9])
          body: (body_statement [3, 11] - [3, 11])))
    SEXP
  end

  describe 'single-file happy path' do
    let(:ruby_file) do
      FileUtils.mkdir_p(tmp_root)
      path = File.join(tmp_root.to_s, 'sample.rb')
      File.write(path, "def foo\n  puts 'hi'\nend\n")
      path
    end

    before do
      allow(Open3).to receive(:capture3)
        .with('tree-sitter', 'parse', ruby_file)
        .and_return([ruby_sexp, '', ok_status])
    end

    subject(:result) { described_class.new(root_path: ruby_file, language: 'ruby').call }

    it 'returns a hash with a files array' do
      expect(result).to be_a(Hash)
      expect(result['files']).to be_an(Array)
      expect(result['files'].size).to eq(1)
    end

    it 'includes node_counts with expected types' do
      counts = result['files'].first['node_counts']
      expect(counts).to include('method', 'class', 'source_file')
    end

    it 'includes definitions matching method and class nodes' do
      defs = result['files'].first['definitions']
      expect(defs).not_to be_empty
      expect(defs.any? { |d| d.include?('(method') }).to be true
    end

    it 'uses the basename as the path for single-file input' do
      expect(result['files'].first['path']).to eq('sample.rb')
    end
  end

  describe 'directory with multiple source files' do
    let(:dir) do
      FileUtils.mkdir_p(tmp_root)
      File.write(File.join(tmp_root.to_s, 'a.rb'), "def a; end\n")
      File.write(File.join(tmp_root.to_s, 'b.rb'), "def b; end\n")
      tmp_root.to_s
    end

    before do
      allow(Open3).to receive(:capture3)
        .with('tree-sitter', 'parse', anything)
        .and_return([ruby_sexp, '', ok_status])
    end

    it 'processes both files and returns two entries' do
      result = described_class.new(root_path: dir, language: 'ruby').call
      expect(result['files'].size).to eq(2)
    end
  end

  describe 'tree-sitter CLI not found (Errno::ENOENT)' do
    let(:ruby_file) do
      FileUtils.mkdir_p(tmp_root)
      path = File.join(tmp_root.to_s, 'sample.rb')
      File.write(path, "puts 1\n")
      path
    end

    before do
      allow(Open3).to receive(:capture3)
        .with('tree-sitter', 'parse', ruby_file)
        .and_raise(Errno::ENOENT)
    end

    it 'returns nil instead of raising' do
      result = described_class.new(root_path: ruby_file, language: 'ruby').call
      expect(result).to be_nil
    end
  end

  describe 'tree-sitter non-zero exit' do
    let(:ruby_file) do
      FileUtils.mkdir_p(tmp_root)
      path = File.join(tmp_root.to_s, 'sample.rb')
      File.write(path, "puts 1\n")
      path
    end

    before do
      allow(Open3).to receive(:capture3)
        .with('tree-sitter', 'parse', ruby_file)
        .and_return(['', 'unknown grammar', fail_status])
    end

    it 'returns nil instead of raising' do
      result = described_class.new(root_path: ruby_file, language: 'ruby').call
      expect(result).to be_nil
    end
  end

  describe 'empty directory' do
    let(:empty_dir) do
      FileUtils.mkdir_p(tmp_root)
      tmp_root.to_s
    end

    it 'returns nil — no source files to analyse' do
      result = described_class.new(root_path: empty_dir, language: 'ruby').call
      expect(result).to be_nil
    end
  end

  describe 'non-existent path' do
    it 'returns nil' do
      result = described_class.new(root_path: '/nonexistent/path', language: 'ruby').call
      expect(result).to be_nil
    end
  end
end
