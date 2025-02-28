# frozen_string_literal: true

require 'spec_helper'
require 'dotenv/load'

RSpec.describe RubyLLM::Models do
  include_context 'with configured RubyLLM'

  describe 'class methods' do
    it 'provides model access through the class' do # rubocop:disable RSpec/MultipleExpectations
      expect(RubyLLM.models).to be_a(described_class)
      expect(RubyLLM.models.all).to be_an(Array)
      expect(described_class.all).to eq(RubyLLM.models.all)
    end
  end

  describe 'model filtering' do
    it 'filters models by provider' do # rubocop:disable RSpec/MultipleExpectations
      openai_models = RubyLLM.models.by_provider('openai')
      expect(openai_models).to be_a(described_class)
      expect(openai_models.all).to all(have_attributes(provider: 'openai'))
    end

    it 'chains filters for multiple conditions' do # rubocop:disable RSpec/MultipleExpectations
      # Get OpenAI chat models
      openai_chat_models = RubyLLM.models.by_provider('openai').chat_models
      expect(openai_chat_models.all).to all(have_attributes(provider: 'openai', type: 'chat'))

      # Filters work in any order
      chat_openai_models = RubyLLM.models.chat_models.by_provider('openai')
      expect(chat_openai_models.all).to all(have_attributes(provider: 'openai', type: 'chat'))

      # Both should return the same models
      expect(openai_chat_models.map(&:id).sort).to eq(chat_openai_models.map(&:id).sort)
    end

    it 'supports multiple chained filters' do
      # Find embedding models from a specific provider
      embedding_models = RubyLLM.models.by_provider('openai').embedding_models
      expect(embedding_models.all).to all(have_attributes(provider: 'openai', type: 'embedding'))
    end
  end

  describe 'model lookup' do
    it 'finds models by ID' do
      model = RubyLLM.config.default_model
      found_model = RubyLLM.models.find(model)
      expect(found_model.id).to eq(model)
    end

    it 'finds models by ID with chained filters' do
      # Find a specific OpenAI chat model by ID
      if RubyLLM.models.by_provider('openai').chat_models.all.any?
        model_id = RubyLLM.models.by_provider('openai').chat_models.all.first.id
        found_model = RubyLLM.models.by_provider('openai').find(model_id)
        expect(found_model.id).to eq(model_id)
      end
    end

    it 'raises an error for unknown models' do
      expect { RubyLLM.models.find('nonexistent-model-12345') }.to raise_error(RubyLLM::ModelNotFoundError)
    end
  end

  describe 'enumerable functionality' do
    it 'allows iterating over filtered results' do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
      count = 0
      RubyLLM.models.chat_models.each do |model|
        expect(model.type).to eq('chat')
        count += 1
      end
      expect(count).to be > 0
    end

    it 'supports enumerable methods' do
      # Get models that support vision capabilities
      vision_models = RubyLLM.models.chat_models.select(&:supports_vision)

      # All returned models should support vision
      expect(vision_models).to all(have_attributes(supports_vision: true))
    end
  end
end
