# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"
require "rails/generators/active_record"

module Acta
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(path)
        ActiveRecord::Generators::Base.next_migration_number(path)
      end

      def create_migration_file
        migration_template "create_acta_events.rb.tt", "db/migrate/create_acta_events.rb"
      end
    end
  end
end
