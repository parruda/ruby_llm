# frozen_string_literal: true

require 'spec_helper'
require 'dotenv/load'

RSpec.describe RubyLLM::Image do
  include_context 'with configured RubyLLM'

  describe 'basic functionality' do
    it 'dall-e-3 can paint images' do # rubocop:disable RSpec/MultipleExpectations
      image = RubyLLM.paint('a siamese cat', model: 'dall-e-3')

      expect(image.base64?).to be(false)
      expect(image.url).to start_with('https://')
      expect(image.mime_type).to include('image')
      expect(image.revised_prompt).to include('cat')
    end

    it 'dall-e-3 supports custom sizes' do # rubocop:disable RSpec/MultipleExpectations
      image = RubyLLM.paint('a siamese cat', size: '1792x1024', model: 'dall-e-3')

      expect(image.base64?).to be(false)
      expect(image.url).to start_with('https://')
      expect(image.mime_type).to include('image')
      expect(image.revised_prompt).to include('cat')
    end

    it 'imagen-3.0-generate-002 can paint images' do # rubocop:disable RSpec/MultipleExpectations
      image = RubyLLM.paint('a siamese cat', model: 'imagen-3.0-generate-002')

      expect(image.base64?).to be(true)
      expect(image.data).to be_present
      expect(image.mime_type).to include('image')
    end

    it 'validates model existence' do
      expect do
        RubyLLM.paint('a cat', model: 'invalid-model')
      end.to raise_error(RubyLLM::ModelNotFoundError)
    end
  end
end
