# frozen_string_literal: true

require 'spec_helper'
require 'dotenv/load'

RSpec.describe RubyLLM::Image do
  include_context 'with configured RubyLLM'

  describe 'basic functionality' do
    [
      'dall-e-3'
      # 'imagen-3.0-generate-002'
    ].each do |model|
      it "#{model} can paint images" do # rubocop:disable RSpec/MultipleExpectations
        image = RubyLLM.paint('a siamese cat', model: model)

        expect(image.url).to start_with('https://')
        expect(image.revised_prompt).to include('cat')
      end

      it "#{model} supports custom sizes" do
        image = RubyLLM.paint(
          'a siamese cat',
          size: '1792x1024'
        )

        expect(image.url).to start_with('https://')
      end
    end
    it 'validates model existence' do
      expect do
        RubyLLM.paint('a cat', model: 'invalid-model')
      end.to raise_error(RubyLLM::ModelNotFoundError)
    end
  end
end
