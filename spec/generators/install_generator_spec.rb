# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/acta/install/install_generator"
require "fileutils"

RSpec.describe Acta::Generators::InstallGenerator do
  let(:destination) { File.expand_path("../../tmp/generator_test", __dir__) }

  before do
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(destination)
  end

  after { FileUtils.rm_rf(destination) }

  it "creates a migration file" do
    described_class.start([], destination_root: destination)

    migration = Dir["#{destination}/db/migrate/*_create_acta_events.rb"].first

    expect(migration).to be_present
    content = File.read(migration)
    expect(content).to include("class CreateActaEvents")
    expect(content).to include("Acta::Schema.install(connection)")
  end

  describe "--database flag" do
    let(:rails_app_double) { double("Rails::Application") }
    let(:rails_paths) { { "db/migrate" => double(to_ary: [ "db/migrate" ]) } }
    let(:db_config) { double("DatabaseConfig", migrations_paths: [ "db/catalog_migrate" ]) }

    before do
      stub_const("Rails", Module.new) unless defined?(Rails)
      allow(Rails).to receive(:application).and_return(rails_app_double)
      allow(Rails).to receive(:env).and_return("test")
      allow(rails_app_double).to receive(:config).and_return(double(paths: rails_paths))
      allow(ActiveRecord::Base.configurations).to receive(:configs_for)
        .with(env_name: "test", name: "catalog")
        .and_return(db_config)
    end

    it "writes to the database's migrations_paths" do
      described_class.start([ "--database=catalog" ], destination_root: destination)

      catalog_migration = Dir["#{destination}/db/catalog_migrate/*_create_acta_events.rb"].first
      default_migration = Dir["#{destination}/db/migrate/*_create_acta_events.rb"].first

      expect(catalog_migration).to be_present
      expect(default_migration).to be_nil
    end

    it "accepts the --db short alias" do
      described_class.start([ "--db=catalog" ], destination_root: destination)

      catalog_migration = Dir["#{destination}/db/catalog_migrate/*_create_acta_events.rb"].first
      expect(catalog_migration).to be_present
    end
  end
end
