# frozen_string_literal: true

module Acta
  module Web
    class << self
      def base_controller_class
        @base_controller_class || "ActionController::Base"
      end

      def base_controller_class=(klass)
        @base_controller_class = klass
      end
    end
  end
end

require_relative "web/engine"
