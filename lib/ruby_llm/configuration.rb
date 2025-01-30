# frozen_string_literal: true

module RubyLLM
  # Configuration class for RubyLLM settings
  class Configuration
    attr_accessor :openai_api_key, :anthropic_api_key, :default_provider, :default_model, :request_timeout

    def initialize
      @request_timeout = 30
      @default_provider = :openai
      @default_model = 'gpt-3.5-turbo'
    end

    def provider_settings
      @provider_settings ||= {
        openai: ProviderSettings.new,
        anthropic: ProviderSettings.new
      }
    end
  end

  # Settings specific to individual LLM providers
  class ProviderSettings
    attr_accessor :api_key, :api_version, :default_model, :base_url
  end
end
