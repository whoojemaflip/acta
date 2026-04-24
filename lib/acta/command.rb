# frozen_string_literal: true

module Acta
  class Command < Model
    class << self
      alias_method :param, :attribute

      def call(**params)
        new(**params).call
      end

      def stream(type, key:)
        @stream_type = type.to_s
        @stream_key_attribute = key
      end

      # Declare how the command handles concurrent writes to its stream.
      #
      #   on_concurrent_write :raise   # capture sequence, raise ConcurrencyConflict on drift
      #   on_concurrent_write :ignore  # explicit opt-out — write unconditionally
      #
      # :raise captures the stream's current sequence at instantiation and
      # asserts it hasn't moved by the time emit runs. :ignore is the same
      # runtime behaviour as omitting the declaration entirely, but it
      # documents intent: the command's author considered concurrency on
      # this aggregate and decided last-write-wins is acceptable.
      VALID_CONCURRENT_WRITE_ACTIONS = %i[ raise ignore ].freeze

      def on_concurrent_write(action)
        unless VALID_CONCURRENT_WRITE_ACTIONS.include?(action)
          raise ArgumentError,
                "on_concurrent_write must be one of #{VALID_CONCURRENT_WRITE_ACTIONS.inspect}, got #{action.inspect}"
        end

        @concurrent_write_action = action
      end

      attr_reader :stream_type, :stream_key_attribute, :concurrent_write_action
    end

    def initialize(**params)
      super
      raise InvalidCommand, self unless valid?

      capture_stream_sequence! if self.class.concurrent_write_action == :raise
    end

    def stream_type
      self.class.stream_type
    end

    def stream_key
      attribute = self.class.stream_key_attribute
      return nil if attribute.nil?

      public_send(attribute)
    end

    def emit(event)
      Acta.emit(event, expected_sequence: @captured_sequence)
    end

    private

    def capture_stream_sequence!
      if stream_type.nil? || stream_key.nil?
        raise ConfigurationError,
              "on_concurrent_write on #{self.class} requires a stream declaration with a present key"
      end

      @captured_sequence = Record
                             .where(stream_type:, stream_key:)
                             .maximum(:stream_sequence) || 0
    end
  end
end
