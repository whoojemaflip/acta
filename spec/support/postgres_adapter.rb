# frozen_string_literal: true

module PostgresAdapterSupport
  PG_CONFIG = {
    adapter: "postgresql",
    database: ENV.fetch("ACTA_PG_DATABASE", "acta_test"),
    host: ENV.fetch("ACTA_PG_HOST", "localhost"),
    port: ENV.fetch("ACTA_PG_PORT", "5432").to_i,
    username: ENV.fetch("ACTA_PG_USER", ENV["USER"]),
    password: ENV.fetch("ACTA_PG_PASSWORD", nil),
    pool: 25
  }.compact.freeze

  def self.available?
    require "pg"
    ActiveRecord::Base.establish_connection(PG_CONFIG)
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue StandardError
    false
  ensure
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:"
    )
  end

  def self.with_connection(&block)
    ActiveRecord::Base.remove_connection
    ActiveRecord::Base.establish_connection(PG_CONFIG)
    ActiveRecord::Base.connection.execute("SELECT 1")
    Acta::Record.reset_column_information
    ActiveRecord::Base.connection.drop_table(:events) if ActiveRecord::Base.connection.table_exists?(:events)
    Acta::Schema.install(ActiveRecord::Base.connection)
    Acta::Record.reset_column_information
    Acta.reset_adapter!
    block.call
  ensure
    ActiveRecord::Base.connection.drop_table(:events) if ActiveRecord::Base.connection.table_exists?(:events)
    ActiveRecord::Base.remove_connection
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:"
    )
    Acta::Record.reset_column_information
    Acta::Schema.install(ActiveRecord::Base.connection) unless ActiveRecord::Base.connection.table_exists?(:events)
    Acta::Record.reset_column_information
    Acta.reset_adapter!
  end
end
