# frozen_string_literal: true

require 'spec_helper'
require 'dotenv/load'
require 'tempfile'

RSpec.describe RubyLLM::Models do
  include_context 'with configured RubyLLM'

  describe 'filtering and chaining' do
    it 'filters models by provider' do # rubocop:disable RSpec/MultipleExpectations
      openai_models = RubyLLM.models.by_provider('openai')
      expect(openai_models.all).to all(have_attributes(provider: 'openai'))

      # Can chain other filters and methods
      expect(openai_models.chat_models).to be_a(described_class)
    end

    it 'chains filters in any order with same result' do
      # These two filters should be equivalent
      openai_chat_models = RubyLLM.models.by_provider('openai').chat_models
      chat_openai_models = RubyLLM.models.chat_models.by_provider('openai')

      # Both return same model IDs
      expect(openai_chat_models.map(&:id).sort).to eq(chat_openai_models.map(&:id).sort)
    end

    it 'supports Enumerable methods' do # rubocop:disable RSpec/MultipleExpectations
      # Count models by provider
      provider_counts = RubyLLM.models.group_by(&:provider)
                               .transform_values(&:count)

      # There should be models from at least OpenAI and Anthropic
      expect(provider_counts.keys).to include('openai', 'anthropic')

      # Select only models with vision support
      vision_models = RubyLLM.models.select(&:supports_vision)
      expect(vision_models).to all(have_attributes(supports_vision: true))
    end
  end

  describe 'finding models' do
    it 'finds models by ID' do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
      # Find the default model
      model_id = RubyLLM.config.default_model
      model = RubyLLM.models.find(model_id)
      expect(model.id).to eq(model_id)

      # Find a model with chaining
      if RubyLLM.models.by_provider('openai').chat_models.any?
        openai_chat_id = RubyLLM.models.by_provider('openai').chat_models.first.id
        found = RubyLLM.models.by_provider('openai').find(openai_chat_id)
        expect(found.id).to eq(openai_chat_id)
        expect(found.provider).to eq('openai')
      end
    end

    it 'raises ModelNotFoundError for unknown models' do
      expect do
        RubyLLM.models.find('nonexistent-model-12345')
      end.to raise_error(RubyLLM::ModelNotFoundError)
    end
  end

  describe '#refresh!' do
    it 'updates models and returns a chainable Models instance' do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
      # Use a temporary file to avoid modifying actual models.json
      temp_file = Tempfile.new(['models', '.json'])
      allow(File).to receive(:expand_path).with('models.json', any_args).and_return(temp_file.path)

      begin
        # Refresh and chain immediately
        chat_models = RubyLLM.models.refresh!.chat_models

        # Verify we got results
        expect(chat_models).to be_a(described_class)
        expect(chat_models.all).to all(have_attributes(type: 'chat'))

        # Verify we got models from at least OpenAI and Anthropic
        providers = chat_models.map(&:provider).uniq
        expect(providers).to include('openai', 'anthropic')
      ensure
        temp_file.close
        temp_file.unlink
      end
    end

    it 'works as a class method too' do # rubocop:disable RSpec/ExampleLength
      temp_file = Tempfile.new(['models', '.json'])
      allow(File).to receive(:expand_path).with('models.json', any_args).and_return(temp_file.path)

      begin
        # Call class method
        described_class.refresh!

        # Verify singleton instance was updated
        expect(RubyLLM.models.all.size).to be > 0
      ensure
        temp_file.close
        temp_file.unlink
      end
    end
  end
end
