# frozen_string_literal: true

require 'rails/generators'

module RubyLLM
  module Generators
    # Generates a simple chat UI scaffold for RubyLLM
    class ChatUIGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      namespace 'ruby_llm:chat_ui'

      def create_views
        # Chat views
        template 'views/chats/index.html.erb', 'app/views/chats/index.html.erb'
        template 'views/chats/new.html.erb', 'app/views/chats/new.html.erb'
        template 'views/chats/show.html.erb', 'app/views/chats/show.html.erb'
        template 'views/chats/_chat.html.erb', 'app/views/chats/_chat.html.erb'
        template 'views/chats/_form.html.erb', 'app/views/chats/_form.html.erb'

        # Message views
        template 'views/messages/_message.html.erb', 'app/views/messages/_message.html.erb'
        template 'views/messages/_form.html.erb', 'app/views/messages/_form.html.erb'
        template 'views/messages/create.turbo_stream.erb', 'app/views/messages/create.turbo_stream.erb'

        # Model views
        template 'views/models/index.html.erb', 'app/views/models/index.html.erb'
        template 'views/models/show.html.erb', 'app/views/models/show.html.erb'
      end

      def create_controllers
        template 'controllers/chats_controller.rb', 'app/controllers/chats_controller.rb'
        template 'controllers/messages_controller.rb', 'app/controllers/messages_controller.rb'
        template 'controllers/models_controller.rb', 'app/controllers/models_controller.rb'
      end

      def create_jobs
        template 'jobs/chat_response_job.rb', 'app/jobs/chat_response_job.rb'
      end

      def add_routes
        route 'resources :models, only: [:index, :show]'
        route "resources :chats do\n    resources :messages, only: [:create]\n  end"
      end

      def display_post_install_message
        readme 'README' if behavior == :invoke
      end
    end
  end
end
