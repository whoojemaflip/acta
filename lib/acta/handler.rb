# frozen_string_literal: true

module Acta
  class Handler
    def self.on(event_class, &block)
      Acta.subscribe(event_class, self, &block)
    end
  end
end
