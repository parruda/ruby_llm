# frozen_string_literal: true

module RubyLLM
  # Client class for handling LLM provider interactions
  class Client
    def initialize
      @providers = {}
    end

    def chat(messages, model: nil, temperature: 0.7, stream: false, tools: nil, &block)
      # Convert any hash messages to Message objects
      formatted_messages = messages.map do |msg|
        msg.is_a?(Message) ? msg : Message.new(**msg)
      end

      provider = provider_for(model)
      provider.chat(
        formatted_messages,
        model: model,
        temperature: temperature,
        stream: stream,
        tools: tools,
        &block
      )
    end

    private

    def provider_for(model)
      provider_name = detect_provider(model)
      @providers[provider_name] ||= case provider_name
                                    when :openai then Providers::OpenAI.new
                                    when :anthropic then Providers::Anthropic.new
                                    else
                                      raise Error, "Unsupported provider: #{provider_name}"
                                    end
    end

    def detect_provider(model)
      return RubyLLM.configuration.default_provider unless model

      case model
      when /^gpt-/, /^text-davinci/
        :openai
      when /^claude/
        :anthropic
      else
        RubyLLM.configuration.default_provider
      end
    end
  end
end
