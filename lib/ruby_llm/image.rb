# frozen_string_literal: true

module RubyLLM
  # Represents a generated image from an AI model.
  # Provides an interface to image generation capabilities
  # from providers like DALL-E.
  class Image
    attr_reader :url, :revised_prompt, :model_id

    def initialize(url:, revised_prompt: nil, model_id: nil)
      @url = url
      @revised_prompt = revised_prompt
      @model_id = model_id
    end

    def self.paint(prompt, model: nil, size: '1024x1024')
      model_id = model || RubyLLM.config.default_image_model
      Models.find(model_id) # Validate model exists

      provider = Provider.for(model_id)
      provider.paint(prompt, model: model_id, size: size)
    end
  end
end
