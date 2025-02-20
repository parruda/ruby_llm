# frozen_string_literal: true

module RubyLLM
  module Providers
    module Gemini
      # Determines capabilities and pricing for Google Gemini models
      module Capabilities # rubocop:disable Metrics/ModuleLength
        module_function

        def context_window_for(model_id)
          case model_id
          when /gemini-2\.0-flash/, /gemini-1\.5-flash/ then 1_048_576
          when /gemini-1\.5-pro/ then 2_097_152
          when /text-embedding/, /embedding-001/ then 2_048
          when /aqa/ then 7_168
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
          base_price = PRICES.dig(pricing_family(model_id), :input) || default_input_price
          return base_price unless long_context_model?(model_id)

          # Double the price for prompts longer than 128k tokens
          context_length(model_id) > 128_000 ? base_price * 2 : base_price
        end

        def output_price_for(model_id)
          base_price = PRICES.dig(pricing_family(model_id), :output) || default_output_price
          return base_price unless long_context_model?(model_id)

          # Double the price for prompts longer than 128k tokens
          context_length(model_id) > 128_000 ? base_price * 2 : base_price
        end

        def supports_vision?(model_id)
          return false if model_id.match?(/text-embedding|embedding-001|aqa/)
          return false if model_id.match?(/gemini-1\.0/)

          model_id.match?(/gemini-[12]\.[05]/)
        end

        def supports_functions?(model_id)
          return false if model_id.match?(/text-embedding|embedding-001|aqa/)
          return false if model_id.match?(/flash-lite/)
          return false if model_id.match?(/gemini-1\.0/)

          model_id.match?(/gemini-[12]\.[05]-(?:pro|flash)(?!-lite)/)
        end

        def supports_json_mode?(model_id)
          return false if model_id.match?(/text-embedding|embedding-001|aqa/)
          return false if model_id.match?(/gemini-1\.0/)

          model_id.match?(/gemini-\d/)
        end

        def format_display_name(model_id)
          model_id
            .delete_prefix('models/')
            .split('-')
            .map(&:capitalize)
            .join(' ')
            .gsub(/(\d+\.\d+)/, ' \1') # Add space before version numbers
            .gsub(/\s+/, ' ')          # Clean up multiple spaces
            .gsub(/Aqa/, 'AQA')        # Special case for AQA
            .strip
        end

        def supports_caching?(model_id)
          return false if model_id.match?(/flash-lite|gemini-1\.0/)

          model_id.match?(/gemini-[12]\.[05]/)
        end

        def supports_tuning?(model_id)
          model_id.match?(/gemini-1\.5-flash/)
        end

        def supports_audio?(model_id)
          model_id.match?(/gemini-[12]\.[05]/)
        end

        def model_type(model_id)
          case model_id
          when /text-embedding|embedding/ then 'embedding'
          when /imagen/ then 'image'
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
          when /gemini-1\.0-pro/ then 'gemini10_pro'
          when /text-embedding-004/ then 'embedding4'
          when /embedding-001/ then 'embedding1'
          when /aqa/ then 'aqa'
          else 'other'
          end
        end

        def pricing_family(model_id) # rubocop:disable Metrics/CyclomaticComplexity
          case model_id
          when /gemini-2\.0-flash-lite/ then :flash_lite_2 # rubocop:disable Naming/VariableNumber
          when /gemini-2\.0-flash/ then :flash_2 # rubocop:disable Naming/VariableNumber
          when /gemini-1\.5-flash-8b/ then :flash_8b
          when /gemini-1\.5-flash/ then :flash
          when /gemini-1\.5-pro/ then :pro
          when /gemini-1\.0-pro/ then :pro_1_0 # rubocop:disable Naming/VariableNumber
          when /text-embedding|embedding/ then :embedding
          else :base
          end
        end

        private

        def long_context_model?(model_id)
          model_id.match?(/gemini-1\.5-(?:pro|flash)/)
        end

        def context_length(model_id)
          context_window_for(model_id)
        end

        PRICES = {
          flash_2: { # Gemini 2.0 Flash # rubocop:disable Naming/VariableNumber
            input: 0.10,
            output: 0.40,
            audio_input: 0.70,
            cache: 0.025,
            cache_storage: 1.00
          },
          flash_lite_2: { # Gemini 2.0 Flash Lite # rubocop:disable Naming/VariableNumber
            input: 0.075,
            output: 0.30,
            cache: 0.01875,
            cache_storage: 1.00
          },
          flash: { # Gemini 1.5 Flash
            input: 0.075,
            output: 0.30,
            cache: 0.01875,
            cache_storage: 1.00
          },
          flash_8b: { # Gemini 1.5 Flash 8B
            input: 0.0375,
            output: 0.15,
            cache: 0.01,
            cache_storage: 0.25
          },
          pro: { # Gemini 1.5 Pro
            input: 1.25,
            output: 5.0,
            cache: 0.3125,
            cache_storage: 4.50
          },
          pro_1_0: { # Gemini 1.0 Pro # rubocop:disable Naming/VariableNumber
            input: 0.50,
            output: 1.50
          },
          embedding: { # Text Embedding models
            input: 0.00,
            output: 0.00
          }
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
end
