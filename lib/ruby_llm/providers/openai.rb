# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAI
      include Provider

      private

      def api_base
        'https://api.openai.com'
      end

      def headers
        {
          'Authorization' => "Bearer #{RubyLLM.config.openai_api_key}"
        }
      end

      def completion_url
        '/v1/chat/completions'
      end

      def models_url
        '/v1/models'
      end

      def build_payload(messages, tools, model:, temperature: 0.7, stream: false)
        {
          model: model,
          messages: format_messages(messages),
          temperature: temperature,
          stream: stream
        }.tap do |payload|
          if tools.any?
            payload[:tools] = tools.map { |t| tool_for(t) }
            payload[:tool_choice] = 'auto'
          end
        end
      end

      def format_messages(messages)
        messages.map do |msg|
          {
            role: msg.role.to_s,
            content: msg.content,
            tool_calls: format_tool_calls(msg.tool_calls)
          }.compact
        end
      end

      def format_tool_calls(tool_calls)
        return nil unless tool_calls

        tool_calls.map do |tc|
          {
            id: tc[:id],
            type: 'function',
            function: {
              name: tc[:name],
              arguments: tc[:arguments]
            }
          }
        end
      end

      def tool_for(tool)
        {
          type: 'function',
          function: {
            name: tool.name,
            description: tool.description,
            parameters: {
              type: 'object',
              properties: tool.parameters.transform_values { |param| param_schema(param) },
              required: tool.parameters.select { |_, p| p.required }.keys
            }
          }
        }
      end

      def param_schema(param)
        {
          type: param.type,
          description: param.description
        }.compact
      end

      def parse_completion_response(response)
        data = response.body
        return if data.empty?

        message_data = data.dig('choices', 0, 'message')
        return unless message_data

        Message.new(
          role: :assistant,
          content: message_data['content'],
          tool_calls: parse_tool_calls(message_data['tool_calls']),
          input_tokens: data['usage']['prompt_tokens'],
          output_tokens: data['usage']['completion_tokens'],
          model_id: data['model']
        )
      end

      def parse_tool_calls(tool_calls)
        return nil unless tool_calls&.any?

        tool_calls.map do |tc|
          {
            id: tc['id'],
            name: tc.dig('function', 'name'),
            arguments: tc.dig('function', 'arguments')
          }
        end
      end

      def parse_models_response(response)
        (response.body['data'] || []).map do |model|
          model_info = begin
            Models.find(model['id'])
          rescue StandardError
            nil
          end
          next unless model_info

          model_info.tap do |info|
            info.metadata.merge!(
              object: model['object'],
              owned_by: model['owned_by']
            )
          end
        end.compact
      end

      def handle_stream(&block)
        to_json_stream do |data|
          block.call(
            Chunk.new(
              role: :assistant,
              model_id: data['model'],
              content: data.dig('choices', 0, 'delta', 'content')
            )
          )
        end
      end

      def parse_list_models_response(response)
        capabilities = ModelCapabilities::OpenAI
        (response.body['data'] || []).map do |model|
          ModelInfo.new(
            id: model['id'],
            created_at: Time.at(model['created']),
            display_name: capabilities.format_display_name(model['id']),
            provider: 'openai',
            metadata: {
              object: model['object'],
              owned_by: model['owned_by']
            },
            context_window: capabilities.context_window_for(model['id']),
            max_tokens: capabilities.max_tokens_for(model['id']),
            supports_vision: capabilities.supports_vision?(model['id']),
            supports_functions: capabilities.supports_functions?(model['id']),
            supports_json_mode: capabilities.supports_json_mode?(model['id']),
            input_price_per_million: capabilities.input_price_for(model['id']),
            output_price_per_million: capabilities.output_price_for(model['id'])
          )
        end
      end
    end
  end
end
