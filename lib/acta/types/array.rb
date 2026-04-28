# frozen_string_literal: true

require "active_model/type"

module Acta
  module Types
    # Wraps any other Acta type as a list-of-element type. Used internally
    # by `attribute :foo, array_of: Class` (or `array_of: :symbol`); not
    # constructed directly by consumers.
    class Array < ActiveModel::Type::Value
      def initialize(element_type)
        super()
        @element_type = element_type
      end

      def cast(value)
        return nil if value.nil?

        Kernel.Array(value).map { |el| @element_type.cast(el) }
      end

      def serialize(value)
        return nil if value.nil?

        value.map { |el| @element_type.serialize(el) }
      end

      def deserialize(value)
        return nil if value.nil?

        value.map { |el| @element_type.deserialize(el) }
      end
    end
  end
end
