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
          create_chat_completion(payload, tools)
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

      def create_chat_completion(payload, tools = nil)
        response = connection.post('/v1/chat/completions') do |req|
          req.headers['Authorization'] = "Bearer #{RubyLLM.configuration.openai_api_key}"
          req.headers['Content-Type'] = 'application/json'
          req.body = payload
        end

        puts 'Response from OpenAI:' if ENV['RUBY_LLM_DEBUG']
        puts JSON.pretty_generate(response.body) if ENV['RUBY_LLM_DEBUG']

        if response.status >= 400
          error_msg = response.body['error']&.fetch('message', nil) || "HTTP #{response.status}"
          raise RubyLLM::Error, "API error: #{error_msg}"
        end

        handle_response(response, tools, payload)
      end

      def handle_response(response, tools, payload)
        data = response.body
        message_data = data.dig('choices', 0, 'message')
        return Message.new(role: :assistant, content: '') unless message_data

        if message_data['function_call'] && tools
          result = handle_function_call(message_data['function_call'], tools)
          puts "Function result: #{result}" if ENV['RUBY_LLM_DEBUG']

          # Create a new chat completion with the function results
          new_messages = payload[:messages] + [
            { role: 'assistant', content: message_data['content'], function_call: message_data['function_call'] },
            { role: 'function', name: message_data['function_call']['name'], content: result }
          ]

          return create_chat_completion(payload.merge(messages: new_messages), tools)
        end

        Message.new(
          role: :assistant,
          content: message_data['content']
        )
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

      def api_base
        'https://api.openai.com'
      end
    end
  end
end
