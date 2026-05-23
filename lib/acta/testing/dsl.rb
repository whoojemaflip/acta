# frozen_string_literal: true

module Acta
  module Testing
    module DSL
      # Seed prior events. Anything emitted inside the block is treated as
      # pre-existing history; the baseline is set after the block runs so
      # subsequent assertions only see events from the 'when' phase.
      def given_events(&block)
        block.call if block
        @_acta_baseline_count = Acta::Record.count
      end

      # Invoke a command instance and capture what it emitted.
      def when_command(command)
        @_acta_baseline_count ||= Acta::Record.count
        command.call
        @_acta_emitted_events = Acta.events.all.drop(@_acta_baseline_count)
        @_acta_matched_events = []
      end

      # Evaluate a block that emits events, capturing them for assertions.
      def when_event(&block)
        @_acta_baseline_count ||= Acta::Record.count
        block.call
        @_acta_emitted_events = Acta.events.all.drop(@_acta_baseline_count)
        @_acta_matched_events = []
      end

      # Assert that at least one of the captured events matches the class
      # and attributes. Marks the matched event so `then_emitted_nothing_else`
      # can verify the remainder.
      def then_emitted(event_class, **attributes)
        @_acta_matched_events ||= []
        event = @_acta_emitted_events.find do |e|
          e.is_a?(event_class) &&
            attributes.all? { |k, v| e.public_send(k) == v } &&
            !@_acta_matched_events.include?(e)
        end

        emitted_classes = @_acta_emitted_events.map(&:class).inspect
        expect(event).not_to(
          be_nil,
          "expected emission of #{event_class} matching #{attributes.inspect}, but emitted: #{emitted_classes}"
        )

        @_acta_matched_events << event
      end

      # Assert no emissions remain unmatched.
      def then_emitted_nothing_else
        @_acta_matched_events ||= []
        remaining = @_acta_emitted_events - @_acta_matched_events
        expect(remaining).to(
          be_empty,
          "expected no further emissions, but also emitted: #{remaining.map(&:class).inspect}"
        )
      end

      # Run the block with a different Acta::Current.actor, restoring the
      # previous actor afterward (even if the block raises). Useful for
      # asserting an emit attributes the right user when the surrounding
      # spec's default actor would otherwise overwrite it.
      def with_actor(**attributes)
        previous = Acta::Current.actor
        Acta::Current.actor = Acta::Actor.new(**attributes)
        yield
      ensure
        Acta::Current.actor = previous
      end

      # Assert that running Acta.rebuild! twice produces the same projected
      # state. The block returns a snapshot of the relevant state (whatever
      # the app considers authoritative for this projection).
      #
      # Implicitly exercises any registered upcasters — both passes go
      # through the same pipeline, so impure upcasters (state leaking
      # outside the per-replay context) surface as a diff.
      def ensure_replay_deterministic(&snapshot)
        Acta.rebuild!
        first = snapshot.call
        Acta.rebuild!
        second = snapshot.call

        expect(second).to(
          eq(first),
          "replay is not deterministic\n" \
          "first pass:  #{first.inspect}\n" \
          "second pass: #{second.inspect}"
        )
      end

      # Insert an event row directly into the store, bypassing `Acta.emit`.
      # Used by upcaster specs to seed events at arbitrary `event_version`
      # values — `Acta.emit` always stamps the current code's version, so
      # it can't simulate a pre-migration row.
      #
      #   acta_seed_event(type: "ItemAdded", event_version: 1,
      #                   payload: { "item_id" => "g_1", "item_type" => "goal" })
      def acta_seed_event(type:, payload:, event_version: 1, actor: nil,
                          stream_type: nil, stream_key: nil, occurred_at: nil, uuid: nil)
        actor ||= Acta::Current.actor || Acta::Actor.new(
          type: "system", id: "rspec", source: "test"
        )

        Acta::Record.create!(
          uuid: uuid || SecureRandom.uuid,
          event_type: type.to_s,
          event_version: event_version,
          payload: payload,
          actor_type: actor.type,
          actor_id: actor.id,
          source: actor.source,
          metadata: actor.metadata.empty? ? nil : actor.metadata,
          stream_type: stream_type&.to_s,
          stream_key: stream_key,
          occurred_at: occurred_at || Time.current,
          recorded_at: Time.current
        )
      end

      # End-to-end upcaster fixture: register upcasters, seed events at the
      # given versions, run `Acta.rebuild!`. The caller asserts on whatever
      # projection state matters for the migration under test.
      #
      #   acta_replay(
      #     upcasters: [Scaff::WorkspaceMigrationUpcasters],
      #     events: [
      #       { type: "Scaff::ItemCreated", event_version: 1,
      #         payload: { "item_id" => "g_1", "item_type" => "goal", "title" => "Foo" } },
      #       { type: "Scaff::ItemCreated", event_version: 1,
      #         payload: { "item_id" => "i_2", "parent_id" => "g_1", "title" => "Bar" } }
      #     ]
      #   )
      #   expect(Workspace.pluck(:id)).to eq(%w[g_1])
      def acta_replay(events:, upcasters: [])
        upcasters.each { |u| Acta.register_upcaster(u) }
        events.each { |attrs| acta_seed_event(**attrs) }
        Acta.rebuild!
      end
    end
  end
end
