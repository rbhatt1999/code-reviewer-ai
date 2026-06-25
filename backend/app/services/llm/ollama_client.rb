module LLM
  class OllamaClient
    def initialize(base_url: ENV.fetch('OLLAMA_BASE_URL', 'http://localhost:11434'),
                   model: ENV.fetch('OLLAMA_MODEL', 'qwen2.5-coder:7b-instruct-q4_K_M'))
      @base_url = base_url
      @model    = model
    end

    # Returns the assistant message content STRING.
    # Raises Llm::Errors::TransportError on transport failure.
    def chat(system:, user:, num_ctx: 8192)
      resp = connection.post('/api/chat') do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = {
          model: @model, stream: false, format: 'json',
          options: { temperature: 0.1, num_ctx: num_ctx },
          messages: [{ role: 'system', content: system }, { role: 'user', content: user }]
        }.to_json
      end
      raise Errors::TransportError, "ollama #{resp.status}" unless resp.success?

      JSON.parse(resp.body).dig('message', 'content').to_s
    rescue Faraday::Error => e
      raise Errors::TransportError, e.message
    end

    private

    def connection
      @connection ||= Faraday.new(url: @base_url) do |f|
        f.request :retry, max: 2, interval: 0.2, backoff_factor: 2,
                          exceptions: [Faraday::ConnectionFailed, Faraday::TimeoutError]
        f.options.timeout = 120
        f.options.open_timeout = 5
        f.adapter Faraday.default_adapter
      end
    end
  end
end
