# frozen_string_literal: true

module Acta
  class Reactor < Handler
    class << self
      def sync!
        @sync = true
      end

      def sync?
        @sync == true
      end
    end
  end
end
