# frozen_string_literal: true

module RubyLLM
  module ModelCapabilities
    module OpenAI
      extend self

      def context_window_for(model_id)
        case model_id
        when /gpt-4o/, /o1/, /gpt-4-turbo/ then 128_000
        when /gpt-4-0[0-9]{3}/            then 8_192
        when /gpt-3.5-turbo-instruct/     then 4_096
        when /gpt-3.5/                    then 16_385
        else                                   4_096
        end
      end

      def max_tokens_for(model_id)
        case model_id
        when /o1-2024-12-17/              then 100_000
        when /o1-mini-2024-09-12/         then 65_536
        when /o1-preview-2024-09-12/      then 32_768
        when /gpt-4o/, /gpt-4-turbo/      then 16_384
        when /gpt-4-0[0-9]{3}/           then 8_192
        when /gpt-3.5-turbo/             then 4_096
        else                                  4_096
        end
      end

      def input_price_for(model_id)
        PRICES.dig(model_family(model_id), :input) || default_input_price
      end

      def output_price_for(model_id)
        PRICES.dig(model_family(model_id), :output) || default_output_price
      end

      def supports_vision?(model_id)
        model_id.include?('vision') || model_id.match?(/gpt-4-(?!0314|0613)/)
      end

      def supports_functions?(model_id)
        !model_id.include?('instruct')
      end

      def supports_json_mode?(model_id)
        model_id.match?(/gpt-4-\d{4}-preview/) ||
          model_id.include?('turbo') ||
          model_id.match?(/gpt-3.5-turbo-(?!0301|0613)/)
      end

      def format_display_name(model_id)
        model_id.then { |id| humanize(id) }
                .then { |name| apply_special_formatting(name) }
      end

      private

      def model_family(model_id)
        case model_id
        when /o1-2024/                   then :o1
        when /o1-mini/                   then :o1_mini
        when /gpt-4o-realtime-preview/   then :gpt4o_realtime
        when /gpt-4o-mini-realtime/      then :gpt4o_mini_realtime
        when /gpt-4o-mini/               then :gpt4o_mini
        when /gpt-4o/                    then :gpt4o
        when /gpt-4-turbo/               then :gpt4_turbo
        when /gpt-3.5/                   then :gpt35
        else :gpt35
        end
      end

      PRICES = {
        o1: { input: 15.0, output: 60.0 },
        o1_mini: { input: 3.0, output: 12.0 },
        gpt4o_realtime: { input: 5.0, output: 20.0 },
        gpt4o_mini_realtime: { input: 0.60, output: 2.40 },
        gpt4o_mini: { input: 0.15, output: 0.60 },
        gpt4o: { input: 2.50, output: 10.0 },
        gpt4_turbo: { input: 10.0, output: 30.0 },
        gpt35: { input: 0.50, output: 1.50 }
      }.freeze

      def default_input_price
        0.50
      end

      def default_output_price
        1.50
      end

      def humanize(id)
        id.tr('-', ' ')
          .split(' ')
          .map(&:capitalize)
          .join(' ')
      end

      def apply_special_formatting(name)
        name
          .gsub(/(\d{4}) (\d{2}) (\d{2})/, '\1\2\3')
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
