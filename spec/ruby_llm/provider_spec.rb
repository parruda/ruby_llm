# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Provider do
  # Create a concrete test provider since Provider is abstract
  let(:test_provider_class) do
    Class.new(described_class) do
      def self.capabilities
        %i[chat]
      end

      def self.configuration_requirements
        []
      end

      def api_base
        'https://test.example.com'
      end
    end
  end

  let(:config) { RubyLLM.config }
  let(:provider) { test_provider_class.new(config) }

  describe '#parse_error' do
    context 'when response body is empty' do
      it 'returns nil' do
        response = instance_double(Faraday::Response, body: '')
        expect(provider.parse_error(response)).to be_nil
      end
    end

    context 'when response body contains a hash with error message' do
      it 'extracts the error message' do
        response_body = { 'error' => { 'message' => 'Invalid API key' } }
        response = instance_double(Faraday::Response, body: response_body)
        expect(provider.parse_error(response)).to eq('Invalid API key')
      end
    end

    context 'when response body contains an array of errors' do
      it 'joins error messages with periods' do
        response_body = [
          { 'error' => { 'message' => 'First error' } },
          { 'error' => { 'message' => 'Second error' } }
        ]
        response = instance_double(Faraday::Response, body: response_body)
        expect(provider.parse_error(response)).to eq('First error. Second error')
      end
    end

    context 'when response body is a plain string' do
      it 'returns the string directly' do
        response = instance_double(Faraday::Response, body: 'Plain error message')
        expect(provider.parse_error(response)).to eq('Plain error message')
      end
    end

    context 'when response body is JSON string' do
      it 'parses and extracts the error message' do
        response_body = '{"error": {"message": "JSON error"}}'
        response = instance_double(Faraday::Response, body: response_body)
        expect(provider.parse_error(response)).to eq('JSON error')
      end
    end

    context 'when response body causes a NoMethodError' do
      it 'returns the raw response body' do
        # Create a body that will cause NoMethodError when dig is called
        problematic_body = Object.new
        def problematic_body.empty?
          false
        end

        def problematic_body.is_a?(_)
          false
        end

        response = instance_double(Faraday::Response, body: problematic_body)
        expect(provider.parse_error(response)).to eq(problematic_body)
      end

      it 'handles integer response body gracefully' do
        response = instance_double(Faraday::Response, body: 500)
        expect(provider.parse_error(response)).to eq(500)
      end
    end
  end
end
