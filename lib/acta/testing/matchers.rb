# frozen_string_literal: true

require "rspec/expectations"

RSpec::Matchers.define :emit do |event_class|
  supports_block_expectations

  match do |block|
    before_count = Acta::Record.count
    block.call
    @actual_events = Acta.events.all.drop(before_count)

    matching = @actual_events.select { |event| event.is_a?(event_class) }

    if @expected_attributes
      @matching_event = matching.find do |event|
        @expected_attributes.all? { |k, v| event.public_send(k) == v }
      end
      !@matching_event.nil?
    else
      !matching.empty?
    end
  end

  chain :with do |attributes|
    @expected_attributes = attributes
  end

  failure_message do
    detail = if @expected_attributes
               "#{event_class} with attributes #{@expected_attributes.inspect}"
    else
               event_class.to_s
    end
    "expected block to emit #{detail}, but emitted: #{@actual_events.map(&:class).inspect}"
  end

  failure_message_when_negated do
    "expected block not to emit #{event_class}, but emitted: #{@actual_events.map(&:class).inspect}"
  end
end

RSpec::Matchers.define :emit_events do |expected_classes|
  supports_block_expectations

  match do |block|
    before_count = Acta::Record.count
    block.call
    @actual_events = Acta.events.all.drop(before_count)
    @actual_classes = @actual_events.map(&:class)

    @actual_classes == expected_classes
  end

  failure_message do
    "expected block to emit events #{expected_classes.inspect} in order, but emitted: #{@actual_classes.inspect}"
  end
end

RSpec::Matchers.define :emit_any_events do
  supports_block_expectations

  match do |block|
    before_count = Acta::Record.count
    block.call
    @actual_events = Acta.events.all.drop(before_count)
    !@actual_events.empty?
  end

  failure_message do
    "expected block to emit events, but emitted none"
  end

  failure_message_when_negated do
    "expected block not to emit events, but emitted: #{@actual_events.map(&:class).inspect}"
  end
end
