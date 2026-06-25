require 'rails_helper'

RSpec.describe LLM::OllamaClient, type: :service do
  let(:base_url) { ENV.fetch('OLLAMA_BASE_URL', 'http://localhost:11434') }
  let(:client)   { described_class.new(base_url: base_url) }
  let(:chat_url) { "#{base_url}/api/chat" }

  describe '#chat' do
    context 'happy path (200 response)' do
      before do
        stub_request(:post, chat_url)
          .to_return(
            status: 200,
            body: { message: { content: '{"issues":[]}' } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns the assistant message content string' do
        result = client.chat(system: 'sys', user: 'usr')
        expect(result).to eq('{"issues":[]}')
      end
    end

    context 'non-200 response (503)' do
      before do
        stub_request(:post, chat_url)
          .to_return(status: 503, body: 'down')
      end

      it 'raises LLM::Errors::TransportError' do
        expect { client.chat(system: 'sys', user: 'usr') }
          .to raise_error(LLM::Errors::TransportError, /503/)
      end
    end

    context 'connection failure' do
      before do
        stub_request(:post, chat_url)
          .to_raise(Faraday::ConnectionFailed.new('refused'))
      end

      it 'raises LLM::Errors::TransportError' do
        expect { client.chat(system: 'sys', user: 'usr') }
          .to raise_error(LLM::Errors::TransportError)
      end
    end

    context 'custom model via OLLAMA_MODEL env var' do
      around do |example|
        original = ENV.fetch('OLLAMA_MODEL', nil)
        ENV['OLLAMA_MODEL'] = 'test-model'
        example.run
        ENV['OLLAMA_MODEL'] = original
      end

      before do
        stub_request(:post, chat_url)
          .to_return(
            status: 200,
            body: { message: { content: '{}' } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'sends the correct model in the request body' do
        described_class.new(base_url: base_url).chat(system: 'sys', user: 'usr')

        expect(WebMock).to(have_requested(:post, chat_url)
          .with { |req| JSON.parse(req.body)['model'] == 'test-model' })
      end
    end
  end
end
