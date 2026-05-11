# frozen_string_literal: true

require "active_record"

module Acta
  # Abstract intermediate. The actual events table lives on `Acta::Record`
  # below; this class exists so hosts can call `connects_to` (which
  # ActiveRecord rejects on concrete classes that have `table_name` set).
  #
  # Default behaviour: inherits from ActiveRecord::Base, no shard or
  # connection routing — Acta::Record uses whatever the host's default
  # connection is.
  #
  # Hosts that want the events table on a specific connection or
  # shard reopen this class in an initializer:
  #
  #     Acta::EventsRecord.connects_to(database: { writing: :events })
  #     # or
  #     Acta::EventsRecord.connects_to(shards: { tenant_a: { writing: :tenant_a } })
  #
  # Acta::Record inherits from EventsRecord so the routing
  # automatically applies.
  class EventsRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  class Record < EventsRecord
    self.table_name = "events"
    self.inheritance_column = nil
  end
end
