require 'rails_helper'

RSpec.describe Reports::PdfRenderer do
  it 'renders markdown to PDF bytes' do
    fake = instance_double(Grover, to_pdf: "%PDF-1.4\nstub")
    allow(Grover).to receive(:new).and_return(fake)
    result = described_class.new(markdown: "# Hello\n\nbody").call
    expect(result).to start_with('%PDF')
  end

  it 'passes HTML containing rendered markdown to Grover' do
    allow(Grover).to receive(:new) do |html, *|
      instance_double(Grover, to_pdf: "%PDF #{html}")
    end
    out = described_class.new(markdown: "# Title").call
    expect(out).to include('<h1>Title</h1>')
  end
end
