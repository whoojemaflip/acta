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

      # Assert that running Acta.rebuild! twice produces the same projected
      # state. The block returns a snapshot of the relevant state (whatever
      # the app considers authoritative for this projection).
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
    end
  end
end
