# frozen_string_literal: true

module RubyLLM
  module Providers
    module OpenAI
      # Determines capabilities and pricing for OpenAI models
      module Capabilities # rubocop:disable Metrics/ModuleLength
        module_function

        def context_window_for(model_id)
          case model_id
          when /o[13]-mini/, /o3-mini-2025/         then 200_000
          when /o1-2024/                            then 200_000
          when /gpt-4o/, /gpt-4-turbo/             then 128_000
          when /gpt-4-0[0-9]{3}/                   then 8_192
          when /gpt-3.5-turbo-instruct/            then 4_096
          when /gpt-3.5/                           then 16_385
          else 4_096
          end
        end

        def max_tokens_for(model_id) # rubocop:disable Metrics/CyclomaticComplexity
          case model_id
          when /o1-2024/, /o3-mini/                then 100_000
          when /o1-mini-2024/                      then 65_536
          when /gpt-4o-2024-05-13/                then 4_096
          when /gpt-4o/, /gpt-4o-mini/            then 16_384
          when /gpt-4o-realtime/                  then 4_096
          when /gpt-4-0[0-9]{3}/                  then 8_192
          when /gpt-3.5-turbo/                    then 4_096
          else 4_096
          end
        end

        def input_price_for(model_id)
          PRICES.dig(model_family(model_id), :input) || default_input_price
        end

        def output_price_for(model_id)
          PRICES.dig(model_family(model_id), :output) || default_output_price
        end

        def supports_vision?(model_id)
          model_id.match?(/gpt-4o|o1/) || model_id.match?(/gpt-4-(?!0314|0613)/)
        end

        def supports_functions?(model_id)
          !model_id.include?('instruct')
        end

        def supports_audio?(model_id)
          model_id.match?(/audio-preview|realtime-preview|whisper|tts/)
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

        def model_type(model_id)
          case model_id
          when /text-embedding|embedding/ then 'embedding'
          when /dall-e/ then 'image'
          when /tts|whisper/ then 'audio'
          when /omni-moderation/ then 'moderation'
          else 'chat'
          end
        end

        def supports_structured_output?(model_id)
          model_id.match?(/gpt-4o|o[13]-mini|o1/)
        end

        def model_family(model_id) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength
          case model_id
          when /o3-mini/ then 'o3_mini'
          when /o1-mini/ then 'o1_mini'
          when /o1/ then 'o1'
          when /gpt-4o-audio/ then 'gpt4o_audio'
          when /gpt-4o-realtime/ then 'gpt4o_realtime'
          when /gpt-4o-mini-audio/ then 'gpt4o_mini_audio'
          when /gpt-4o-mini-realtime/ then 'gpt4o_mini_realtime'
          when /gpt-4o-mini/ then 'gpt4o_mini'
          when /gpt-4o/ then 'gpt4o'
          when /gpt-4-turbo/ then 'gpt4_turbo'
          when /gpt-4/ then 'gpt4'
          when /gpt-3.5-turbo-instruct/ then 'gpt35_instruct'
          when /gpt-3.5/ then 'gpt35'
          when /dall-e-3/ then 'dalle3'
          when /dall-e-2/ then 'dalle2'
          when /text-embedding-3-large/ then 'embedding3_large'
          when /text-embedding-3-small/ then 'embedding3_small'
          when /text-embedding-ada/ then 'embedding2'
          when /tts-1-hd/ then 'tts1_hd'
          when /tts-1/ then 'tts1'
          when /whisper/ then 'whisper1'
          when /omni-moderation/ then 'moderation'
          when /babbage/ then 'babbage'
          when /davinci/ then 'davinci'
          else 'other'
          end
        end

        private

        PRICES = {
          o1: { input: 15.0, cached_input: 7.5, output: 60.0 },
          o1_mini: { input: 1.10, cached_input: 0.55, output: 4.40 },
          o3_mini: { input: 1.10, cached_input: 0.55, output: 4.40 },
          gpt4o: { input: 2.50, cached_input: 1.25, output: 10.0 },
          gpt4o_audio: {
            text_input: 2.50,
            audio_input: 40.0,
            text_output: 10.0,
            audio_output: 80.0
          },
          gpt4o_realtime: {
            text_input: 5.0,
            cached_text_input: 2.50,
            audio_input: 40.0,
            cached_audio_input: 2.50,
            text_output: 20.0,
            audio_output: 80.0
          },
          gpt4o_mini: { input: 0.15, cached_input: 0.075, output: 0.60 },
          gpt4o_mini_audio: {
            text_input: 0.15,
            audio_input: 10.0,
            text_output: 0.60,
            audio_output: 20.0
          },
          gpt4o_mini_realtime: {
            text_input: 0.60,
            cached_text_input: 0.30,
            audio_input: 10.0,
            cached_audio_input: 0.30,
            text_output: 2.40,
            audio_output: 20.0
          },
          gpt4_turbo: { input: 10.0, output: 30.0 },
          gpt4: { input: 30.0, output: 60.0 },
          gpt35: { input: 0.50, output: 1.50 },
          gpt35_instruct: { input: 1.50, output: 2.0 },
          embedding3_large: { price: 0.13 },
          embedding3_small: { price: 0.02 },
          embedding2: { price: 0.10 },
          davinci: { input: 2.0, output: 2.0 },
          babbage: { input: 0.40, output: 0.40 },
          tts1: { price: 15.0 },
          tts1_hd: { price: 30.0 },
          whisper1: { price: 0.006 }
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

        def apply_special_formatting(name) # rubocop:disable Metrics/MethodLength
          name
            .gsub(/(\d{4}) (\d{2}) (\d{2})/, '\1\2\3')
            .gsub(/^Gpt /, 'GPT-')
            .gsub(/^O([13]) /, 'O\1-')
            .gsub(/^Chatgpt /, 'ChatGPT-')
            .gsub(/^Tts /, 'TTS-')
            .gsub(/^Dall E /, 'DALL-E-')
            .gsub(/3\.5 /, '3.5-')
            .gsub(/4 /, '4-')
            .gsub(/4o (?=Mini|Preview|Turbo|Audio)/, '4o-')
            .gsub(/\bHd\b/, 'HD')
        end
      end
    end
  end
end
