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
require_relative "acta/projection_managed"
require_relative "acta/railtie" if defined?(::Rails::Railtie)

require "active_support/lazy_load_hooks"
ActiveSupport.on_load(:active_record) do
  include Acta::ProjectionManaged
end

module Acta
  def self.adapter
    @adapter ||= Adapters.for(Record.connection)
  end

  def self.reset_adapter!
    @adapter = nil
  end

  def self.emit(event, actor: nil, if_version: nil)
    event.actor = actor if actor
    raise MissingActor, "No actor for emit of #{event.event_type} (set Acta::Current.actor or pass actor:)" if event.actor.nil?

    assert_version!(event, if_version) unless if_version.nil?

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
      Projection.applying! { registration[:block].call(event) }
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
    projection_classes << klass unless projection_classes.include?(klass)
  end

  def self.rebuild!
    Projection.applying! { truncate_projections! }
    Record.order(:id).find_each do |record|
      event = events.find_by_uuid(record.uuid)
      dispatch(event, kind: :projection)
    rescue ProjectionError
      raise
    rescue StandardError => e
      raise ReplayError.new(record:, original: e)
    end
  end

  # Truncate all projections in FK-safe order. Wrapped in `Projection.applying!`
  # by `rebuild!` so projection-managed AR models (`acta_managed!`) accept the
  # delete_all calls instead of raising `ProjectionWriteError`.
  def self.truncate_projections!
    legacy, declared = projection_classes.partition { |p| p.truncated_classes.empty? }

    legacy.each(&:truncate!)
    truncate_order(declared).each(&:truncate!)
  end
  private_class_method :truncate_projections!

  # Order projections so that, for every belongs_to A → B where A and B are
  # owned by different projections, the projection owning A truncates first.
  # This deletes children before parents and keeps Acta.rebuild! safe under
  # FK constraints regardless of registration order.
  def self.truncate_order(projections)
    return projections if projections.length < 2

    owner_of = projections.each_with_object({}) do |projection, acc|
      projection.truncated_classes.each { |klass| acc[klass] = projection }
    end

    # `before[parent] = [children]`: every child projection must run before
    # the parent so the FK-bearing rows are gone by the time the parent
    # tries to delete the rows they reference.
    before = Hash.new { |h, k| h[k] = [] }
    projections.each do |child_projection|
      child_projection.truncated_classes.each do |child_class|
        child_class.reflect_on_all_associations(:belongs_to).each do |reflection|
          next if reflection.polymorphic?

          parent_class = begin
            reflection.klass
          rescue StandardError
            next
          end

          parent_owner = owner_of[parent_class]
          next if parent_owner.nil? || parent_owner == child_projection

          before[parent_owner] << child_projection unless before[parent_owner].include?(child_projection)
        end
      end
    end

    sorted = topological_sort(projections, before)
    sorted || raise(TruncateOrderError.new(projections))
  end
  private_class_method :truncate_order

  # Given `before[node] = [predecessors]`, returns nodes ordered so each
  # predecessor appears before the node it constrains, or nil if the graph
  # has a cycle. Stable: preserves input order among nodes that don't
  # constrain each other.
  def self.topological_sort(nodes, before)
    visited = {}
    result = []

    visit = lambda do |node|
      case visited[node]
      when :done then return true
      when :visiting then return false
      end

      visited[node] = :visiting
      before[node].each { |predecessor| return false unless visit.call(predecessor) }
      visited[node] = :done
      result << node
      true
    end

    nodes.each { |node| return nil unless visit.call(node) }

    result
  end
  private_class_method :topological_sort

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

  # Public: read the current high-water mark for a stream. Returns 0 for
  # streams that have never been emitted to. Use the result with
  # `Acta.emit(..., if_version: version)` for optimistic locking.
  def self.version_of(stream_type:, stream_key:)
    Record
      .where(stream_type: stream_type.to_s, stream_key: stream_key)
      .maximum(:stream_sequence) || 0
  end

  def self.assert_version!(event, expected)
    if event.stream_type.nil? || event.stream_key.nil?
      raise ArgumentError, "if_version requires the event to declare a stream"
    end

    actual = version_of(stream_type: event.stream_type, stream_key: event.stream_key)
    return if actual == expected

    raise VersionConflict.new(
      stream_type: event.stream_type,
      stream_key: event.stream_key,
      expected_version: expected,
      actual_version: actual
    )
  end
  private_class_method :assert_version!

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

# The web admin engine is opt-in: required only when the host runs Rails.
# Loading it unconditionally would pull in ActionController etc. for
# non-Rails consumers (background jobs, scripts).
require_relative "acta/web" if defined?(::Rails)
