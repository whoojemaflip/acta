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
  # Hosts that need the events table to *share a connection pool* with
  # their own tenant-scoped abstract base (so writes inside a single
  # transaction don't fight across pools on the same SQLite file)
  # re-parent EventsRecord via `Acta.set_events_record_parent!`:
  #
  #     # config/initializers/_acta_record_parent.rb
  #     class TenantRecord < ActiveRecord::Base
  #       self.abstract_class = true
  #     end
  #     Acta.set_events_record_parent!(TenantRecord)
  #     # then call connects_to on TenantRecord — Acta::Record rides along
  #
  # Acta::Record inherits from EventsRecord so any routing applied to
  # EventsRecord (or to a re-parented ancestor) automatically applies.
  class EventsRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  class Record < EventsRecord
    self.table_name = "events"
    self.inheritance_column = nil
  end

  # Re-parent EventsRecord (and therefore Record) onto a host-supplied
  # abstract class. Must run BEFORE any query against Acta::Record
  # executes — call from a host initializer after the parent class is
  # defined. Re-defines the two constants so existing references to
  # `Acta::Record` resolve to the new class.
  #
  # Use case: per-tenant SQLite sharding where the host wants events
  # and its own tenant-scoped rows in the same connection pool to
  # avoid SQLite write contention on cross-pool transactions.
  def self.set_events_record_parent!(parent)
    raise ArgumentError, "parent must be an abstract ActiveRecord class" unless parent.is_a?(Class) && parent < ::ActiveRecord::Base && parent.abstract_class?

    Acta.send(:remove_const, :Record)        if Acta.const_defined?(:Record, false)
    Acta.send(:remove_const, :EventsRecord)  if Acta.const_defined?(:EventsRecord, false)

    Acta.const_set(:EventsRecord, Class.new(parent) { self.abstract_class = true })
    Acta.const_set(:Record, Class.new(Acta::EventsRecord) do
      self.table_name = "events"
      self.inheritance_column = nil
    end)
  end
end
