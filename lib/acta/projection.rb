# frozen_string_literal: true

module Acta
  class Projection < Handler
    def self.inherited(subclass)
      super
      Acta.register_projection(subclass)
    end

    def self.truncate!
      # default no-op; apps override to clear their projected state
    end
  end
end
