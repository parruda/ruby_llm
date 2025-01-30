# frozen_string_literal: true

module RubyLLM
  module ModelCapabilities
    # Implements model capabilities for OpenAI's GPT models
    class OpenAI < Base
      def determine_context_window(model_id)
        case model_id
        when /gpt-4o/, /o1/, /gpt-4-turbo/
          128_000
        when /gpt-4-0[0-9]{3}/
          8_192
        when /gpt-3.5-turbo-instruct/
          4_096
        when /gpt-3.5/
          16_385
        else
          4_096
        end
      end

      def determine_max_tokens(model_id)
        case model_id
        when /o1-2024-12-17/
          100_000
        when /o1-mini-2024-09-12/
          65_536
        when /o1-preview-2024-09-12/
          32_768
        when /gpt-4o/, /gpt-4-turbo/
          16_384
        when /gpt-4-0[0-9]{3}/
          8_192
        when /gpt-3.5-turbo/
          4_096
        else
          4_096
        end
      end

      def get_input_price(model_id)
        case model_id
        when /o1-2024/
          15.0    # $15.00 per million tokens
        when /o1-mini/
          3.0     # $3.00 per million tokens
        when /gpt-4o-realtime-preview/
          5.0     # $5.00 per million tokens
        when /gpt-4o-mini-realtime-preview/
          0.60    # $0.60 per million tokens
        when /gpt-4o-mini/
          0.15    # $0.15 per million tokens
        when /gpt-4o/
          2.50    # $2.50 per million tokens
        when /gpt-4-turbo/
          10.0    # $10.00 per million tokens
        when /gpt-3.5/
          0.50    # $0.50 per million tokens
        else
          0.50    # Default to GPT-3.5 pricing
        end
      end

      def get_output_price(model_id)
        case model_id
        when /o1-2024/
          60.0    # $60.00 per million tokens
        when /o1-mini/
          12.0    # $12.00 per million tokens
        when /gpt-4o-realtime-preview/
          20.0    # $20.00 per million tokens
        when /gpt-4o-mini-realtime-preview/
          2.40    # $2.40 per million tokens
        when /gpt-4o-mini/
          0.60    # $0.60 per million tokens
        when /gpt-4o/
          10.0    # $10.00 per million tokens
        when /gpt-4-turbo/
          30.0    # $30.00 per million tokens
        when /gpt-3.5/
          1.50    # $1.50 per million tokens
        else
          1.50    # Default to GPT-3.5 pricing
        end
      end

      def supports_functions?(model_id)
        !model_id.include?('instruct')
      end

      def supports_vision?(model_id)
        model_id.include?('vision') || model_id.match?(/gpt-4-(?!0314|0613)/)
      end

      def supports_json_mode?(model_id)
        model_id.match?(/gpt-4-\d{4}-preview/) ||
          model_id.include?('turbo') ||
          model_id.match?(/gpt-3.5-turbo-(?!0301|0613)/)
      end

      def format_display_name(model_id)
        # First replace hyphens with spaces
        name = model_id.tr('-', ' ')

        # Capitalize each word
        name = name.split(' ').map(&:capitalize).join(' ')

        # Apply specific formatting rules
        name.gsub(/(\d{4}) (\d{2}) (\d{2})/, '\1\2\3') # Convert dates to YYYYMMDD
            .gsub(/^Gpt /, 'GPT-')
            .gsub(/^O1 /, 'O1-')
            .gsub(/^Chatgpt /, 'ChatGPT-')
            .gsub(/^Tts /, 'TTS-')
            .gsub(/^Dall E /, 'DALL-E-')
            .gsub(/3\.5 /, '3.5-')
            .gsub(/4 /, '4-')
            .gsub(/4o (?=Mini|Preview|Turbo)/, '4o-')
            .gsub(/\bHd\b/, 'HD')
      end
    end
  end
end
