# frozen_string_literal: true

module RubyLLM
  module Providers
    # Gemini API integration.
    module Gemini
      extend OpenAI
      extend Gemini::Models

      module_function

      def api_base
        'https://generativelanguage.googleapis.com/v1beta/openai'
      end

      def headers
        {
          'Authorization' => "Bearer #{RubyLLM.config.gemini_api_key}"
        }
      end

      def capabilities
        Gemini::Capabilities
      end

      def slug
        'gemini'
      end
    end
  end
end
