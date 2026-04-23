# frozen_string_literal: true

require "securerandom"
require "active_support/core_ext/time"

module Acta
  class Event < Model
    attr_accessor :uuid, :occurred_at, :recorded_at, :actor

    ENVELOPE_KEYS = %i[ uuid occurred_at recorded_at actor ].freeze

    def initialize(**attrs)
      envelope = attrs.slice(*ENVELOPE_KEYS)
      payload = attrs.except(*ENVELOPE_KEYS)

      @uuid = envelope[:uuid] || SecureRandom.uuid
      @occurred_at = envelope[:occurred_at] || Time.current
      @recorded_at = envelope[:recorded_at]
      @actor = envelope.key?(:actor) ? envelope[:actor] : Acta::Current.actor

      super(**payload)

      raise InvalidEvent, self unless valid?
    end

    def event_type
      self.class.event_type
    end

    def event_version
      self.class.event_version
    end

    def payload_hash
      to_acta_hash
    end

    def self.event_type
      name
    end

    def self.event_version
      1
    end

    def self.stream(type, key:)
      @stream_type = type.to_s
      @stream_key_attribute = key
    end

    class << self
      attr_reader :stream_type, :stream_key_attribute
    end

    def stream_type
      self.class.stream_type
    end

    def stream_key
      attribute = self.class.stream_key_attribute
      return nil if attribute.nil?

      public_send(attribute)
    end
  end
end
