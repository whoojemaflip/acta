# frozen_string_literal: true

module Acta
  module Schema
    TABLE_NAME = :events

    def self.install(connection, table_name: TABLE_NAME)
      adapter = Acta::Adapters.for(connection)
      adapter.install_schema(connection, table_name:)
    end
  end
end
