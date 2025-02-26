# frozen_string_literal: true

require 'spec_helper'
require 'dotenv/load'

RSpec.describe RubyLLM::Chat do
  before do
    RubyLLM.configure do |config|
      config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY')
    end
  end

  describe 'with Anthropic provider' do
    let(:chat) { RubyLLM.chat(model: 'claude-3-7-sonnet-20250219') }
    let(:pdf_path) { File.expand_path('../fixtures/sample.pdf', __dir__) }

    it 'sends a PDF document to Claude' do # rubocop:disable RSpec/MultipleExpectations
      response = chat.ask('Summarize this document', with: { pdf: pdf_path })
      expect(response.content).not_to be_empty

      response = chat.ask 'go on'
      expect(response.content).not_to be_empty
    end

    it 'handles multiple PDFs' do # rubocop:disable RSpec/MultipleExpectations
      # Using same file twice for testing
      response = chat.ask('Compare these documents', with: { pdf: [pdf_path, pdf_path] })
      expect(response.content).not_to be_empty

      response = chat.ask 'go on'
      expect(response.content).not_to be_empty
    end
  end
end
