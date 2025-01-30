# frozen_string_literal: true

module RubyLLM
  class ModelInfo
    attr_reader :id, :created_at, :display_name, :provider, :metadata,
                :context_window, :max_tokens, :supports_vision, :supports_functions,
                :supports_json_mode, :input_price_per_million, :output_price_per_million

    def initialize(id:, created_at:, display_name:, provider:, context_window:, max_tokens:, supports_vision:,
                   supports_functions:, supports_json_mode:, input_price_per_million:, output_price_per_million:, metadata: {})
      @id = id
      @created_at = created_at
      @display_name = display_name
      @provider = provider
      @metadata = metadata
      @context_window = context_window
      @max_tokens = max_tokens
      @supports_vision = supports_vision
      @supports_functions = supports_functions
      @supports_json_mode = supports_json_mode
      @input_price_per_million = input_price_per_million
      @output_price_per_million = output_price_per_million
    end

    def to_h
      {
        id: id,
        created_at: created_at,
        display_name: display_name,
        provider: provider,
        metadata: metadata,
        context_window: context_window,
        max_tokens: max_tokens,
        supports_vision: supports_vision,
        supports_functions: supports_functions,
        supports_json_mode: supports_json_mode,
        input_price_per_million: input_price_per_million,
        output_price_per_million: output_price_per_million
      }
    end
  end
end
