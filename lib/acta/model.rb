# frozen_string_literal: true

require "active_model"
require "active_model/attributes"
require_relative "model_type"
require_relative "array_type"

module Acta
  class Model
    include ActiveModel::Model
    include ActiveModel::Attributes

    # Accept:
    # - a class as a type (Acta::Model / Acta::Serializable) — wrapped in ModelType
    # - array_of: Class or array_of: :symbol — wrapped in ArrayType
    # - standard symbol types (:string, :integer, ...) — forwarded to AM
    def self.attribute(name, type = nil, array_of: nil, **options)
      if array_of
        element = element_type_for(array_of)
        type = Acta::ArrayType.new(element)
      elsif type.is_a?(Class)
        type = Acta::ModelType.new(type)
      end

      if type.nil?
        super(name, **options)
      else
        super(name, type, **options)
      end
    end

    def self.element_type_for(target)
      case target
      when Class then Acta::ModelType.new(target)
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
      known_keys = attribute_types.keys
      filtered = hash.each_with_object({}) do |(k, v), acc|
        key = k.to_s
        acc[key.to_sym] = v if known_keys.include?(key)
      end
      new(**filtered)
    end
  end
end
