module LLM
  # DeepSeek chat-completions client (OpenAI-compatible API).
  class DeepseekClient
    def initialize(base_url: ENV.fetch('DEEPSEEK_BASE_URL', 'https://api.deepseek.com'),
                    model: ENV.fetch('DEEPSEEK_MODEL', 'deepseek-v4-flash'),
                    api_key: ENV.fetch('DEEPSEEK_API_KEY', nil))
      @base_url = base_url
      @model    = model
      @api_key  = api_key
    end

    # Sends the full conversation so far (system/user/assistant/tool messages)
    # and, optionally, an OpenAI-compatible `tools` function schema. Returns the
    # assistant MESSAGE HASH as-is — {'content' => ..., 'tool_calls' => [...]} —
    # rather than just the content string, so callers can drive an agentic
    # tool-calling loop (needed by LLM::ReviewService's read_file flow).
    # Raises Llm::Errors::TransportError on transport failure or missing key.
    def complete(messages:, tools: nil, response_format: nil, max_tokens: nil)
      raise Errors::TransportError, 'DEEPSEEK_API_KEY is not set' if @api_key.blank?

      body = { model: @model, temperature: 0.1, messages: messages }
      body[:tools] = tools if tools.present?
      body[:response_format] = response_format if response_format.present?
      body[:max_tokens] = max_tokens if max_tokens.present?

      resp = connection.post('/chat/completions') do |req|
        req.headers['Content-Type']  = 'application/json'
        req.headers['Authorization'] = "Bearer #{@api_key}"
        req.body = body.to_json
      end
      raise Errors::TransportError, "deepseek #{resp.status}" unless resp.success?

      choice = JSON.parse(resp.body).dig('choices', 0) || {}
      (choice['message'] || {}).merge('_finish_reason' => choice['finish_reason'])
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
