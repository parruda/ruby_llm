# frozen_string_literal: true

require 'spec_helper'
require 'dotenv/load'

RSpec.describe RubyLLM::Embedding do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    RubyLLM.configure do |config|
      config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
      config.gemini_api_key = ENV.fetch('GEMINI_API_KEY')
    end
  end

  let(:test_text) { "Ruby is a programmer's best friend" }
  let(:test_texts) { %w[Ruby Python JavaScript] }

  describe 'basic functionality' do
    [
      'text-embedding-004', # gemini
      'text-embedding-3-small' # openai
    ].each do |model|
      context "with #{model}" do
        it 'can handle a single text' do # rubocop:disable RSpec/MultipleExpectations
          embedding = RubyLLM.embed(test_text, model: model)
          expect(embedding.vectors).to be_an(Array)
          expect(embedding.vectors.first).to be_a(Float)
          expect(embedding.model).to eq(model)
          expect(embedding.input_tokens).to be >= 0
        end

        it 'can handle multiple texts' do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
          embeddings = RubyLLM.embed(test_texts, model: model)
          expect(embeddings.vectors).to be_an(Array)
          expect(embeddings.vectors.size).to eq(3)
          expect(embeddings.vectors.first).to be_an(Array)
          expect(embeddings.model).to eq(model)
          expect(embeddings.input_tokens).to be >= 0
        end
      end
    end
  end
end
