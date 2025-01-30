# frozen_string_literal: true

module RubyLLM
  module Providers
    # Base provider class for LLM interactions
    class Base
      attr_reader :connection

      def initialize
        @connection = build_connection
      end

      def chat(messages, **options, &block)
        raise NotImplementedError
      end

      protected

      def build_connection
        Faraday.new(url: api_base) do |f|
          f.options.timeout = RubyLLM.configuration.request_timeout
          f.request :json
          f.response :json
          f.adapter Faraday.default_adapter
        end
      end

      def handle_error(error)
        case error
        when Faraday::TimeoutError
          raise RubyLLM::Error, 'Request timed out'
        when Faraday::ConnectionFailed
          raise RubyLLM::Error, 'Connection failed'
        when Faraday::ClientError
          handle_api_error(error)
        else
          raise error
        end
      end

      def handle_api_error(error)
        raise RubyLLM::Error, "API error: #{error.response[:status]}"
      end
    end
  end
end
