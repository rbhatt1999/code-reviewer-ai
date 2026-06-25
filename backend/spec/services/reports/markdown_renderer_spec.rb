require 'rails_helper'

RSpec.describe Reports::MarkdownRenderer do
  let(:sub)   { create(:submission, :completed, source_ref: 'my_file.rb') }
  let(:issue) { create(:issue, :linter, submission: sub, message: 'Too complex', file_path: 'app/a.rb', line_start: 5, line_end: 5) }
  let(:payload) { Reports::PayloadBuilder.new(submission: sub).call }

  before { issue }

  subject(:md) { described_class.new(payload: payload).call }

  it 'returns a string' do
    expect(md).to be_a(String)
  end

  it 'includes the source_ref' do
    expect(md).to include('my_file.rb')
  end

  it 'includes the issue message' do
    expect(md).to include('Too complex')
  end
end
