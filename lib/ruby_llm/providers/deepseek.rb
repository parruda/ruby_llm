# frozen_string_literal: true

module RubyLLM
  module Providers
    # DeepSeek API integration.
    class DeepSeek < OpenAI
      private

      def api_base
        'https://api.deepseek.com'
      end

      def headers
        {
          'Authorization' => "Bearer #{RubyLLM.config.deepseek_api_key}"
        }
      end
    end
  end
end
