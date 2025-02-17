# frozen_string_literal: true

module RubyLLM
  module ModelCapabilities
    # Determines capabilities and pricing for DeepSeek models
    module DeepSeek
      module_function

      # Returns the context window size for the given model
      # @param model_id [String] the model identifier
      # @return [Integer] the context window size in tokens
      def context_window_for(model_id)
        case model_id
        when /deepseek-(?:chat|reasoner)/ then 64_000
        else 32_768 # Sensible default
        end
      end

      # Returns the maximum output tokens for the given model
      # @param model_id [String] the model identifier
      # @return [Integer] the maximum output tokens
      def max_tokens_for(model_id)
        case model_id
        when /deepseek-(?:chat|reasoner)/ then 8_192
        else 4_096 # Default if max_tokens not specified
        end
      end

      # Returns the input price per million tokens for the given model
      # @param model_id [String] the model identifier
      # @return [Float] the price per million tokens
      def input_price_for(model_id)
        PRICES.dig(model_family(model_id), :input_miss) || default_input_price
      end

      # Returns the output price per million tokens for the given model
      # @param model_id [String] the model identifier
      # @return [Float] the price per million tokens
      def output_price_for(model_id)
        PRICES.dig(model_family(model_id), :output) || default_output_price
      end

      # Returns the cache hit price per million tokens for the given model
      # @param model_id [String] the model identifier
      # @return [Float] the price per million tokens
      def cache_hit_price_for(model_id)
        PRICES.dig(model_family(model_id), :input_hit) || default_cache_hit_price
      end

      # Determines if the model supports vision capabilities
      # @param model_id [String] the model identifier
      # @return [Boolean] true if the model supports vision
      def supports_vision?(_model_id)
        false # DeepSeek models don't currently support vision
      end

      # Determines if the model supports function calling
      # @param model_id [String] the model identifier
      # @return [Boolean] true if the model supports function calling
      def supports_functions?(model_id)
        model_id.match?(/deepseek-chat/) # Only deepseek-chat supports function calling
      end

      # Determines if the model supports JSON mode
      # @param model_id [String] the model identifier
      # @return [Boolean] true if the model supports JSON mode
      def supports_json_mode?(model_id)
        model_id.match?(/deepseek-chat/) # Only deepseek-chat supports JSON mode
      end

      # Formats the model ID into a display name
      # @param model_id [String] the model identifier
      # @return [String] the formatted display name
      def format_display_name(model_id)
        case model_id
        when 'deepseek-chat' then 'DeepSeek V3'
        when 'deepseek-reasoner' then 'DeepSeek R1'
        else
          model_id.split('-')
                  .map(&:capitalize)
                  .join(' ')
        end
      end

      # Returns the model type
      # @param model_id [String] the model identifier
      # @return [String] the model type
      def model_type(_model_id)
        'chat' # All DeepSeek models are chat models
      end

      # Returns the model family for pricing purposes
      # @param model_id [String] the model identifier
      # @return [String] the model family identifier
      def model_family(model_id)
        case model_id
        when /deepseek-chat/ then :chat
        when /deepseek-reasoner/ then :reasoner
        else :chat # Default to chat family
        end
      end

      # Pricing information for DeepSeek models (USD per 1M tokens)
      PRICES = {
        chat: {
          input_hit: 0.07,   # $0.07 per million tokens on cache hit
          input_miss: 0.27,  # $0.27 per million tokens on cache miss
          output: 1.10       # $1.10 per million tokens output
        },
        reasoner: {
          input_hit: 0.14,   # $0.14 per million tokens on cache hit
          input_miss: 0.55,  # $0.55 per million tokens on cache miss
          output: 2.19       # $2.19 per million tokens output
        }
      }.freeze

      private

      def default_input_price
        0.27 # Default to chat cache miss price
      end

      def default_output_price
        1.10 # Default to chat output price
      end

      def default_cache_hit_price
        0.07 # Default to chat cache hit price
      end
    end
  end
end
