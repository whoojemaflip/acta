# frozen_string_literal: true

require "active_model"
require "active_model/attributes"
require_relative "types/model"
require_relative "types/array"

module Acta
  class Model
    include ActiveModel::Model
    include ActiveModel::Attributes

    # Accept:
    # - a class as a type (Acta::Model / Acta::Serializable) — wrapped in Acta::Types::Model
    # - array_of: Class or array_of: :symbol — wrapped in Acta::Types::Array
    # - standard symbol types (:string, :integer, ...) — forwarded to AM
    def self.attribute(name, type = nil, array_of: nil, **options)
      if array_of
        element = element_type_for(array_of)
        type = Acta::Types::Array.new(element)
      elsif type.is_a?(Class)
        type = Acta::Types::Model.new(type)
      end

      if type.nil?
        super(name, **options)
      else
        super(name, type, **options)
      end
    end

    def self.element_type_for(target)
      case target
      when Class then Acta::Types::Model.new(target)
      when Symbol then ActiveModel::Type.lookup(target)
      else target
      end
    end
    private_class_method :element_type_for

    def to_acta_hash
      self.class.attribute_types.each_with_object({}) do |(name, type), hash|
        hash[name] = type.serialize(public_send(name))
      end
    end

    def self.from_acta_hash(hash)
      types = attribute_types
      filtered = hash.each_with_object({}) do |(k, v), acc|
        key = k.to_s
        next unless types.key?(key)

        acc[key.to_sym] = types[key].deserialize(v)
      end
      new(**filtered)
    end
  end
end
