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
end
