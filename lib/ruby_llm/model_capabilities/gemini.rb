# frozen_string_literal: true

module RubyLLM
  module ModelCapabilities
    # Determines capabilities and pricing for Google Gemini models
    module Gemini # rubocop:disable Metrics/ModuleLength
      module_function

      def context_window_for(model_id)
        case model_id
        when /gemini-2\.0-flash/ then 1_048_576
        when /gemini-1\.5-pro/ then 2_097_152
        when /gemini-1\.5/ then 1_048_576
        when /text-embedding/, /embedding-001/ then 2_048
        else 32_768 # Sensible default for unknown models
        end
      end

      def max_tokens_for(model_id)
        case model_id
        when /gemini-2\.0-flash/, /gemini-1\.5/ then 8_192
        when /text-embedding/, /embedding-001/ then 768 # Output dimension size for embeddings
        when /aqa/ then 1_024
        else 4_096 # Sensible default
        end
      end

      def input_price_for(model_id)
        PRICES.dig(pricing_family(model_id), :input) || default_input_price
      end

      def output_price_for(model_id)
        PRICES.dig(pricing_family(model_id), :output) || default_output_price
      end

      def supports_vision?(model_id)
        return false if model_id.match?(/text-embedding|embedding-001|aqa/)
        return false if model_id.match?(/flash-lite/)
        return false if model_id.match?(/imagen/)

        # Only pro and regular flash models support vision
        model_id.match?(/gemini-[12]\.(?:5|0)-(?:pro|flash)(?!-lite)/)
      end

      def supports_functions?(model_id)
        return false if model_id.match?(/text-embedding|embedding-001|aqa/)
        return false if model_id.match?(/imagen/)
        return false if model_id.match?(/flash-lite/)
        return false if model_id.match?(/bison|gecko|evergreen/)

        # Currently only full models support function calling
        model_id.match?(/gemini-[12]\.(?:5|0)-(?:pro|flash)(?!-lite)/)
      end

      def supports_json_mode?(model_id)
        return false if model_id.match?(/text-embedding|embedding-001|aqa/)
        return false if model_id.match?(/imagen/)
        return false if model_id.match?(/flash-lite/)
        return false if model_id.match?(/bison|gecko|evergreen/)

        # Gemini 1.5+ models support JSON mode
        model_id.match?(/gemini-[12]\.(?:5|0)-(?:pro|flash)(?!-lite)/)
      end

      def format_display_name(model_id)
        return model_id unless model_id.start_with?('models/')

        model_id
          .delete_prefix('models/')
          .split('-')
          .map(&:capitalize)
          .join(' ')
          .gsub(/(\d+\.\d+)/, ' \1') # Add space before version numbers
          .gsub(/\s+/, ' ')          # Clean up multiple spaces
          .strip
      end

      def model_type(model_id)
        case model_id
        when /text-embedding|embedding/ then 'embedding'
        when /imagen/ then 'image'
        when /bison|text-bison/ then 'legacy'
        else 'chat'
        end
      end

      def model_family(model_id) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/MethodLength
        case model_id
        when /gemini-2\.0-flash-lite/ then 'gemini20_flash_lite'
        when /gemini-2\.0-flash/ then 'gemini20_flash'
        when /gemini-1\.5-flash-8b/ then 'gemini15_flash_8b'
        when /gemini-1\.5-flash/ then 'gemini15_flash'
        when /gemini-1\.5-pro/ then 'gemini15_pro'
        when /text-embedding-004/ then 'embedding4'
        when /embedding-001/ then 'embedding1'
        when /bison|text-bison/ then 'bison'
        when /imagen/ then 'imagen3'
        else 'other'
        end
      end

      def pricing_family(model_id)
        case model_id
        when /gemini-2\.0-flash-lite/ then :flash_lite_2 # rubocop:disable Naming/VariableNumber
        when /gemini-2\.0-flash/ then :flash_2 # rubocop:disable Naming/VariableNumber
        when /gemini-1\.5-flash-8b/ then :flash_8b
        when /gemini-1\.5-flash/ then :flash
        when /gemini-1\.5-pro/ then :pro
        when /text-embedding|embedding/ then :embedding
        else :base
        end
      end

      PRICES = {
        flash_2: { input: 0.10, output: 0.40 },       # Gemini 2.0 Flash # rubocop:disable Naming/VariableNumber
        flash_lite_2: { input: 0.075, output: 0.30 }, # Gemini 2.0 Flash Lite # rubocop:disable Naming/VariableNumber
        flash: { input: 0.075, output: 0.30 },        # Gemini 1.5 Flash basic pricing
        flash_8b: { input: 0.0375, output: 0.15 },    # Gemini 1.5 Flash 8B
        pro: { input: 1.25, output: 5.0 },            # Gemini 1.5 Pro
        embedding: { input: 0.00, output: 0.00 }      # Text Embedding models are free
      }.freeze

      def default_input_price
        0.075 # Default to Flash pricing
      end

      def default_output_price
        0.30  # Default to Flash pricing
      end
    end
  end
end
