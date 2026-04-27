# frozen_string_literal: true

module Acta
  class Command < Model
    class << self
      alias_method :param, :attribute

      def call(**params)
        new(**params).call
      end

      # Declare the event class(es) this command may emit. Variadic so
      # commands that conditionally emit different events for the same
      # aggregate can list every option:
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
      # emitted — `emits` is a hint, not a contract. It exists for
      # documentation and for downstream tooling (e.g. introspection
      # of which commands write to which streams).
      def emits(*event_classes)
        raise ArgumentError, "emits requires at least one event class" if event_classes.empty?

        event_classes.each do |event_class|
          unless event_class.respond_to?(:stream_type) && event_class.respond_to?(:stream_key_attribute)
            raise ArgumentError,
                  "emits expects classes with stream_type and stream_key_attribute " \
                  "(typically Acta::Event subclasses), got #{event_class.inspect}"
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
    end

    def initialize(**params)
      super
      raise InvalidCommand, self unless valid?
    end

    # Emit an event. Pass `if_version:` to assert the stream's current
    # high-water mark for optimistic locking — see Acta.version_of.
    def emit(event, if_version: nil)
      Acta.emit(event, if_version: if_version)
    end
  end
end
