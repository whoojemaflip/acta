# frozen_string_literal: true

module Acta
  class Actor
    attr_reader :type, :id, :source, :metadata

    def initialize(type:, id: nil, source: nil, metadata: {})
      raise ArgumentError, "Acta::Actor type must be a non-empty string" if type.nil? || type.to_s.empty?

      @type = type.to_s
      @id = id
      @source = source
      @metadata = metadata
    end

    def to_h
      { type:, id:, source:, metadata: }
    end

    def ==(other)
      other.is_a?(self.class) && to_h == other.to_h
    end
    alias_method :eql?, :==

    def hash
      to_h.hash
    end

    def self.from_h(hash)
      hash = hash.transform_keys(&:to_sym)
      new(type: hash[:type], id: hash[:id], source: hash[:source], metadata: hash[:metadata] || {})
    end
  end
end
