# frozen_string_literal: true

module Acta
  class Command < Model
    class << self
      alias_method :param, :attribute

      def call(**params)
        new(**params).call
      end

      # Declare the aggregate this command operates on. Two forms:
      #
      #   stream :order, key: :order_id       # explicit declaration
      #   emits OrderPlaced                    # inherit from the event class
      #
      # When both are given, the explicit `stream` takes precedence.
      def stream(type, key:)
        @stream_type = type.to_s
        @stream_key_attribute = key
      end

      # Declare the event class(es) this command might emit. The command
      # inherits stream_type and stream_key_attribute from the FIRST event,
      # removing the duplicate declaration in the common case:
      #
      #   class OrderRenamed < Acta::Event
      #     stream :order, key: :order_id
      #     # ...
      #   end
      #
      #   class RenameOrder < Acta::Command
      #     emits OrderRenamed
      #     on_concurrent_write :raise
      #     # ...
      #   end
      #
      # Commands that conditionally emit different events for the same
      # aggregate can list them all — handy for documentation and so the
      # `emits` line stops being a half-truth:
      #
      #   class RegisterTrail < Acta::Command
      #     emits TrailRegistered, TrailUpdated
      #
      #     def call
      #       existing = Trail.find_by(id:)
      #       existing ? emit(TrailUpdated.new(...)) : emit(TrailRegistered.new(...))
      #     end
      #   end
      #
      # The runtime does not enforce that only the listed events are
      # emitted — `emits` is a hint, not a contract. List the events that
      # share the same aggregate (and therefore the same stream config),
      # or use the explicit `stream :type, key: :attr` form when the
      # command emits across multiple aggregates.
      def emits(*event_classes)
        if event_classes.empty?
          raise ArgumentError, "emits requires at least one event class"
        end

        event_classes.each do |event_class|
          unless event_class.respond_to?(:stream_type) && event_class.respond_to?(:stream_key_attribute)
            raise ArgumentError,
                  "emits expects classes with stream_type and stream_key_attribute (typically Acta::Event subclasses), got #{event_class.inspect}"
          end
        end

        @emitted_event_classes = event_classes
      end

      def emitted_event_classes
        @emitted_event_classes || []
      end

      def emitted_event_class
        emitted_event_classes.first
      end

      attr_reader :concurrent_write_action

      def stream_type
        @stream_type || emitted_event_class&.stream_type
      end

      def stream_key_attribute
        @stream_key_attribute || emitted_event_class&.stream_key_attribute
      end

      # Declare how the command handles concurrent writes to its stream.
      #
      #   on_concurrent_write :raise   # capture sequence, raise ConcurrencyConflict on drift
      #   on_concurrent_write :ignore  # explicit opt-out — write unconditionally
      VALID_CONCURRENT_WRITE_ACTIONS = %i[ raise ignore ].freeze

      def on_concurrent_write(action)
        unless VALID_CONCURRENT_WRITE_ACTIONS.include?(action)
          raise ArgumentError,
                "on_concurrent_write must be one of #{VALID_CONCURRENT_WRITE_ACTIONS.inspect}, got #{action.inspect}"
        end

        @concurrent_write_action = action
      end
    end

    def initialize(**params)
      super
      raise InvalidCommand, self unless valid?

      capture_stream_sequence! if self.class.concurrent_write_action == :raise
    end

    def stream_type
      self.class.stream_type
    end

    def stream_key
      attribute = self.class.stream_key_attribute
      return nil if attribute.nil?

      public_send(attribute)
    end

    def emit(event)
      Acta.emit(event, expected_sequence: @captured_sequence)
    end

    private

    def capture_stream_sequence!
      if stream_type.nil? || stream_key.nil?
        raise ConfigurationError,
              "on_concurrent_write on #{self.class} requires a stream declaration (via `stream` or `emits`) with a present key"
      end

      @captured_sequence = Record
                             .where(stream_type:, stream_key:)
                             .maximum(:stream_sequence) || 0
    end
  end
end
