module LLM
  module Errors
    class TransportError < StandardError; end
    class MalformedResponseError < StandardError; end
  end
end
