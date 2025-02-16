# frozen_string_literal: true

module RubyLLM
  module Providers
    # Gemini API integration.
    class Gemini < OpenAI
      private

      def api_base
        'https://generativelanguage.googleapis.com/v1beta/openai'
      end

      def headers
        {
          'Authorization' => "Bearer #{RubyLLM.config.gemini_api_key}"
        }
      end

      def parse_list_models_response(response)
        response.body['data']&.each do |model|
          model['id'] = model['id'].delete_prefix('models/')
        end

        super(response)
      end
    end
  end
end
