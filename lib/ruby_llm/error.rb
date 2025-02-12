# frozen_string_literal: true

module RubyLLM
  # Custom error class that wraps API errors from different providers
  # into a consistent format with helpful error messages.
  #
  # Example:
  #   begin
  #     chat.ask "What's 2+2?"
  #   rescue RubyLLM::Error => e
  #     puts "Couldn't chat with AI: #{e.message}"
  #   end
  class Error < StandardError
    attr_reader :response

    def initialize(response = nil, message = nil)
      @response = response
      super(message || response&.body)
    end
  end

  class UnauthorizedError < Error; end
  class BadRequestError < Error; end
  class RateLimitError < Error; end
  class ServerError < Error; end

  # Faraday middleware that maps provider-specific API errors to RubyLLM errors.
  # Uses provider's parse_error method to extract meaningful error messages.
  class ErrorMiddleware < Faraday::Middleware
    def initialize(app, provider: nil)
      super(app)
      @provider = provider
    end

    def call(env) # rubocop:disable Metrics/MethodLength
      @app.call(env).on_complete do |response|
        message = @provider&.parse_error(response)

        case response.status
        when 400
          raise BadRequestError.new(response, message)
        when 401
          raise UnauthorizedError.new(response, 'Invalid API key - check your credentials')
        when 429
          raise RateLimitError.new(response, 'Rate limit exceeded - please wait a moment')
        when 500..599
          raise ServerError.new(response, 'API server error - please try again')
        end
      end
    end
  end
end

Faraday::Middleware.register_middleware(llm_errors: RubyLLM::ErrorMiddleware)
