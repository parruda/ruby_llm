# frozen_string_literal: true

require 'spec_helper'
require 'dotenv/load'

RSpec.describe RubyLLM::Chat do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    RubyLLM.configure do |config|
      config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
      config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY')
      config.gemini_api_key = ENV.fetch('GEMINI_API_KEY')
      config.max_retries = 10
    end
  end

  let(:image_path) { File.expand_path('../fixtures/ruby.png', __dir__) }
  let(:audio_path) { File.expand_path('../fixtures/ruby.wav', __dir__) }

  describe 'vision models' do
    [
      'claude-3-5-sonnet-20241022',
      'gemini-2.0-flash',
      'gpt-4o-mini'
    ].each do |model|
      it "#{model} can understand images" do # rubocop:disable RSpec/MultipleExpectations
        chat = RubyLLM.chat(model: model)
        response = chat.ask('What do you see in this image?', with: { image: image_path })

        expect(response.content).to be_present
        expect(chat.messages.first.content).to be_a(Array)
        expect(chat.messages.first.content.last[:type]).to eq('image')
      end
    end
  end

  describe 'audio models' do
    %w[
      gpt-4o-mini-audio-preview
      gpt-4o-audio-preview
    ].each do |model|
      it "#{model} can understand audio" do # rubocop:disable RSpec/MultipleExpectations
        chat = RubyLLM.chat(model: model)
        response = chat.ask('What is being said?', with: { audio: audio_path })

        expect(response.content).to be_present
        expect(chat.messages.first.content).to be_a(Array)
        expect(chat.messages.first.content.last[:type]).to eq('input_audio')
      end
    end
  end
end
