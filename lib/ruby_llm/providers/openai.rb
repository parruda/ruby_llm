# frozen_string_literal: true

module RubyLLM
  module Providers
    # OpenAI API integration. Handles chat completion, function calling,
    # and OpenAI's unique streaming format. Supports GPT-4, GPT-3.5,
    # and other OpenAI models.
    class OpenAI # rubocop:disable Metrics/ClassLength
      include Provider

      def parse_error(response)
        JSON.parse(response.body).dig('error', 'message')
      end

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

      def embedding_url
        '/v1/embeddings'
      end

      def build_payload(messages, tools:, temperature:, model:, stream: false) # rubocop:disable Metrics/MethodLength
        {
          model: model,
          messages: format_messages(messages),
          temperature: temperature,
          stream: stream
        }.tap do |payload|
          if tools.any?
            payload[:tools] = tools.map { |_, tool| tool_for(tool) }
            payload[:tool_choice] = 'auto'
          end
          payload[:stream_options] = { include_usage: true } if stream
        end
      end

      def format_messages(messages)
        messages.map do |msg|
          {
            role: format_role(msg.role),
            content: msg.content,
            tool_calls: format_tool_calls(msg.tool_calls),
            tool_call_id: msg.tool_call_id
          }.compact
        end
      end

      def format_role(role)
        case role
        when :system
          'developer'
        else
          role.to_s
        end
      end

      def build_embedding_payload(text, model:)
        {
          model: model,
          input: text
        }
      end

      def parse_embedding_response(response)
        embeddings = response.body['data'].map { |d| d['embedding'] }
        embeddings.size == 1 ? embeddings.first : embeddings
      end

      def format_tool_calls(tool_calls) # rubocop:disable Metrics/MethodLength
        return nil unless tool_calls&.any?

        tool_calls.map do |_, tc|
          {
            id: tc.id,
            type: 'function',
            function: {
              name: tc.name,
              arguments: JSON.generate(tc.arguments)
            }
          }
        end
      end

      def tool_for(tool) # rubocop:disable Metrics/MethodLength
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

      def parse_completion_response(response) # rubocop:disable Metrics/MethodLength
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

      def parse_tool_calls(tool_calls, parse_arguments: true) # rubocop:disable Metrics/MethodLength
        return nil unless tool_calls&.any?

        tool_calls.to_h do |tc|
          [
            tc['id'],
            ToolCall.new(
              id: tc['id'],
              name: tc.dig('function', 'name'),
              arguments: parse_arguments ? JSON.parse(tc.dig('function', 'arguments')) : tc.dig('function', 'arguments')
            )
          ]
        end
      end

      def parse_models_response(response) # rubocop:disable Metrics/MethodLength
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

      def handle_stream(&block) # rubocop:disable Metrics/MethodLength
        to_json_stream do |data|
          block.call(
            Chunk.new(
              role: :assistant,
              model_id: data['model'],
              content: data.dig('choices', 0, 'delta', 'content'),
              tool_calls: parse_tool_calls(data.dig('choices', 0, 'delta', 'tool_calls'), parse_arguments: false),
              input_tokens: data.dig('usage', 'prompt_tokens'),
              output_tokens: data.dig('usage', 'completion_tokens')
            )
          )
        end
      end

      def parse_list_models_response(response) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
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
