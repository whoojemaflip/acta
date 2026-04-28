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

      # Declares the ActiveJob queue name to enqueue this reactor's job on.
      # Read by Acta's dispatcher when the reactor is async (the default);
      # ignored for `sync!` reactors. With no per-class declaration, the
      # global `Acta.reactor_queue` setting applies; if that's also unset,
      # ActiveJob's `:default` queue is used.
      #
      #   class WelcomeEmailReactor < Acta::Reactor
      #     queue_as :fast
      #     on UserSignedUp do |event|
      #       UserMailer.welcome(event.user_id).deliver_later
      #     end
      #   end
      def queue_as(name)
        @queue_name = name
      end

      def queue_name
        return @queue_name if defined?(@queue_name)

        Acta.reactor_queue
      end
    end
  end
end
