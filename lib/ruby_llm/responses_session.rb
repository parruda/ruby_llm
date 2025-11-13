# frozen_string_literal: true

module RubyLLM
  # Manages state for OpenAI Responses API stateful conversations.
  # Tracks response IDs, session validity, and failure recovery.
  class ResponsesSession
    RESPONSE_ID_TTL = 300 # 5 minutes
    MAX_FAILURES = 2

    attr_reader :response_id, :last_activity, :failure_count

    def initialize(response_id: nil, last_activity: nil, failure_count: 0, disabled: false)
      @response_id = response_id
      @last_activity = last_activity
      @failure_count = failure_count
      @disabled = disabled
    end

    def reset!
      @response_id = nil
      @last_activity = nil
      @failure_count = 0
      @disabled = false
    end

    def update(new_response_id)
      @response_id = new_response_id
      @last_activity = Time.now
      @failure_count = 0
    end

    def valid?
      return false if @disabled
      return false unless @response_id
      return false unless @last_activity

      (Time.now - @last_activity) < RESPONSE_ID_TTL
    end

    def record_failure!
      @failure_count += 1

      if @failure_count >= MAX_FAILURES
        @disabled = true
      else
        # Reset response_id and last_activity but preserve failure_count
        @response_id = nil
        @last_activity = nil
      end
    end

    def disabled?
      @disabled
    end

    def to_h
      {
        response_id: @response_id,
        last_activity: @last_activity&.iso8601,
        failure_count: @failure_count,
        disabled: @disabled
      }
    end

    def self.from_h(hash)
      hash = hash.transform_keys(&:to_sym)
      last_activity = hash[:last_activity] ? Time.parse(hash[:last_activity]) : nil

      new(
        response_id: hash[:response_id],
        last_activity: last_activity,
        failure_count: hash[:failure_count] || 0,
        disabled: hash[:disabled] || false
      )
    end
  end
end
