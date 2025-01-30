# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAI < Base
      def chat(messages, model: nil, temperature: 0.7, stream: false, tools: nil, &block)
        payload = {
          model: model || RubyLLM.configuration.default_model,
          messages: messages.map(&:to_h),
          temperature: temperature,
          stream: stream
        }

        if tools&.any?
          payload[:functions] = tools.map { |tool| tool_to_function(tool) }
          payload[:function_call] = 'auto'
        end

        puts 'Sending payload to OpenAI:' if ENV['RUBY_LLM_DEBUG']
        puts JSON.pretty_generate(payload) if ENV['RUBY_LLM_DEBUG']

        if stream && block_given?
          stream_chat_completion(payload, tools, &block)
        else
          create_chat_completion(payload, tools, &block)
        end
      rescue Faraday::TimeoutError
        raise RubyLLM::Error, 'Request timed out'
      rescue Faraday::ConnectionFailed
        raise RubyLLM::Error, 'Connection failed'
      rescue Faraday::ClientError => e
        raise RubyLLM::Error, 'Client error' unless e.response

        error_msg = e.response[:body]['error']&.fetch('message', nil) || "HTTP #{e.response[:status]}"
        raise RubyLLM::Error, "API error: #{error_msg}"
      end

      def list_models
        response = @connection.get('/v1/models') do |req|
          req.headers['Authorization'] = "Bearer #{RubyLLM.configuration.openai_api_key}"
        end

        raise RubyLLM::Error, "API error: #{parse_error_message(response)}" if response.status >= 400

        capabilities = RubyLLM::ModelCapabilities::OpenAI.new
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
            context_window: capabilities.determine_context_window(model['id']),
            max_tokens: capabilities.determine_max_tokens(model['id']),
            supports_vision: capabilities.supports_vision?(model['id']),
            supports_functions: capabilities.supports_functions?(model['id']),
            supports_json_mode: capabilities.supports_json_mode?(model['id']),
            input_price_per_million: capabilities.get_input_price(model['id']),
            output_price_per_million: capabilities.get_output_price(model['id'])
          )
        end
      rescue Faraday::Error => e
        handle_error(e)
      end

      private

      def tool_to_function(tool)
        {
          name: tool.name,
          description: tool.description,
          parameters: {
            type: 'object',
            properties: tool.parameters.transform_values { |v| v.reject { |k, _| k == :required } },
            required: tool.parameters.select { |_, v| v[:required] }.keys
          }
        }
      end

      def create_chat_completion(payload, tools = nil, &block)
        response = connection.post('/v1/chat/completions') do |req|
          req.headers['Authorization'] = "Bearer #{RubyLLM.configuration.openai_api_key}"
          req.headers['Content-Type'] = 'application/json'
          req.body = payload
        end

        puts 'Response from OpenAI:' if ENV['RUBY_LLM_DEBUG']
        puts JSON.pretty_generate(response.body) if ENV['RUBY_LLM_DEBUG']

        # Check for API errors
        check_for_api_error(response)

        # Check for HTTP errors
        if response.status >= 400
          error_msg = response.body['error']&.fetch('message', nil) || "HTTP #{response.status}"
          raise RubyLLM::Error, "API error: #{error_msg}"
        end

        handle_response(response, tools, payload, &block)
      end

      def handle_response(response, tools, payload, &block)
        data = response.body
        message_data = data.dig('choices', 0, 'message')
        return [] unless message_data

        if message_data['function_call'] && tools
          # Create function call message
          function_message = Message.new(
            role: :assistant,
            content: message_data['content'],
            tool_calls: [message_data['function_call']]
          )
          yield function_message if block_given?

          # Execute function and create result message
          result = handle_function_call(message_data['function_call'], tools)
          result_message = Message.new(
            role: :tool,
            content: result,
            tool_results: {
              name: message_data['function_call']['name'],
              content: result
            }
          )
          yield result_message if block_given?

          # Get final response with function results
          new_messages = payload[:messages] + [
            { role: 'assistant', content: message_data['content'], function_call: message_data['function_call'] },
            { role: 'function', name: message_data['function_call']['name'], content: result }
          ]

          final_response = create_chat_completion(
            payload.merge(messages: new_messages),
            tools,
            &block
          )

          # Return all messages in sequence
          [function_message, result_message] + final_response
        else
          token_usage = if data['usage']
                          {
                            input_tokens: data['usage']['prompt_tokens'],
                            output_tokens: data['usage']['completion_tokens'],
                            total_tokens: data['usage']['total_tokens']
                          }
                        end

          [Message.new(
            role: :assistant,
            content: message_data['content'],
            token_usage: token_usage,
            model_id: data['model']
          )]
        end
      end

      def handle_function_call(function_call, tools)
        return unless function_call && tools

        tool = tools.find { |t| t.name == function_call['name'] }
        return unless tool

        begin
          args = JSON.parse(function_call['arguments'])
          tool.call(args)
        rescue JSON::ParserError, ArgumentError => e
          "Error executing function #{tool.name}: #{e.message}"
        end
      end

      def handle_error(error)
        case error
        when Faraday::TimeoutError
          raise RubyLLM::Error, 'Request timed out'
        when Faraday::ConnectionFailed
          raise RubyLLM::Error, 'Connection failed'
        when Faraday::ClientError
          raise RubyLLM::Error, 'Client error' unless error.response

          error_msg = error.response[:body]['error']&.fetch('message', nil) || "HTTP #{error.response[:status]}"
          raise RubyLLM::Error, "API error: #{error_msg}"

        else
          raise error
        end
      end

      def handle_api_error(error)
        response_body = error.response[:body]
        if response_body.is_a?(String)
          begin
            error_data = JSON.parse(response_body)
            message = error_data.dig('error', 'message')
            raise RubyLLM::Error, "API error: #{message}" if message
          rescue JSON::ParserError
            raise RubyLLM::Error, "API error: #{error.response[:status]}"
          end
        elsif response_body['error']
          raise RubyLLM::Error, "API error: #{response_body['error']['message']}"
        else
          raise RubyLLM::Error, "API error: #{error.response[:status]}"
        end
      end

      def api_base
        'https://api.openai.com'
      end
    end
  end
end
