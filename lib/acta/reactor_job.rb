# frozen_string_literal: true

require "active_job"

module Acta
  class ReactorJob < ActiveJob::Base
    def perform(event_uuid:, reactor_class:, event_class:)
      event = Acta.events.find_by_uuid(event_uuid)
      return unless event

      reactor = Object.const_get(reactor_class)
      ev_class = Object.const_get(event_class)

      Acta.handlers[ev_class]
        .select { |r| r[:handler_class] == reactor && r[:kind] == :reactor }
        .each { |r| r[:block].call(event) }
    end
  end
end
