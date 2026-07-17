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

  # Raised by `context.fail_replay!(reason)` inside an upcaster block. Halts
  # replay so the operator can investigate rather than land a partial,
  # possibly-corrupt projection.
  class ReplayHaltedByUpcaster < Error
    attr_reader :record, :reason

    def initialize(record:, reason:)
      @record = record
      @reason = reason
      super(
        "Upcaster halted replay on event id=#{record.id} uuid=#{record.uuid} " \
        "(#{record.event_type} v#{record.event_version}): #{reason}"
      )
    end
  end

  # Raised at registration time when an upcaster set is malformed — e.g.
  # `from` >= `to`, or two upcasters claim the same (event_type, from).
  class UpcasterRegistryError < Error; end

  # Raised when a record's stored event_version exceeds anything the
  # currently-loaded upcaster registry knows how to reach. Typically means
  # an older deployment is replaying events emitted by a newer one.
  class FutureSchemaVersion < Error
    attr_reader :record, :latest_known_version

    def initialize(record:, latest_known_version:)
      @record = record
      @latest_known_version = latest_known_version
      super(
        "Event id=#{record.id} uuid=#{record.uuid} (#{record.event_type}) is at " \
        "event_version #{record.event_version}, but the loaded upcaster registry " \
        "only knows up to v#{latest_known_version}. Likely an older deployment " \
        "replaying events emitted by a newer one."
      )
    end
  end
end
