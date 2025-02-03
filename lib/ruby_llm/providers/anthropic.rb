# frozen_string_literal: true

module RubyLLM
  module Providers
    class Anthropic
      include Provider

      private

      def api_base
        'https://api.anthropic.com'
      end

      def headers
        {
          'x-api-key' => RubyLLM.config.anthropic_api_key,
          'anthropic-version' => '2023-06-01'
        }
      end

      def completion_url
        '/v1/messages'
      end

      def models_url
        '/v1/models'
      end

      def build_payload(messages, tools:, temperature:, model:, stream: false)
        {
          model: model,
          messages: format_messages(messages),
          temperature: temperature,
          stream: stream,
          max_tokens: RubyLLM.models.find(model).max_tokens
        }.tap do |payload|
          payload[:tools] = tools.values.map { |t| function_for(t) } if tools.any?
        end
      end

      def parse_completion_response(response)
        data = response.body
        content_blocks = data['content'] || []

        text_blocks = content_blocks.select { |c| c['type'] == 'text' }
        text_content = text_blocks.map { |c| c['text'] }.join('')

        tool_use = content_blocks.find { |c| c['type'] == 'tool_use' }

        if tool_use
          Message.new(
            role: :assistant,
            content: text_content,
            tool_calls: {
              tool_use['id'] => ToolCall.new(
                id: tool_use['id'],
                name: tool_use['name'],
                arguments: tool_use['input']
              )
            },
            input_tokens: data.dig('usage', 'input_tokens'),
            output_tokens: data.dig('usage', 'output_tokens'),
            model_id: data['model']
          )
        else
          Message.new(
            role: :assistant,
            content: text_content,
            input_tokens: data.dig('usage', 'input_tokens'),
            output_tokens: data.dig('usage', 'output_tokens'),
            model_id: data['model']
          )
        end
      end

      def parse_models_response(response)
        capabilities = ModelCapabilities::Anthropic.new

        (response.body['data'] || []).map do |model|
          ModelInfo.new(
            id: model['id'],
            created_at: Time.parse(model['created_at']),
            display_name: model['display_name'],
            provider: 'anthropic',
            metadata: { type: model['type'] },
            context_window: capabilities.determine_context_window(model['id']),
            max_tokens: capabilities.determine_max_tokens(model['id']),
            supports_vision: capabilities.supports_vision?(model['id']),
            supports_functions: capabilities.supports_functions?(model['id']),
            supports_json_mode: capabilities.supports_json_mode?(model['id']),
            input_price_per_million: capabilities.get_input_price(model['id']),
            output_price_per_million: capabilities.get_output_price(model['id'])
          )
        end
      end

      def handle_stream(&block)
        to_json_stream do |data|
          block.call(
            Chunk.new(
              role: :assistant,
              model_id: data.dig('message', 'model'),
              content: data.dig('delta', 'text'),
              input_tokens: data.dig('message', 'usage', 'input_tokens'),
              output_tokens: data.dig('message', 'usage', 'output_tokens') || data.dig('usage', 'output_tokens')
            )
          )
        end
      end

      def function_for(tool)
        {
          name: tool.name,
          description: tool.description,
          input_schema: {
            type: 'object',
            properties: clean_parameters(tool.parameters),
            required: required_parameters(tool.parameters)
          }
        }
      end

      def format_messages(messages)
        messages.map do |msg|
          if msg.tool_call?
            {
              role: 'assistant',
              content: [
                {
                  type: 'text',
                  text: msg.content
                },
                {
                  type: 'tool_use',
                  id: msg.tool_calls.values.first.id,
                  name: msg.tool_calls.values.first.name,
                  input: msg.tool_calls.values.first.arguments
                }
              ]
            }
          elsif msg.tool_result?
            {
              role: 'user',
              content: [
                {
                  type: 'tool_result',
                  tool_use_id: msg.tool_call_id,
                  content: msg.content
                }
              ]
            }
          else
            {
              role: convert_role(msg.role),
              content: msg.content
            }
          end
        end
      end

      def convert_role(role)
        case role
        when :tool then 'user'
        when :user then 'user'
        else 'assistant'
        end
      end

      def clean_parameters(parameters)
        parameters.transform_values do |param|
          {
            type: param.type,
            description: param.description
          }.compact
        end
      end

      def required_parameters(parameters)
        parameters.select { |_, param| param.required }.keys
      end
    end
  end
end
