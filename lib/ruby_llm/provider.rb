# frozen_string_literal: true

module RubyLLM
  # Base interface for LLM providers like OpenAI and Anthropic.
  # Handles the complexities of API communication, streaming responses,
  # and error handling so individual providers can focus on their unique features.
  module Provider
    def self.included(base)
      base.include(InstanceMethods)
    end

    # Common functionality for all LLM providers. Implements the core provider
    # interface so specific providers only need to implement a few key methods.
    module InstanceMethods
      def complete(messages, tools:, temperature:, model:, &block)
        payload = build_payload messages, tools: tools, temperature: temperature, model: model, stream: block_given?

        if block_given?
          stream_response payload, &block
        else
          sync_response payload
        end
      end

      def list_models
        response = connection.get(models_url) do |req|
          req.headers.merge! headers
        end

        parse_list_models_response response
      end

      def embed(text, model:)
        payload = build_embedding_payload text, model: model
        response = post embedding_url, payload
        parse_embedding_response response
      end

      private

      def sync_response(payload)
        response = post completion_url, payload
        parse_completion_response response
      end

      def stream_response(payload, &block)
        accumulator = StreamAccumulator.new

        post completion_url, payload do |req|
          req.options.on_data = handle_stream do |chunk|
            accumulator.add chunk
            block.call chunk
          end
        end

        accumulator.to_message
      end

      def post(url, payload)
        connection.post url, payload do |req|
          req.headers.merge! headers
          yield req if block_given?
        end
      end

      def connection
        @connection ||= Faraday.new(api_base) do |f|
          f.options.timeout = RubyLLM.config.request_timeout
          f.request :json
          f.response :json
          f.adapter Faraday.default_adapter
          f.use :llm_errors, provider: self
          f.response :logger, RubyLLM.logger, { headers: false, bodies: true, errors: true, log_level: :debug }
        end
      end

      def to_json_stream(&block) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        buffer = String.new
        parser = EventStreamParser::Parser.new

        proc do |chunk, _bytes, env|
          if env && env.status != 200
            # Accumulate error chunks
            buffer << chunk
            begin
              error_data = JSON.parse(buffer)
              error_response = env.merge(body: error_data)
              ErrorMiddleware.parse_error(provider: self, response: error_response)
            rescue JSON::ParserError
              # Keep accumulating if we don't have complete JSON yet
              RubyLLM.logger.debug "Accumulating error chunk: #{chunk}"
            end
          else
            parser.feed(chunk) do |_type, data|
              unless data == '[DONE]'
                parsed_data = JSON.parse(data)
                RubyLLM.logger.debug "chunk: #{parsed_data}"
                block.call(parsed_data)
              end
            end
          end
        end
      end
    end

    def try_parse_json(maybe_json)
      return maybe_json if maybe_json.is_a?(Hash)

      JSON.parse(maybe_json)
    rescue JSON::ParserError
      maybe_json
    end

    class << self
      def register(name, provider_class)
        providers[name.to_sym] = provider_class
      end

      def for(model)
        model_info = Models.find(model)
        provider_class = providers[model_info.provider.to_sym]

        provider_class.new
      end

      private

      def providers
        @providers ||= {}
      end
    end
  end
end
