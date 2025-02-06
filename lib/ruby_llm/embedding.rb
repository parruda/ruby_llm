# frozen_string_literal: true

module RubyLLM
  # Core embedding interface. Provides a clean way to generate embeddings
  # from text using various provider models.
  module Embedding
    module_function

    def embed(text, model: nil)
      model_id = model || RubyLLM.config.default_embedding_model
      Models.find(model_id)

      provider = Provider.for(model_id)
      provider.embed(text, model: model_id)
    end
  end
end
