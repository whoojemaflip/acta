# frozen_string_literal: true

module Acta
  class Error < StandardError; end

  class InvalidEvent < Error
    attr_reader :event

    def initialize(event)
      @event = event
      super("Event is invalid: #{event.errors.full_messages.join(', ')}")
    end
  end

  class CommandError < Error; end

  class InvalidCommand < CommandError
    attr_reader :command

    def initialize(command)
      @command = command
      super("Command #{command.class} is invalid: #{command.errors.full_messages.join(', ')}")
    end
  end

  class ProjectionError < Error
    attr_reader :event, :projection_class, :original

    def initialize(event:, projection_class:, original:)
      @event = event
      @projection_class = projection_class
      @original = original
      super("Projection #{projection_class} failed on #{event.event_type}: #{original.message}")
    end
  end

  class ConcurrencyConflict < Error
    attr_reader :stream_type, :stream_key, :expected_sequence, :actual_sequence

    def initialize(stream_type:, stream_key:, expected_sequence:, actual_sequence:)
      @stream_type = stream_type
      @stream_key = stream_key
      @expected_sequence = expected_sequence
      @actual_sequence = actual_sequence
      super(
        "Concurrent write on stream #{stream_type}/#{stream_key}: " \
        "expected to write at sequence #{expected_sequence}, stream is at #{actual_sequence}"
      )
    end
  end

  class MissingActor < Error; end
  class ConfigurationError < Error; end
  class AdapterError < Error; end

  class UnknownEventType < Error
    attr_reader :event_type

    def initialize(event_type)
      @event_type = event_type
      super("Unknown event type #{event_type.inspect} — class is not loaded")
    end
  end

  class ReplayError < Error
    attr_reader :record, :original

    def initialize(record:, original:)
      @record = record
      @original = original
      super("Replay failed on event id=#{record.id} uuid=#{record.uuid} (#{record.event_type}): #{original.message}")
    end
  end

  class TruncateOrderError < Error
    attr_reader :projections

    def initialize(projections)
      @projections = projections
      super(
        "Cannot determine a safe truncate order for projections #{projections.map(&:name).inspect} — " \
        "their declared `truncates` classes form a foreign-key cycle. " \
        "Either break the cycle or have one projection truncate the other's tables itself."
      )
    end
  end
end
