# frozen_string_literal: true

require "active_support/concern"

module Acta
  module Serializable
    extend ActiveSupport::Concern

    class_methods do
      def acta_serialize(except: nil, only: nil)
        raise ArgumentError, "acta_serialize: pass only one of except: or only:" if except && only

        @acta_serialize_options = {
          except: except&.map(&:to_s),
          only: only&.map(&:to_s)
        }
      end

      def acta_serialize_options
        @acta_serialize_options ||= { except: nil, only: nil }
      end

      def from_acta_hash(hash)
        return nil if hash.nil?

        known = column_names
        filtered = hash.each_with_object({}) do |(key, value), acc|
          name = key.to_s
          acc[name.to_sym] = value if known.include?(name)
        end
        new(**filtered)
      end
    end

    def to_acta_hash
      opts = self.class.acta_serialize_options
      hash = attributes

      if opts[:only]
        hash.slice(*opts[:only])
      elsif opts[:except]
        hash.except(*opts[:except])
      else
        hash
      end
    end
  end
end
