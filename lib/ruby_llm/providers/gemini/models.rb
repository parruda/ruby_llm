# frozen_string_literal: true

module RubyLLM
  module Providers
    module Gemini
      # Models methods of the Gemini API integration
      module Models
        module_function

        def parse_list_models_response(response, slug, capabilities)
          response.body['data']&.each do |model|
            model['id'] = model['id'].delete_prefix('models/')
          end

          OpenAI::Models.parse_list_models_response(response, slug, capabilities)
        end
      end
    end
  end
end
