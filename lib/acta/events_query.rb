# frozen_string_literal: true

module Acta
  class EventsQuery
    def initialize(scope)
      @scope = scope
    end

    def last
      upcast_and_hydrate_one(@scope.last)
    end

    def first
      upcast_and_hydrate_one(@scope.first)
    end

    def find_by_uuid(uuid)
      upcast_and_hydrate_one(@scope.find_by(uuid:))
    end

    # Iterates the full scope through the upcaster pipeline with a SINGLE
    # shared context across every record, matching `Acta.rebuild!` semantics.
    # Stateful upcasters (those that resolve later events from state seeded
    # by earlier ones) depend on this. Single-record lookups
    # (`find_by_uuid`, `first`, `last`) deliberately use a fresh context —
    # there is no prior history to seed it with — and may produce
    # incomplete output for stateful upcasters. See `docs/upcasters.md`.
    def all
      context = Upcaster::Context.new
      @scope.flat_map { |record| upcast_and_hydrate(record, context) }
    end

    def count
      @scope.count
    end

    def each(&)
      all.each(&)
    end

    include Enumerable

    def for_stream(type:, key:)
      filtered = @scope
                   .where(stream_type: type.to_s, stream_key: key)
                   .reorder(:stream_sequence)
      self.class.new(filtered)
    end

    # Run a single record through the upcaster pipeline and hydrate every
    # output into a typed Acta::Event. Returns an Array (length 0..N) —
    # callers that expect one event (the historic shape) should use the
    # find_by_uuid/first/last helpers above, which apply a fresh context
    # per call and unwrap to a single event (raising if upcasters drop or
    # fan out, since those shapes aren't meaningful for one-record reads).
    #
    # Acta.rebuild! supplies a single shared context for the full pass.
    def upcast_and_hydrate(record, context)
      Upcaster.upcast(record, context).map { |view| hydrate(view) }
    end

    private

    # Single-record helper used by the public lookup methods. Drop and
    # fan-out are rejected here — `find_by_uuid(x)` returning either nil
    # (when an upcaster dropped) or an array (when it fanned out) would
    # silently break every existing caller. Live emit and tests reach for
    # this surface assuming one record → one event.
    def upcast_and_hydrate_one(record)
      return nil unless record

      results = upcast_and_hydrate(record, fresh_context)

      case results.length
      when 0
        nil
      when 1
        results.first
      else
        raise UpcasterRegistryError,
              "Upcaster fan-out (#{results.length} events) is not supported on " \
              "single-record reads of #{record.event_type} uuid=#{record.uuid}; " \
              "use Acta.rebuild! or EventsQuery#each, which iterate the pipeline."
      end
    end

    def fresh_context
      Upcaster::Context.new
    end

    def hydrate(record)
      return nil unless record

      klass = begin
        Object.const_get(record.event_type)
      rescue NameError
        raise Acta::UnknownEventType, record.event_type
      end

      envelope = {
        uuid: record.uuid,
        occurred_at: record.occurred_at,
        recorded_at: record.recorded_at,
        actor: build_actor(record)
      }
      klass.from_acta_record(envelope:, payload: record.payload || {})
    end

    def build_actor(record)
      return nil if record.actor_type.nil?

      Actor.new(
        type: record.actor_type,
        id: record.actor_id,
        source: record.source,
        metadata: record.metadata || {}
      )
    end
  end
end
