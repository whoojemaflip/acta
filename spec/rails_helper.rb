# frozen_string_literal: true

require "spec_helper"
require "active_record"
require "active_job"
require "acta/schema"
require "acta/record"

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

Acta::Schema.install(ActiveRecord::Base.connection)

ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(IO::NULL)

RSpec.configure do |config|
  config.around(:each, :active_record) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
