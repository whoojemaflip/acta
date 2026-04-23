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

      def expected_sequence(mode)
        raise ArgumentError, "only :loaded is currently supported" unless mode == :loaded

        @expected_sequence_mode = :loaded
      end

      attr_reader :stream_type, :stream_key_attribute, :expected_sequence_mode
    end

    def initialize(**params)
      super
      raise InvalidCommand, self unless valid?

      capture_expected_sequence! if self.class.expected_sequence_mode == :loaded
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
      Acta.emit(event, expected_sequence: @expected_sequence)
    end

    private

    def capture_expected_sequence!
      if stream_type.nil? || stream_key.nil?
        raise ConfigurationError,
              "expected_sequence :loaded on #{self.class} requires stream declaration with a present key"
      end

      @expected_sequence = Record
                             .where(stream_type:, stream_key:)
                             .maximum(:stream_sequence) || 0
    end
  end
end
