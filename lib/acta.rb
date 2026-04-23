# frozen_string_literal: true

require_relative "acta/version"
require_relative "acta/errors"
require_relative "acta/actor"
require_relative "acta/current"
require_relative "acta/model"
require_relative "acta/serializable"
require_relative "acta/event"
require_relative "acta/schema"
require_relative "acta/record"
require_relative "acta/adapters"
require_relative "acta/events_query"
require_relative "acta/handler"
require_relative "acta/projection"
require_relative "acta/reactor"
require_relative "acta/reactor_job"
require_relative "acta/command"

module Acta
  def self.adapter
    @adapter ||= Adapters.for(Record.connection)
  end

  def self.reset_adapter!
    @adapter = nil
  end

  def self.emit(event, actor: nil, expected_sequence: nil)
    event.actor = actor if actor
    raise MissingActor, "No actor for emit of #{event.event_type} (set Acta::Current.actor or pass actor:)" if event.actor.nil?

    assert_expected_sequence!(event, expected_sequence) unless expected_sequence.nil?

    ActiveSupport::Notifications.instrument("acta.event_emitted", event:, event_type: event.event_type) do
      Record.transaction(requires_new: true) do
        record = adapter.insert_event(record_attributes_for(event))
        event.recorded_at = record.recorded_at
        dispatch(event, kind: :projection)
      end
      dispatch(event, kind: :handler)
      dispatch(event, kind: :reactor)
    end

    event
  end

  def self.subscribe(event_class, handler_class, &block)
    handlers[event_class] << { handler_class:, block:, kind: handler_kind(handler_class) }
  end

  def self.handlers
    @handlers ||= Hash.new { |h, k| h[k] = [] }
  end

  def self.dispatch(event, kind: nil)
    handlers.each do |event_class, registrations|
      next unless event.is_a?(event_class)

      registrations.each do |registration|
        next if kind && registration[:kind] != kind

        invoke(event, registration)
      end
    end
  end

  def self.invoke(event, registration)
    case registration[:kind]
    when :projection then run_projection(event, registration)
    when :reactor then run_reactor(event, registration)
    else registration[:block].call(event)
    end
  end
  private_class_method :invoke

  def self.run_projection(event, registration)
    ActiveSupport::Notifications.instrument(
      "acta.projection_applied",
      event:,
      projection_class: registration[:handler_class]
    ) do
      registration[:block].call(event)
    end
  rescue ProjectionError
    raise
  rescue StandardError => e
    raise ProjectionError.new(
      event:,
      projection_class: registration[:handler_class],
      original: e
    )
  end
  private_class_method :run_projection

  def self.run_reactor(event, registration)
    if registration[:handler_class].sync?
      ActiveSupport::Notifications.instrument(
        "acta.reactor_invoked",
        event:,
        reactor_class: registration[:handler_class],
        sync: true
      ) do
        registration[:block].call(event)
      end
    else
      ActiveSupport::Notifications.instrument(
        "acta.reactor_enqueued",
        event:,
        reactor_class: registration[:handler_class]
      ) do
        ReactorJob.perform_later(
          event_uuid: event.uuid,
          reactor_class: registration[:handler_class].name,
          event_class: event.class.name
        )
      end
    end
  end
  private_class_method :run_reactor

  def self.reset_handlers!
    @handlers = Hash.new { |h, k| h[k] = [] }
    @projection_classes = []
  end

  def self.projection_classes
    @projection_classes ||= []
  end

  def self.register_projection(klass)
    projection_classes << klass
  end

  def self.rebuild!
    projection_classes.each(&:truncate!)
    Record.order(:id).find_each do |record|
      event = events.find_by_uuid(record.uuid)
      dispatch(event, kind: :projection)
    rescue ProjectionError
      raise
    rescue StandardError => e
      raise ReplayError.new(record:, original: e)
    end
  end

  def self.handler_kind(handler_class)
    if handler_class <= Projection
      :projection
    elsif handler_class <= Reactor
      :reactor
    else
      :handler
    end
  end
  private_class_method :handler_kind

  def self.assert_expected_sequence!(event, expected)
    if event.stream_type.nil? || event.stream_key.nil?
      raise ArgumentError, "expected_sequence requires the event to declare a stream"
    end

    actual = Record
               .where(stream_type: event.stream_type, stream_key: event.stream_key)
               .maximum(:stream_sequence) || 0

    return if actual == expected

    raise ConcurrencyConflict.new(
      stream_type: event.stream_type,
      stream_key: event.stream_key,
      expected_sequence: expected,
      actual_sequence: actual
    )
  end
  private_class_method :assert_expected_sequence!

  def self.events
    EventsQuery.new(adapter.fetch_records)
  end

  def self.record_attributes_for(event)
    actor = event.actor
    {
      uuid: event.uuid,
      event_type: event.event_type,
      event_version: event.event_version,
      stream_type: event.stream_type,
      stream_key: event.stream_key,
      payload: event.payload_hash,
      actor_type: actor.type,
      actor_id: actor.id,
      source: actor.source,
      metadata: (actor.metadata.empty? ? nil : actor.metadata),
      occurred_at: event.occurred_at,
      recorded_at: Time.current
    }
  end
  private_class_method :record_attributes_for
end
