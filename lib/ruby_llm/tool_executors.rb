# frozen_string_literal: true

module RubyLLM
  # Built-in tool executors for concurrent tool execution.
  # These are registered automatically when RubyLLM is loaded.
  module ToolExecutors
    class << self
      # Registers the built-in executors.
      # Called automatically when RubyLLM is loaded.
      def register_defaults
        register_threads_executor
        register_async_executor
      end

      private

      # Thread-based executor using Ruby's native threads.
      # Uses only stdlib - no external dependencies.
      # Good for broad compatibility and CPU-bound operations.
      def register_threads_executor
        RubyLLM.register_tool_executor(:threads) do |tool_calls, max_concurrency:, &execute|
          results = {}
          mutex = Mutex.new
          semaphore = max_concurrency ? Thread::SizedQueue.new(max_concurrency) : nil

          # Fill semaphore with permits
          max_concurrency&.times { semaphore << :permit }

          threads = tool_calls.map do |tool_call|
            Thread.new do
              # Acquire permit (blocks if none available)
              permit = semaphore&.pop

              begin
                result = execute.call(tool_call)
                mutex.synchronize { results[tool_call.id] = result }
              rescue StandardError => e
                # Store error as result so LLM sees it
                error_result = "Error: #{e.class}: #{e.message}"
                mutex.synchronize { results[tool_call.id] = error_result }
                RubyLLM.logger.warn "[RubyLLM] Tool #{tool_call.id} failed: #{e.message}"
              ensure
                # Release permit
                semaphore&.push(permit) if permit
              end
            end
          end

          threads.each(&:join)
          results
        end
      end

      # Async-based executor using the async gem.
      # Uses lightweight fibers for I/O-bound operations.
      # Requires the async gem to be installed.
      def register_async_executor
        RubyLLM.register_tool_executor(:async) do |tool_calls, max_concurrency:, &execute|
          AsyncExecutor.execute(tool_calls, max_concurrency: max_concurrency, &execute)
        end
      end
    end

    # Internal implementation for async executor.
    # Separated to keep block size manageable.
    module AsyncExecutor
      class << self
        def execute(tool_calls, max_concurrency:, &block)
          load_async_gem
          run_with_sync { execute_tools(tool_calls, max_concurrency, &block) }
        end

        private

        def load_async_gem
          require 'async'
          require 'async/barrier'
          require 'async/semaphore'
        rescue LoadError => e
          raise LoadError,
                'The async gem is required for :async tool executor. ' \
                "Add `gem 'async'` to your Gemfile. Original error: #{e.message}"
        end

        def run_with_sync(&)
          # Use Kernel#Sync if available (async 2.x), otherwise Async{}.wait
          if defined?(Sync)
            Sync(&)
          else
            Async(&).wait
          end
        end

        def execute_tools(tool_calls, max_concurrency)
          semaphore = max_concurrency ? Async::Semaphore.new(max_concurrency) : nil
          barrier = Async::Barrier.new
          results = {}

          tool_calls.each do |tool_call|
            barrier.async do
              results[tool_call.id] = execute_single_tool(tool_call, semaphore) { yield tool_call }
            rescue StandardError => e
              results[tool_call.id] = "Error: #{e.class}: #{e.message}"
              RubyLLM.logger.warn "[RubyLLM] Tool #{tool_call.id} failed: #{e.message}"
            end
          end

          barrier.wait
          results
        end

        def execute_single_tool(_tool_call, semaphore, &)
          if semaphore
            semaphore.acquire(&)
          else
            yield
          end
        end
      end
    end
  end
end

# Register built-in executors when this file is loaded
RubyLLM::ToolExecutors.register_defaults
