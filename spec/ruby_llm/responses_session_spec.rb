# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::ResponsesSession do
  describe '#initialize' do
    it 'creates a new session with default values' do
      session = described_class.new

      expect(session.response_id).to be_nil
      expect(session.last_activity).to be_nil
      expect(session.failure_count).to eq(0)
      expect(session.disabled?).to be false
    end

    it 'creates a session with custom values' do
      time = Time.now
      session = described_class.new(
        response_id: 'resp_123',
        last_activity: time,
        failure_count: 1,
        disabled: false
      )

      expect(session.response_id).to eq('resp_123')
      expect(session.last_activity).to eq(time)
      expect(session.failure_count).to eq(1)
      expect(session.disabled?).to be false
    end
  end

  describe '#reset!' do
    it 'resets all session state to defaults' do
      session = described_class.new(
        response_id: 'resp_123',
        last_activity: Time.now,
        failure_count: 2,
        disabled: true
      )

      session.reset!

      expect(session.response_id).to be_nil
      expect(session.last_activity).to be_nil
      expect(session.failure_count).to eq(0)
      expect(session.disabled?).to be false
    end
  end

  describe '#update' do
    it 'updates response_id and last_activity' do
      session = described_class.new

      session.update('resp_456')

      expect(session.response_id).to eq('resp_456')
      expect(session.last_activity).to be_within(1).of(Time.now)
      expect(session.failure_count).to eq(0)
    end

    it 'resets failure count on successful update' do
      session = described_class.new(failure_count: 2)

      session.update('resp_789')

      expect(session.failure_count).to eq(0)
    end
  end

  describe '#valid?' do
    it 'returns true when response_id exists and within TTL' do
      session = described_class.new(
        response_id: 'resp_123',
        last_activity: Time.now - 60 # 1 minute ago
      )

      expect(session.valid?).to be true
    end

    it 'returns false when response_id is nil' do
      session = described_class.new(last_activity: Time.now)

      expect(session.valid?).to be false
    end

    it 'returns false when last_activity is nil' do
      session = described_class.new(response_id: 'resp_123')

      expect(session.valid?).to be false
    end

    it 'returns false when session is expired (beyond TTL)' do
      session = described_class.new(
        response_id: 'resp_123',
        last_activity: Time.now - described_class::RESPONSE_ID_TTL - 10
      )

      expect(session.valid?).to be false
    end

    it 'returns false when disabled' do
      session = described_class.new(
        response_id: 'resp_123',
        last_activity: Time.now,
        disabled: true
      )

      expect(session.valid?).to be false
    end

    it 'returns true when exactly at TTL boundary' do
      session = described_class.new(
        response_id: 'resp_123',
        last_activity: Time.now - described_class::RESPONSE_ID_TTL + 1
      )

      expect(session.valid?).to be true
    end
  end

  describe '#record_failure!' do
    it 'increments failure count' do
      session = described_class.new

      session.record_failure!

      expect(session.failure_count).to eq(1)
    end

    it 'resets session on first failure' do
      session = described_class.new(
        response_id: 'resp_123',
        last_activity: Time.now
      )

      session.record_failure!

      expect(session.response_id).to be_nil
      expect(session.last_activity).to be_nil
      expect(session.disabled?).to be false
    end

    it 'disables session after MAX_FAILURES' do
      session = described_class.new(failure_count: described_class::MAX_FAILURES - 1)

      session.record_failure!

      expect(session.disabled?).to be true
      expect(session.failure_count).to eq(described_class::MAX_FAILURES)
    end

    it 'does not reset session when disabled' do
      session = described_class.new(
        response_id: 'resp_123',
        last_activity: Time.now,
        failure_count: described_class::MAX_FAILURES - 1
      )

      session.record_failure!

      expect(session.disabled?).to be true
      # Response ID should remain since session is disabled, not reset
      expect(session.response_id).to eq('resp_123')
    end
  end

  describe '#to_h' do
    it 'serializes session to hash' do
      time = Time.now
      session = described_class.new(
        response_id: 'resp_123',
        last_activity: time,
        failure_count: 1,
        disabled: false
      )

      hash = session.to_h

      expect(hash[:response_id]).to eq('resp_123')
      expect(hash[:last_activity]).to eq(time.iso8601)
      expect(hash[:failure_count]).to eq(1)
      expect(hash[:disabled]).to be false
    end

    it 'handles nil last_activity' do
      session = described_class.new(response_id: 'resp_123')

      hash = session.to_h

      expect(hash[:last_activity]).to be_nil
    end
  end

  describe '.from_h' do
    it 'deserializes session from hash with symbol keys' do
      time = Time.now
      hash = {
        response_id: 'resp_123',
        last_activity: time.iso8601,
        failure_count: 2,
        disabled: true
      }

      session = described_class.from_h(hash)

      expect(session.response_id).to eq('resp_123')
      expect(session.last_activity).to be_within(1).of(time)
      expect(session.failure_count).to eq(2)
      expect(session.disabled?).to be true
    end

    it 'deserializes session from hash with string keys' do
      time = Time.now
      hash = {
        'response_id' => 'resp_456',
        'last_activity' => time.iso8601,
        'failure_count' => 1,
        'disabled' => false
      }

      session = described_class.from_h(hash)

      expect(session.response_id).to eq('resp_456')
      expect(session.failure_count).to eq(1)
      expect(session.disabled?).to be false
    end

    it 'handles missing optional fields' do
      hash = {
        response_id: 'resp_789'
      }

      session = described_class.from_h(hash)

      expect(session.response_id).to eq('resp_789')
      expect(session.last_activity).to be_nil
      expect(session.failure_count).to eq(0)
      expect(session.disabled?).to be false
    end

    it 'handles nil last_activity' do
      hash = {
        response_id: 'resp_123',
        last_activity: nil,
        failure_count: 0,
        disabled: false
      }

      session = described_class.from_h(hash)

      expect(session.last_activity).to be_nil
    end

    it 'roundtrips through to_h and from_h' do
      original = described_class.new(
        response_id: 'resp_roundtrip',
        last_activity: Time.now,
        failure_count: 1,
        disabled: false
      )

      restored = described_class.from_h(original.to_h)

      expect(restored.response_id).to eq(original.response_id)
      expect(restored.last_activity).to be_within(1).of(original.last_activity)
      expect(restored.failure_count).to eq(original.failure_count)
      expect(restored.disabled?).to eq(original.disabled?)
    end
  end

  describe 'constants' do
    it 'has a response ID TTL of 5 minutes' do
      expect(described_class::RESPONSE_ID_TTL).to eq(300)
    end

    it 'has max failures of 2' do
      expect(described_class::MAX_FAILURES).to eq(2)
    end
  end
end
