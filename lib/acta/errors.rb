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

  class VersionConflict < Error
    attr_reader :stream_type, :stream_key, :expected_version, :actual_version

    def initialize(stream_type:, stream_key:, expected_version:, actual_version:)
      @stream_type = stream_type
      @stream_key = stream_key
      @expected_version = expected_version
      @actual_version = actual_version
      super(
        "Version conflict on stream #{stream_type}/#{stream_key}: " \
        "expected version #{expected_version}, stream is at version #{actual_version}"
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

  class ProjectionWriteError < Error
    attr_reader :model_class, :write_method

    def initialize(model_class:, write_method:)
      @model_class = model_class
      @write_method = write_method
      super(
        "Direct #{write_method} on #{model_class.name} bypasses the event log. " \
        "#{model_class.name} is acta_managed! — its rows are owned by an Acta::Projection. " \
        "Emit an event so the projection can update the row, or wrap intentional " \
        "out-of-band writes in `Acta::Projection.applying! { ... }` (fixtures, migrations, backfills)."
      )
    end
  end
end
