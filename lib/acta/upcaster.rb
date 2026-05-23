# frozen_string_literal: true

module Acta
  # Replay-time event transformation. Apps declare upcasters when an event
  # type's shape changes between schema versions; the pipeline transforms
  # stored records on read so projections see them at the latest shape.
  # See `docs/upcasters.md` for the end-to-end recipe.
  #
  #   module Scaff
  #     class WorkspaceMigrationUpcasters
  #       include Acta::Upcaster
  #
  #       upcasts "Scaff::ItemCreated", from: 1, to: 2 do |event, context|
  #         payload = event.payload
  #         if payload["item_type"] == "goal"
  #           context[:goal_to_workspace][payload["item_id"]] = payload["item_id"]
  #           event.upcast_to(
  #             type: "Scaff::WorkspaceCreated",
  #             payload: { "workspace_id" => payload["item_id"], "title" => payload["title"] },
  #             schema_version: 2
  #           )
  #         else
  #           event.upcast_to(payload: payload.merge("workspace_id" => "..."), schema_version: 2)
  #         end
  #       end
  #     end
  #   end
  #
  #   Acta.register_upcaster(Scaff::WorkspaceMigrationUpcasters)
  #
  # Upcasters run pre-hydration during every read (`Acta.rebuild!`,
  # `ReactorJob#perform`, the events admin, test fixtures) — apps can
  # safely delete an old event class once a rename upcaster is in place.
  # The live emit path is exempt: emitted events carry the current code's
  # `event_version` and are dispatched in-memory before any read happens.
  module Upcaster
    # Identity sentinel — `upcasts "Foo", from: N, to: N, &Acta::Upcaster::NO_OP`
    # declares the post-migration record at version N as a no-op pass-through
    # (e.g. a `GoalPromotedToWorkspace` event whose effect is already produced
    # by upcasting earlier events).
    NO_OP = lambda { |event, _context| event }.freeze

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Declare a transform. `from` and `to` are integer schema versions on
      # the same event type; `to` must be >= `from`. The block receives an
      # upcast-shaped record and the per-replay context, and must return
      # either a single upcasted record, an array (1-to-many — each branch
      # continues chaining independently), `nil`/`[]` (drop on replay), or
      # call `context.fail_replay!(reason)`.
      def upcasts(event_type, from:, to:, &block)
        raise UpcasterRegistryError, "from must be an Integer" unless from.is_a?(Integer)
        raise UpcasterRegistryError, "to must be an Integer" unless to.is_a?(Integer)
        raise UpcasterRegistryError, "to (#{to}) must be >= from (#{from})" if to < from
        raise UpcasterRegistryError, "block required for upcasts(#{event_type.inspect}, from: #{from}, to: #{to})" unless block

        upcaster_registrations << { event_type: event_type.to_s, from:, to:, block: }
      end

      def upcaster_registrations
        @upcaster_registrations ||= []
      end
    end

    # Per-replay state carrier passed to every upcaster block. Hash-shaped
    # by default — `context[:goal_to_workspace] ||= {}`. Lives the length
    # of one replay; never persisted across runs.
    class Context
      class FailReplay < StandardError; end

      def initialize
        @store = {}
      end

      def [](key)
        @store[key] ||= {}
      end

      def []=(key, value)
        @store[key] = value
      end

      def key?(key)
        @store.key?(key)
      end

      # Halt the replay with a clear reason. Wrapped by the pipeline into
      # `Acta::ReplayHaltedByUpcaster`, which carries the offending record.
      def fail_replay!(reason)
        raise FailReplay, reason
      end
    end

    # In-memory record shape passed to upcaster blocks. Wraps a backing
    # `Acta::Record` (the row as stored) with optional overlays for
    # `event_type`, `event_version`, and `payload` — upcasters mutate
    # *only* the overlays, never the stored row.
    class View
      ENVELOPE_FIELDS = %i[id uuid occurred_at recorded_at actor_type actor_id source metadata stream_type stream_key stream_sequence].freeze

      attr_reader :base, :event_type, :event_version, :payload

      def initialize(base, event_type: nil, event_version: nil, payload: nil)
        @base = base
        @event_type = event_type || base.event_type
        @event_version = event_version || base.event_version
        @payload = payload || (base.payload || {})
      end

      ENVELOPE_FIELDS.each do |field|
        define_method(field) { base.public_send(field) }
      end

      # Produce a new View with the supplied attributes overlaid. `type`
      # defaults to the current event_type; `payload` defaults to the
      # current payload; `schema_version` is required and replaces
      # `event_version`. The original (and the underlying Record) are
      # untouched.
      def upcast_to(type: nil, payload: nil, schema_version:)
        raise ArgumentError, "schema_version required" if schema_version.nil?

        View.new(
          base,
          event_type: type || @event_type,
          event_version: schema_version,
          payload: payload || @payload
        )
      end
    end

    # Holds the merged set of `(event_type, from) → block` entries from
    # every registered upcaster class. Also tracks the max `to` per event
    # type so the pipeline can flag future-version records cleanly.
    class Registry
      def initialize
        @by_key = {}
        @latest_to = Hash.new(0)
        @registered_classes = []
      end

      def register(upcaster_class)
        return if @registered_classes.include?(upcaster_class)

        upcaster_class.upcaster_registrations.each do |reg|
          key = [ reg[:event_type], reg[:from] ]
          if @by_key.key?(key)
            existing = @by_key[key]
            raise UpcasterRegistryError,
                  "Conflicting upcasters for #{reg[:event_type].inspect} v#{reg[:from]}: " \
                  "#{existing[:owner].name} already registered the (event_type, from) pair; " \
                  "#{upcaster_class.name} tried to register it again."
          end

          @by_key[key] = reg.merge(owner: upcaster_class)
          @latest_to[reg[:event_type]] = [ @latest_to[reg[:event_type]], reg[:to] ].max
        end

        @registered_classes << upcaster_class
      end

      def find(event_type, from)
        @by_key[[ event_type, from ]]
      end

      def latest_for(event_type)
        @latest_to[event_type]
      end

      def empty?
        @by_key.empty?
      end

      def clear!
        @by_key.clear
        @latest_to.clear
        @registered_classes.clear
      end
    end

    # Walk a record through every matching upcaster, returning 0..N
    # upcasted records. Identity when no upcaster matches. Handles:
    #   - chain:        block returns a single record → loop continues at new (event_type, event_version)
    #   - 1-to-many:    block returns an array       → each branch recurses (so chaining + fan-out compose)
    #   - drop:         block returns nil or []      → record produces no projection input
    #   - fail:         block calls `context.fail_replay!` → halts with `ReplayHaltedByUpcaster`
    #   - future ver:   stored event_version exceeds anything we can reach → `FutureSchemaVersion`
    def self.upcast(record, context, registry: Acta.upcaster_registry)
      origin = record.respond_to?(:base) ? record.base : record
      current = record.is_a?(View) ? record : View.new(record)
      return [ current ] if registry.empty?

      loop do
        reg = registry.find(current.event_type, current.event_version)

        unless reg
          known_max = registry.latest_for(current.event_type)
          if known_max.positive? && current.event_version > known_max
            raise FutureSchemaVersion.new(record: origin, latest_known_version: known_max)
          end

          break
        end

        result = begin
          reg[:block].call(current, context)
        rescue Context::FailReplay => e
          raise ReplayHaltedByUpcaster.new(record: origin, reason: e.message)
        end

        return [] if result.nil? || (result.is_a?(Array) && result.empty?)

        if result.is_a?(Array)
          return result.flat_map { |branch| upcast(branch, context, registry: registry) }
        end

        unless result.is_a?(View)
          raise UpcasterRegistryError,
                "Upcaster #{reg[:owner].name} for #{current.event_type} v#{current.event_version} " \
                "returned #{result.class} — expected an Acta::Upcaster::View " \
                "(use `event.upcast_to(...)` to produce one)."
        end

        if result.event_version == current.event_version && result.event_type == current.event_type
          # Identity at the current version (e.g. NO_OP). Stop the loop —
          # otherwise we'd recurse forever on the same (type, version) key.
          current = result
          break
        end

        current = result
      end

      [ current ]
    end
  end
end
