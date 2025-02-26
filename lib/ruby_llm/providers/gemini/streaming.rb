# frozen_string_literal: true

module RubyLLM
  module Providers
    module Gemini
      # Streaming methods for the Gemini API implementation
      module Streaming
        # Need to make stream_completion public for chat.rb to access
        def stream_completion(model, payload, &block) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
          url = "models/#{model}:streamGenerateContent?alt=sse"
          accumulator = StreamAccumulator.new

          post(url, payload) do |req|
            req.options.on_data = stream_handler(accumulator, &block)
          end

          # If this is a tool call, immediately execute it and include the result
          message = accumulator.to_message
          if message.tool_call? && message.content.to_s.empty? && @tools && !@tools.empty?
            tool_call = message.tool_calls.values.first
            tool = @tools[tool_call.name.to_sym]

            if tool
              tool_result = tool.call(tool_call.arguments)
              # Create a new chunk with the result
              result_chunk = Chunk.new(
                role: :assistant,
                content: "The result is #{tool_result}",
                model_id: message.model_id,
                input_tokens: message.input_tokens,
                output_tokens: message.output_tokens,
                tool_calls: message.tool_calls
              )

              # Add to accumulator and call the block
              accumulator.add(result_chunk)
              block.call(result_chunk)
            end
          end

          accumulator.to_message
        end

        private

        # Handle streaming
        def stream_handler(accumulator, &block) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
          to_json_stream do |data| # rubocop:disable Metrics/BlockLength
            next unless data['candidates']&.any?

            candidate = data['candidates'][0]
            parts = candidate.dig('content', 'parts')
            model_id = data['modelVersion']

            # First attempt to extract tool calls
            tool_calls = nil

            # Check if any part contains a functionCall
            if parts&.any? { |p| p['functionCall'] }
              function_part = parts.find { |p| p['functionCall'] }
              function_data = function_part['functionCall']

              if function_data && function_data['name']
                # Create a tool call with proper structure - convert args to JSON string
                id = SecureRandom.uuid
                tool_calls = {
                  id => ToolCall.new(
                    id: id,
                    name: function_data['name'],
                    arguments: JSON.generate(function_data['args']) # Convert Hash to JSON string
                  )
                }
              end
            end

            # Extract text content (if any)
            text = nil
            if parts
              text_parts = parts.select { |p| p['text'] }
              text = text_parts.map { |p| p['text'] }.join if text_parts.any?
            end

            chunk = Chunk.new(
              role: :assistant,
              content: text,
              model_id: model_id,
              input_tokens: data.dig('usageMetadata', 'promptTokenCount'),
              output_tokens: data.dig('usageMetadata', 'candidatesTokenCount'),
              tool_calls: tool_calls
            )

            accumulator.add(chunk)
            block.call(chunk)
          end
        end
      end
    end
  end
end
