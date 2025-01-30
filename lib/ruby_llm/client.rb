# frozen_string_literal: true

module RubyLLM
  # Client class for handling LLM provider interactions
  class Client
    def initialize
      @providers = {}
      @conversations = {}
    end

    def chat(messages, model: nil, temperature: 1.0, stream: false, &block)
      provider = provider_for(model)
      provider.chat(
        messages,
        model: model,
        temperature: temperature,
        stream: stream,
        &block
      )
    end

    def create_conversation(tools: [])
      conversation = Conversation.new(tools: tools)
      @conversations[conversation.id] = conversation
      conversation
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
