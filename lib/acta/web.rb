# frozen_string_literal: true

module Acta
  module Web
    # Raised when the engine is mounted without `base_controller_class`
    # being set. Without a configured parent, the engine's controllers
    # would inherit ActionController::Base directly — meaning the event
    # log is publicly accessible. Fail loudly at request time so the
    # mistake surfaces in development before reaching production.
    class ConfigurationError < StandardError; end

    class << self
      # The host-app controller class (as a String) that engine controllers
      # should inherit from. Set this to your `ApplicationController` (or any
      # base controller that enforces authentication) before mounting:
      #
      #   # config/initializers/acta_web.rb
      #   Acta::Web.base_controller_class = "ApplicationController"
      #
      # No default is provided: a misconfigured mount would expose the
      # entire event log without authentication.
      def base_controller_class
        @base_controller_class || raise(
          ConfigurationError,
          "Acta::Web.base_controller_class is not set. Configure it before " \
          "mounting the engine, e.g. in config/initializers/acta_web.rb:\n\n" \
          "    Acta::Web.base_controller_class = \"ApplicationController\"\n\n" \
          "Set it to a controller class that enforces authentication so the " \
          "event log isn't publicly accessible."
        )
      end

      def base_controller_class=(klass)
        @base_controller_class = klass
      end

      # Test/reset hook — clears the configured controller class. Mainly for specs.
      def reset_configuration!
        @base_controller_class = nil
      end
    end
  end
end

require_relative "web/engine"
