# frozen_string_literal: true

module RubyLLM
  module Providers
    module Anthropic
      # Streaming methods of the Anthropic API integration
      module Streaming
        private

        def stream_url
          completion_url
        end

        def handle_stream(&block)
          to_json_stream do |data|
            block.call(build_chunk(data))
          end
        end

        def build_chunk(data)
          Chunk.new(
            role: :assistant,
            model_id: extract_model_id(data),
            content: data.dig('delta', 'text'),
            input_tokens: extract_input_tokens(data),
            output_tokens: extract_output_tokens(data),
            tool_calls: extract_tool_calls(data)
          )
        end

        def json_delta?(data)
          data['type'] == 'content_block_delta' && data.dig('delta', 'type') == 'input_json_delta'
        end
      end
    end
  end
end
