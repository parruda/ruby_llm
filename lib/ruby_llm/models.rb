# frozen_string_literal: true

module RubyLLM
  # Registry of available AI models and their capabilities. Provides a clean interface
  # to discover and work with models from different providers.
  #
  # Example:
  #   RubyLLM.models.all                  # All available models
  #   RubyLLM.models.chat_models          # Models that support chat
  #   RubyLLM.models.find('claude-3')     # Get info about a specific model
  module Models
    module_function

    def provider_for(model)
      Provider.for(model)
    end

    def all
      @all ||= begin
        data = JSON.parse(File.read(File.expand_path('models.json', __dir__)))
        data['models'].map { |model| ModelInfo.new(model.transform_keys(&:to_sym)) }
      end
    rescue Errno::ENOENT
      [] # Return empty array if file doesn't exist yet
    end

    def find(model_id)
      all.find { |m| m.id == model_id } or raise Error, "Unknown model: #{model_id}"
    end

    def chat_models
      all.select { |m| m.type == 'chat' }
    end

    def embedding_models
      all.select { |m| m.type == 'embedding' }
    end

    def audio_models
      all.select { |m| m.type == 'audio' }
    end

    def image_models
      all.select { |m| m.type == 'image' }
    end

    def by_family(family)
      all.select { |m| m.family == family }
    end

    def default_model
      'gpt-4o-mini'
    end

    def refresh!
      @all = nil
    end
  end
end
