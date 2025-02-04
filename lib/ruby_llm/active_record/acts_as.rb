# frozen_string_literal: true

module RubyLLM
  module ActiveRecord
    # Adds chat and message persistence capabilities to ActiveRecord models.
    # Provides a clean interface for storing chat history and message metadata
    # in your database.
    module ActsAs
      extend ActiveSupport::Concern

      class_methods do
        def acts_as_chat(message_class:)
          include ChatMethods

          has_many :messages,
                   -> { order(created_at: :asc) },
                   class_name: message_class.to_s,
                   dependent: :destroy

          # No more callback config - just expose the core chat functionality
          delegate :ask, :say, :complete, to: :chat
        end

        def acts_as_message(chat_class:)
          include MessageMethods

          belongs_to :chat, class_name: chat_class.to_s

          serialize :tool_calls, coder: JSON
        end
      end
    end

    # Methods mixed into chat models to handle message persistence and
    # provide a conversation interface.
    module ChatMethods
      extend ActiveSupport::Concern

      def chat
        @chat ||= begin
          chat = RubyLLM.chat(model: model_id)

          # Load existing messages into chat
          messages.each do |msg|
            chat.add_message(msg.to_llm)
          end

          # Set up message persistence
          chat.on_new_message { |msg| persist_new_message(msg) }
              .on_end_message { |msg| persist_message_completion(msg) }

          chat
        end
      end

      private

      def persist_new_message(message)
        return unless message

        messages.create!(
          role: message.role,
          content: message.content,
          tool_calls: message.tool_calls,
          tool_call_id: message.tool_call_id,
          model_id: message.model_id
        )
      end

      def persist_message_completion(message)
        return unless message

        messages.last.update!(
          content: message.content,
          tool_calls: message.tool_calls,
          input_tokens: message.input_tokens,
          output_tokens: message.output_tokens
        )
      end
    end

    # Methods mixed into message models to handle serialization and
    # provide a clean interface to the underlying message data.
    module MessageMethods
      extend ActiveSupport::Concern

      def to_llm
        RubyLLM::Message.new(
          role: role.to_sym,
          content: content,
          tool_calls: tool_calls,
          tool_call_id: tool_call_id,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          model_id: model_id
        )
      end
    end
  end
end
