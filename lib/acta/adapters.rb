# frozen_string_literal: true

require_relative "adapters/base"
require_relative "adapters/sqlite"
require_relative "adapters/postgres"

module Acta
  module Adapters
    def self.for(connection)
      name = connection.adapter_name.downcase
      case name
      when /sqlite/ then SQLite.new
      when /postgres/, /postgis/ then Postgres.new
      else
        raise AdapterError, "No Acta adapter for #{name.inspect}"
      end
    end
  end
end
