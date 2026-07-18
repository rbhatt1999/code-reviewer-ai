require 'rails_helper'

RSpec.describe Diff::HunkFormatter do
  describe '.number' do
    it 'numbers context and added lines using the new-file line numbers' do
      patch = "@@ -10,3 +10,4 @@ def foo\n context\n-old\n+new one\n+new two\n context2"

      result = described_class.number(patch)

      expect(result).to include('  10|  context')
      expect(result).to include('    -| -old')
      expect(result).to include('  11| +new one')
      expect(result).to include('  12| +new two')
      expect(result).to include('  13|  context2')
    end

    it 'handles multiple hunks, restarting the counter at each header' do
      patch = "@@ -1,1 +1,1 @@\n+first\n@@ -50,1 +52,1 @@\n+second"

      result = described_class.number(patch)

      expect(result).to include("   1| +first")
      expect(result).to include("  52| +second")
    end

    it 'leaves the "no newline at end of file" marker untouched' do
      patch = "@@ -1,1 +1,1 @@\n+line\n\\ No newline at end of file"

      result = described_class.number(patch)

      expect(result).to include("\\ No newline at end of file")
    end

    it 'falls back to the raw patch text if parsing raises' do
      patch = nil

      expect { described_class.number(patch) }.not_to raise_error
    end
  end
end
