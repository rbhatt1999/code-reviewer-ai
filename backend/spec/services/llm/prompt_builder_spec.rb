require 'rails_helper'

RSpec.describe LLM::PromptBuilder do
  subject(:builder) { described_class.new }

  describe 'SYSTEM_PROMPT' do
    it 'mentions all allowed severity values' do
      %w[info low medium high critical].each do |sev|
        expect(described_class::SYSTEM_PROMPT).to include(sev)
      end
    end

    it 'mentions all allowed category values' do
      %w[code_quality bug style security refactor].each do |cat|
        expect(described_class::SYSTEM_PROMPT).to include(cat)
      end
    end

    it 'describes the read_file tool workflow' do
      expect(described_class::SYSTEM_PROMPT).to include('read_file')
    end

    it 'requires a "file" key per issue in the schema' do
      expect(described_class::SYSTEM_PROMPT).to include('"file"')
    end
  end

  describe 'TOOLS' do
    it 'defines a read_file function tool' do
      fn = described_class::TOOLS.first[:function]
      expect(fn[:name]).to eq('read_file')
      expect(fn[:parameters][:required]).to include('path')
    end
  end

  describe '#build_initial' do
    let(:file_tree) do
      [
        { rel: 'app/models/user.rb', bytes: 120, linter_issue_count: 0 },
        { rel: 'app.rb', bytes: 40, linter_issue_count: 2 }
      ]
    end

    subject(:result) do
      builder.build_initial(language: 'ruby', file_tree: file_tree, linter_summary: linter_summary)
    end

    context 'with no linter findings' do
      let(:linter_summary) { [] }

      it 'includes the language' do
        expect(result).to include('ruby')
      end

      it 'lists every file in the tree with its size' do
        expect(result).to include('app/models/user.rb (120 bytes)')
        expect(result).to include('app.rb (40 bytes)')
      end

      it 'flags files with linter issues' do
        expect(result).to include('app.rb (40 bytes) [flagged: 2 issue(s)]')
      end

      it 'does not flag files with zero linter issues' do
        expect(result).not_to include('app/models/user.rb (120 bytes) [flagged')
      end

      it 'shows (none) for the static analyzer section' do
        expect(result).to include('(none)')
      end
    end

    context 'with linter findings' do
      let(:linter_summary) { ['app.rb:L2-2 [Style/Foo] Use bar'] }

      it 'includes the formatted finding' do
        expect(result).to include('app.rb:L2-2 [Style/Foo] Use bar')
      end

      it 'does not show (none)' do
        expect(result).not_to include('(none)')
      end
    end
  end
end
