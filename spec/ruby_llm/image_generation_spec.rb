# frozen_string_literal: true

require 'spec_helper'
require 'dotenv/load'

RSpec.describe RubyLLM::Image do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    RubyLLM.configure do |config|
      config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
    end
  end

  describe 'basic functionality' do
    [
      'dall-e-3'
      # 'imagen-3.0-generate-002' # Google's model doesn't support OpenAI API
    ].each do |model|
      it 'can paint images' do # rubocop:disable RSpec/MultipleExpectations
        image = RubyLLM.paint('a siamese cat', model: model)

        expect(image.url).to start_with('https://')
        expect(image.revised_prompt).to include('cat')
      end

      it 'supports custom sizes' do
        image = RubyLLM.paint(
          'a siamese cat',
          size: '1792x1024'
        )

        expect(image.url).to start_with('https://')
      end

      it 'validates model existence' do
        expect do
          RubyLLM.paint('a cat', model: 'invalid-model')
        end.to raise_error(RubyLLM::ModelNotFoundError)
      end
    end
  end
end
