# frozen_string_literal: true

module RubyLLM
  module Providers
    # Anthropic Claude API integration. Handles the complexities of
    # Claude's unique message format and tool calling conventions.
    class Anthropic # rubocop:disable Metrics/ClassLength
      include Provider

      def parse_error(response)
        return if response.body.empty?

        JSON.parse(response.body).dig('error', 'message')
      end

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

        text_content = extract_text_content(content_blocks)
        tool_use = find_tool_use(content_blocks)

        build_message(data, text_content, tool_use)
      end

      def extract_text_content(blocks)
        text_blocks = blocks.select { |c| c['type'] == 'text' }
        text_blocks.map { |c| c['text'] }.join('')
      end

      def find_tool_use(blocks)
        blocks.find { |c| c['type'] == 'tool_use' }
      end

      def build_message(data, content, tool_use)
        Message.new(
          role: :assistant,
          content: content,
          tool_calls: parse_tool_calls(tool_use),
          input_tokens: data.dig('usage', 'input_tokens'),
          output_tokens: data.dig('usage', 'output_tokens'),
          model_id: data['model']
        )
      end

      def parse_models_response(response) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
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

      def extract_model_id(data)
        data.dig('message', 'model')
      end

      def extract_input_tokens(data)
        data.dig('message', 'usage', 'input_tokens')
      end

      def extract_output_tokens(data)
        data.dig('message', 'usage', 'output_tokens') || data.dig('usage', 'output_tokens')
      end

      def extract_tool_calls(data)
        if json_delta?(data)
          { nil => ToolCall.new(id: nil, name: nil, arguments: data.dig('delta', 'partial_json')) }
        else
          parse_tool_calls(data['content_block'])
        end
      end

      def json_delta?(data)
        data['type'] == 'content_block_delta' && data.dig('delta', 'type') == 'input_json_delta'
      end

      def parse_tool_calls(content_block)
        return nil unless content_block && content_block['type'] == 'tool_use'

        {
          content_block['id'] => ToolCall.new(
            id: content_block['id'],
            name: content_block['name'],
            arguments: content_block['input']
          )
        }
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
        messages.map { |msg| format_message(msg) }
      end

      def format_message(msg)
        if msg.tool_call?
          format_tool_call(msg)
        elsif msg.tool_result?
          format_tool_result(msg)
        else
          format_basic_message(msg)
        end
      end

      def format_tool_call(msg)
        tool_call = msg.tool_calls.values.first

        {
          role: 'assistant',
          content: [
            format_text_block(msg.content),
            format_tool_use_block(tool_call)
          ]
        }
      end

      def format_tool_result(msg)
        {
          role: 'user',
          content: [format_tool_result_block(msg)]
        }
      end

      def format_basic_message(msg)
        {
          role: convert_role(msg.role),
          content: msg.content
        }
      end

      def format_text_block(content)
        {
          type: 'text',
          text: content
        }
      end

      def format_tool_use_block(tool_call)
        {
          type: 'tool_use',
          id: tool_call.id,
          name: tool_call.name,
          input: tool_call.arguments
        }
      end

      def format_tool_result_block(msg)
        {
          type: 'tool_result',
          tool_use_id: msg.tool_call_id,
          content: msg.content
        }
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
