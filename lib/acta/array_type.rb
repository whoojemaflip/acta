# frozen_string_literal: true

require "active_model/type"

module Acta
  class ArrayType < ActiveModel::Type::Value
    def initialize(element_type)
      super()
      @element_type = element_type
    end

    def cast(value)
      return nil if value.nil?

      Array(value).map { |el| @element_type.cast(el) }
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
