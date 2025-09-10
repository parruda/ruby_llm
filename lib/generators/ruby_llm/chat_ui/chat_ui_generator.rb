# frozen_string_literal: true

require 'rails/generators'

module RubyLLM
  module Generators
    # Generates a simple chat UI scaffold for RubyLLM
    class ChatUIGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      namespace 'ruby_llm:chat_ui'

      argument :model_mappings, type: :array, default: [], banner: 'chat:ChatName message:MessageName ...'

      desc 'Creates a chat UI scaffold with Turbo streaming\n' \
           'Usage: rails g ruby_llm:chat_ui [chat:ChatName] [message:MessageName] ...'

      def parse_model_mappings
        @model_names = {
          chat: 'Chat',
          message: 'Message',
          tool_call: 'ToolCall',
          model: 'Model'
        }

        model_mappings.each do |mapping|
          if mapping.include?(':')
            key, value = mapping.split(':', 2)
            @model_names[key.to_sym] = value.classify
          end
        end

        @model_names
      end

      %i[chat message model].each do |type|
        define_method("#{type}_model_name") do
          @model_names ||= parse_model_mappings
          @model_names[type]
        end
      end

      def create_views
        # Chat views
        template 'views/chats/index.html.erb', "app/views/#{chat_model_name.tableize}/index.html.erb"
        template 'views/chats/new.html.erb', "app/views/#{chat_model_name.tableize}/new.html.erb"
        template 'views/chats/show.html.erb', "app/views/#{chat_model_name.tableize}/show.html.erb"
        template 'views/chats/_chat.html.erb',
                 "app/views/#{chat_model_name.tableize}/_#{chat_model_name.underscore}.html.erb"
        template 'views/chats/_form.html.erb', "app/views/#{chat_model_name.tableize}/_form.html.erb"

        # Message views
        template 'views/messages/_message.html.erb',
                 "app/views/#{message_model_name.tableize}/_#{message_model_name.underscore}.html.erb"
        template 'views/messages/_form.html.erb', "app/views/#{message_model_name.tableize}/_form.html.erb"
        template 'views/messages/create.turbo_stream.erb',
                 "app/views/#{message_model_name.tableize}/create.turbo_stream.erb"

        # Model views
        template 'views/models/index.html.erb', "app/views/#{model_model_name.tableize}/index.html.erb"
        template 'views/models/show.html.erb', "app/views/#{model_model_name.tableize}/show.html.erb"
      end

      def create_controllers
        template 'controllers/chats_controller.rb', "app/controllers/#{chat_model_name.tableize}_controller.rb"
        template 'controllers/messages_controller.rb', "app/controllers/#{message_model_name.tableize}_controller.rb"
        template 'controllers/models_controller.rb', "app/controllers/#{model_model_name.tableize}_controller.rb"
      end

      def create_jobs
        template 'jobs/chat_response_job.rb', "app/jobs/#{chat_model_name.underscore}_response_job.rb"
      end

      def add_routes
        route "resources :#{model_model_name.tableize}, only: [:index, :show]"
        chat_routes = <<~ROUTES.strip
          resources :#{chat_model_name.tableize} do
            resources :#{message_model_name.tableize}, only: [:create]
          end
        ROUTES
        route chat_routes
      end

      def add_broadcasting_to_message_model
        msg_var = message_model_name.underscore
        chat_var = chat_model_name.underscore
        broadcasting_code = "broadcasts_to ->(#{msg_var}) { \"#{chat_var}_\#{#{msg_var}.#{chat_var}_id}\" }"

        inject_into_class "app/models/#{msg_var}.rb", message_model_name do
          "\n  #{broadcasting_code}\n"
        end
      rescue Errno::ENOENT
        say "#{message_model_name} model not found. Add broadcasting code to your model.", :yellow
        say "  #{broadcasting_code}", :yellow
      end

      def display_post_install_message
        readme 'README' if behavior == :invoke
      end
    end
  end
end
