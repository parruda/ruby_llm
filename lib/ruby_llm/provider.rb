# frozen_string_literal: true

module RubyLLM
  module Provider
    def self.included(base)
      base.include(InstanceMethods)
    end

    module InstanceMethods
      def complete(messages, tools: [], model: nil, &block)
        payload = build_payload messages, tools, model: model, stream: block_given?

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

      private

      def sync_response(payload)
        response = post payload
        parse_completion_response response
      end

      def stream_response(payload, &block)
        accumulator = StreamAccumulator.new

        post payload do |req|
          req.options.on_data = handle_stream do |chunk|
            accumulator.add chunk
            block.call chunk
          end
        end

        accumulator.to_message
      end

      def post(payload)
        connection.post completion_url, payload do |req|
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
          f.use Faraday::Response::RaiseError
          f.response :logger, RubyLLM.logger, { headers: false, bodies: true, errors: true, log_level: :debug }
        end
      end

      def to_json_stream(&block)
        parser = EventStreamParser::Parser.new
        proc do |chunk, _bytes, _|
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

    class << self
      def register(name, provider_class)
        providers[name.to_sym] = provider_class
      end

      def for(model)
        model_info = Models.find(model)
        provider_class = providers[model_info.provider.to_sym] or
          raise Error, "No provider registered for #{model_info.provider}"

        provider_class.new
      end

      private

      def providers
        @providers ||= {}
      end
    end
  end
end
