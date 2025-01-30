# frozen_string_literal: true

module RubyLLM
  module ModelCapabilities
    class Anthropic < Base
      def determine_context_window(model_id)
        case model_id
        when /claude-3-5-sonnet/, /claude-3-5-haiku/,
             /claude-3-opus/, /claude-3-sonnet/, /claude-3-haiku/
          200_000
        else
          100_000
        end
      end

      def determine_max_tokens(model_id)
        case model_id
        when /claude-3-5-sonnet/, /claude-3-5-haiku/
          8_192
        when /claude-3-opus/, /claude-3-sonnet/, /claude-3-haiku/
          4_096
        else
          4_096
        end
      end

      def get_input_price(model_id)
        case model_id
        when /claude-3-5-sonnet/
          3.0     # $3.00 per million tokens
        when /claude-3-5-haiku/
          0.80    # $0.80 per million tokens
        when /claude-3-opus/
          15.0    # $15.00 per million tokens
        when /claude-3-sonnet/
          3.0     # $3.00 per million tokens
        when /claude-3-haiku/
          0.25    # $0.25 per million tokens
        else
          3.0
        end
      end

      def get_output_price(model_id)
        case model_id
        when /claude-3-5-sonnet/
          15.0    # $15.00 per million tokens
        when /claude-3-5-haiku/
          4.0     # $4.00 per million tokens
        when /claude-3-opus/
          75.0    # $75.00 per million tokens
        when /claude-3-sonnet/
          15.0    # $15.00 per million tokens
        when /claude-3-haiku/
          1.25    # $1.25 per million tokens
        else
          15.0
        end
      end

      def supports_vision?(model_id)
        case model_id
        when /claude-3-5-haiku/
          false
        when /claude-2/, /claude-1/
          false
        else
          true
        end
      end

      def supports_functions?(model_id)
        model_id.include?('claude-3')
      end

      def supports_json_mode?(model_id)
        model_id.include?('claude-3')
      end
    end
  end
end
