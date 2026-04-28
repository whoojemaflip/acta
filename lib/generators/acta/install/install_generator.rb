# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"
require "rails/generators/active_record/migration"

module Acta
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :database, type: :string, aliases: %i[--db],
                   desc: "The database for the events migration. By default, the current environment's primary database is used."

      def create_migration_file
        migration_template "create_acta_events.rb.tt",
                           File.join(db_migrate_path, "create_acta_events.rb")
      end
    end
  end
end
