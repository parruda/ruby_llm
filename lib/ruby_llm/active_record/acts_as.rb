# frozen_string_literal: true

module RubyLLM
  module ActiveRecord
    # Provides ActsAs functionality for LLM-related models
    module ActsAs
      def acts_as_llm_model(_options = {})
        include ModelMethods
      end

      def acts_as_llm_conversation(_options = {})
        include ConversationMethods
        has_many :messages, -> { order(created_at: :asc) }
      end

      def acts_as_llm_message(_options = {})
        include MessageMethods
        belongs_to :conversation
      end
    end

    # Methods for LLM model functionality
    module ModelMethods
      extend ActiveSupport::Concern

      included do
        validates :name, presence: true
        validates :provider, presence: true
      end

      class_methods do
        def sync_models
          # Logic to sync models from providers
        end
      end
    end

    # Methods for LLM conversation handling
    module ConversationMethods
      extend ActiveSupport::Concern

      included do
        before_create :set_default_model
      end

      def send_message(content, model: nil)
        transaction do
          create_user_message(content)
          create_assistant_response(model)
        end
      end

      private

      def create_user_message(content)
        messages.create!(
          role: :user,
          content: content
        )
      end

      def create_assistant_response(model)
        response = RubyLLM.client.chat(
          conversation_messages,
          model: model || current_model
        )

        messages.create!(
          role: :assistant,
          content: response.content,
          token_count: response.token_count
        )
      end

      def conversation_messages
        messages.map(&:to_llm_format)
      end

      def set_default_model
        self.current_model ||= RubyLLM.configuration.default_model
      end
    end

    # Methods for LLM message handling
    module MessageMethods
      extend ActiveSupport::Concern

      included do
        validates :role, presence: true, inclusion: { in: RubyLLM::Message::VALID_ROLES.map(&:to_s) }
        validates :content, presence: true, unless: :tool_call?

        before_save :calculate_tokens
      end

      def to_llm_format
        RubyLLM::Message.new(
          role: role.to_sym,
          content: content,
          tool_calls: tool_calls,
          tool_results: tool_results
        )
      end

      private

      def calculate_tokens
        # Logic to calculate tokens
      end

      def tool_call?
        tool_calls.present? || tool_results.present?
      end
    end
  end
end
