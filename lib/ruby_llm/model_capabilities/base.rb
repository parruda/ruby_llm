# frozen_string_literal: true

module RubyLLM
  module ModelCapabilities
    # Base class defining the interface for model-specific capabilities
    class Base
      def determine_context_window(_model_id)
        raise NotImplementedError
      end

      def determine_max_tokens(_model_id)
        raise NotImplementedError
      end

      def get_input_price(_model_id)
        raise NotImplementedError
      end

      def get_output_price(_model_id)
        raise NotImplementedError
      end

      def supports_vision?(_model_id)
        raise NotImplementedError
      end

      def supports_functions?(_model_id)
        raise NotImplementedError
      end

      def supports_json_mode?(_model_id)
        raise NotImplementedError
      end
    end
  end
end
