# frozen_string_literal: true

module RubyLLM
  module ModelCapabilities
    module Anthropic
      extend self

      def determine_context_window(model_id)
        case model_id
        when /claude-3/ then 200_000
        else 100_000
        end
      end

      def determine_max_tokens(model_id)
        case model_id
        when /claude-3-5/ then 8_192
        else 4_096
        end
      end

      def get_input_price(model_id)
        PRICES.dig(model_family(model_id), :input) || default_input_price
      end

      def get_output_price(model_id)
        PRICES.dig(model_family(model_id), :output) || default_output_price
      end

      def supports_vision?(model_id)
        return false if model_id.match?(/claude-3-5-haiku/)
        return false if model_id.match?(/claude-[12]/)

        true
      end

      def supports_functions?(model_id)
        model_id.include?('claude-3')
      end

      def supports_json_mode?(model_id)
        model_id.include?('claude-3')
      end

      private

      def model_family(model_id)
        case model_id
        when /claude-3-5-sonnet/  then :claude35_sonnet
        when /claude-3-5-haiku/   then :claude35_haiku
        when /claude-3-opus/      then :claude3_opus
        when /claude-3-sonnet/    then :claude3_sonnet
        when /claude-3-haiku/     then :claude3_haiku
        else :claude2
        end
      end

      PRICES = {
        claude35_sonnet: { input: 3.0, output: 15.0 }, # $3.00/$15.00 per million tokens
        claude35_haiku: { input: 0.80, output: 4.0 }, # $0.80/$4.00 per million tokens
        claude3_opus: { input: 15.0, output: 75.0 }, # $15.00/$75.00 per million tokens
        claude3_sonnet: { input: 3.0, output: 15.0 }, # $3.00/$15.00 per million tokens
        claude3_haiku: { input: 0.25, output: 1.25 }, # $0.25/$1.25 per million tokens
        claude2: { input: 3.0,  output: 15.0 } # Default pricing for Claude 2.x models
      }.freeze

      def default_input_price
        3.0
      end

      def default_output_price
        15.0
      end
    end
  end
end
