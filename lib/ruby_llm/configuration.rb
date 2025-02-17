# frozen_string_literal: true

module RubyLLM
  # Global configuration for RubyLLM. Manages API keys, default models,
  # and provider-specific settings.
  #
  # Configure via:
  #   RubyLLM.configure do |config|
  #     config.openai_api_key = ENV['OPENAI_API_KEY']
  #     config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
  #   end
  class Configuration
    attr_accessor :openai_api_key,
                  :anthropic_api_key,
                  :gemini_api_key,
                  :deepseek_api_key,
                  :default_model,
                  :default_embedding_model,
                  :request_timeout

    def initialize
      @request_timeout = 120
      @default_model = 'gpt-4o-mini'
      @default_embedding_model = 'text-embedding-3-small'
    end
  end
end
