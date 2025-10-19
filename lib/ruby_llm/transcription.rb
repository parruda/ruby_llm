# frozen_string_literal: true

module RubyLLM
  # Represents a transcription of audio content.
  class Transcription
    attr_reader :text, :model, :language, :duration, :segments

    def initialize(text:, model:, language: nil, duration: nil, segments: nil)
      @text = text
      @model = model
      @language = language
      @duration = duration
      @segments = segments
    end

    def self.transcribe(audio_file, # rubocop:disable Metrics/ParameterLists
                        model: nil,
                        language: nil,
                        provider: nil,
                        assume_model_exists: false,
                        context: nil,
                        **options)
      config = context&.config || RubyLLM.config
      model ||= config.default_transcription_model
      model, provider_instance = Models.resolve(model, provider: provider, assume_exists: assume_model_exists,
                                                       config: config)
      model_id = model.id

      provider_instance.transcribe(audio_file, model: model_id, language:, **options)
    end
  end
end
