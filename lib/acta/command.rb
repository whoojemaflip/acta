# frozen_string_literal: true

module Acta
  class Command < Model
    class << self
      alias_method :param, :attribute

      # Instantiate the command with the given params, run it, and return
      # the command instance. Callers that need to know what the command
      # emitted read it back off the instance:
      #
      #   cmd = CreateOrder.call(customer_id: "c_1")
      #   cmd.emitted_events                              # => [<OrderCreated …>]
      #   cmd.emitted_events.find { _1.is_a?(OrderCreated) }.order_id
      #
      # Returning the instance keeps the framework honest about
      # multiplicity — commands can emit zero, one, or many events, and
      # the caller (who knows the domain) picks what matters. The
      # framework does not invent a "primary" event.
      def call(**params)
        instance = new(**params)
        instance.call
        instance
      end
    end

    def initialize(**params)
      super
      raise InvalidCommand, self unless valid?
    end

    # Emit an event. Pass `if_version:` to assert the stream's current
    # high-water mark for optimistic locking — see Acta.version_of.
    def emit(event, if_version: nil)
      Acta.emit(event, if_version: if_version)
      emitted_events << event
      event
    end

    # Every event emitted during this command instance's invocation, in
    # the order `emit` was called. Empty until #call runs; cascading
    # commands invoked from inside #call produce events in their own
    # instances, not this one.
    def emitted_events
      @emitted_events ||= []
    end
  end
end
