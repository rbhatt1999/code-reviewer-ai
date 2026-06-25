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
  end

  describe '#build' do
    let(:code) { "def hello\n  puts 'hi'\nend\n" }

    context 'with no linter issues' do
      subject(:result) do
        builder.build(file_rel_path: 'app/models/user.rb', language: 'ruby', code: code, linter_issues: [])
      end

      it 'includes the file path' do
        expect(result).to include('path: app/models/user.rb')
      end

      it 'includes the language' do
        expect(result).to include('language: ruby')
      end

      it 'shows (none) for linter findings' do
        expect(result).to include('(none)')
      end

      it 'includes line-numbered code starting at 1' do
        expect(result).to include('   1| def hello')
        expect(result).to include('   2|   puts')
        expect(result).to include('   3| end')
      end
    end

    context 'with linter issues' do
      subject(:result) { builder.build(file_rel_path: 'app.rb', language: 'ruby', code: code, linter_issues: [issue]) }

      let(:issue) { instance_double(Issue, line_start: 2, line_end: 2, rule_id: 'Style/Foo', message: 'Use bar') }

      it 'formats linter issues as L<start>-<end> [<rule>] <message>' do
        expect(result).to include('L2-2 [Style/Foo] Use bar')
      end

      it 'does not show (none)' do
        expect(result).not_to include('(none)')
      end
    end
  end
end
