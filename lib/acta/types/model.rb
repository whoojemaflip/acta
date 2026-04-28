# frozen_string_literal: true

require "active_model/type"

module Acta
  module Types
    # Wraps an Acta::Model subclass (or any class with `to_acta_hash` /
    # `from_acta_hash`, e.g. AR classes that include Acta::Serializable)
    # so it can be used as an `attribute` type on another Acta::Model.
    # The wrapping is automatic — `attribute :location, GeoPoint` invokes
    # this internally; consumers don't construct it directly.
    class Model < ActiveModel::Type::Value
      def initialize(wrapped_class)
        super()
        @wrapped_class = wrapped_class
      end

      def cast(value)
        case value
        when nil then nil
        when @wrapped_class then value
        when Hash then @wrapped_class.from_acta_hash(value)
        else
          raise ArgumentError, "Cannot cast #{value.class} (#{value.inspect}) to #{@wrapped_class}"
        end
      end

      def serialize(value)
        return nil if value.nil?

        value.to_acta_hash
      end

      def deserialize(value)
        cast(value)
      end
    end
  end
end
