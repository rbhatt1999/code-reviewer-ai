module LLM
  # DeepSeek chat-completions client (OpenAI-compatible API).
  # Swapped in for LLM::OllamaClient as the default LLM::ReviewService
  # client — same public interface (#chat), so no caller changes needed.
  class DeepseekClient
    def initialize(base_url: ENV.fetch('DEEPSEEK_BASE_URL', 'https://api.deepseek.com'),
                    model: ENV.fetch('DEEPSEEK_MODEL', 'deepseek-v4-flash'),
                    api_key: ENV.fetch('DEEPSEEK_API_KEY', nil))
      @base_url = base_url
      @model    = model
      @api_key  = api_key
    end

    # Returns the assistant message content STRING.
    # Raises Llm::Errors::TransportError on transport failure or missing key.
    def chat(system:, user:, num_ctx: 8192)
      raise Errors::TransportError, 'DEEPSEEK_API_KEY is not set' if @api_key.blank?

      resp = connection.post('/chat/completions') do |req|
        req.headers['Content-Type']  = 'application/json'
        req.headers['Authorization'] = "Bearer #{@api_key}"
        req.body = {
          model: @model,
          temperature: 0.1,
          response_format: { type: 'json_object' },
          messages: [{ role: 'system', content: system }, { role: 'user', content: user }]
        }.to_json
      end
      raise Errors::TransportError, "deepseek #{resp.status}" unless resp.success?

      JSON.parse(resp.body).dig('choices', 0, 'message', 'content').to_s
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
