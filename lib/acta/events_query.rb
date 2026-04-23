# frozen_string_literal: true

module Acta
  class EventsQuery
    def initialize(scope)
      @scope = scope
    end

    def last
      hydrate(@scope.last)
    end

    def first
      hydrate(@scope.first)
    end

    def find_by_uuid(uuid)
      hydrate(@scope.find_by(uuid:))
    end

    def all
      @scope.map { |record| hydrate(record) }
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

    private

    def hydrate(record)
      return nil unless record

      klass = begin
        Object.const_get(record.event_type)
      rescue NameError
        raise Acta::UnknownEventType, record.event_type
      end

      payload = (record.payload || {}).transform_keys(&:to_sym)
      envelope = {
        uuid: record.uuid,
        occurred_at: record.occurred_at,
        recorded_at: record.recorded_at,
        actor: build_actor(record)
      }
      klass.new(**envelope, **payload)
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
