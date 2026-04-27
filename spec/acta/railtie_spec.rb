# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "pathname"
require "active_support/ordered_options"
require "acta/railtie"

RSpec.describe Acta::Railtie do
  let(:tmp_root) { Pathname.new(Dir.mktmpdir("acta-railtie")) }

  let(:app) do
    root = tmp_root
    acta_cfg = ActiveSupport::OrderedOptions.new
    cfg = Object.new
    cfg.define_singleton_method(:acta) { acta_cfg }
    fake = Object.new
    fake.define_singleton_method(:root)   { root }
    fake.define_singleton_method(:config) { cfg }
    fake
  end

  before do
    Acta.reset_handlers!
  end

  after do
    Acta.reset_handlers!
    FileUtils.remove_entry(tmp_root) if tmp_root.exist?
  end

  def write_subscriber_file(relative, body)
    full = tmp_root.join(relative)
    FileUtils.mkdir_p(full.dirname)
    full.write(body)
    full
  end

  it "loads projection files under app/projections so they self-register" do
    write_subscriber_file("app/projections/example_projection.rb", <<~RUBY)
      class ExampleProjection < Acta::Projection
      end
    RUBY

    app.config.acta.projection_paths = [ "app/projections" ]
    app.config.acta.handler_paths    = []
    app.config.acta.reactor_paths    = []

    expect {
      described_class.eager_load_subscribers!(app)
    }.to change { Acta.projection_classes.map(&:name) }.from([]).to(include("ExampleProjection"))
  end

  it "loads handler files under app/handlers" do
    write_subscriber_file("app/handlers/example_handler.rb", <<~RUBY)
      class ExampleHandlerWasLoaded
      end
    RUBY

    app.config.acta.projection_paths = []
    app.config.acta.handler_paths    = [ "app/handlers" ]
    app.config.acta.reactor_paths    = []

    described_class.eager_load_subscribers!(app)

    expect(Object.const_defined?(:ExampleHandlerWasLoaded)).to be(true)
  ensure
    Object.send(:remove_const, :ExampleHandlerWasLoaded) if defined?(ExampleHandlerWasLoaded)
  end

  it "skips configured paths that don't exist on disk" do
    app.config.acta.projection_paths = [ "app/projections" ]
    app.config.acta.handler_paths    = []
    app.config.acta.reactor_paths    = []

    expect { described_class.eager_load_subscribers!(app) }.not_to raise_error
  end

  it "is idempotent — loading twice doesn't double-register a projection" do
    write_subscriber_file("app/projections/idempotent_projection.rb", <<~RUBY)
      class IdempotentProjection < Acta::Projection
      end
    RUBY

    app.config.acta.projection_paths = [ "app/projections" ]
    app.config.acta.handler_paths    = []
    app.config.acta.reactor_paths    = []

    described_class.eager_load_subscribers!(app)
    described_class.eager_load_subscribers!(app)

    expect(Acta.projection_classes.count { |k| k.name == "IdempotentProjection" }).to eq(1)
  end

  it "treats nil path lists as the configured defaults so apps don't have to set them" do
    write_subscriber_file("app/projections/default_path_projection.rb", <<~RUBY)
      class DefaultPathProjection < Acta::Projection
      end
    RUBY

    app.config.acta.projection_paths = described_class::DEFAULT_PROJECTION_PATHS.dup
    app.config.acta.handler_paths    = described_class::DEFAULT_HANDLER_PATHS.dup
    app.config.acta.reactor_paths    = described_class::DEFAULT_REACTOR_PATHS.dup

    described_class.eager_load_subscribers!(app)

    expect(Acta.projection_classes.map(&:name)).to include("DefaultPathProjection")
  end

  describe "subscriber_paths" do
    it "returns absolute paths only for directories that exist" do
      FileUtils.mkdir_p(tmp_root.join("app/projections"))

      app.config.acta.projection_paths = [ "app/projections" ]
      app.config.acta.handler_paths    = [ "app/handlers" ] # not created
      app.config.acta.reactor_paths    = []

      expect(described_class.subscriber_paths(app)).to eq([ tmp_root.join("app/projections").to_s ])
    end

    it "deduplicates overlapping path lists" do
      FileUtils.mkdir_p(tmp_root.join("app/subscribers"))

      app.config.acta.projection_paths = [ "app/subscribers" ]
      app.config.acta.handler_paths    = [ "app/subscribers" ]
      app.config.acta.reactor_paths    = [ "app/subscribers" ]

      expect(described_class.subscriber_paths(app)).to eq([ tmp_root.join("app/subscribers").to_s ])
    end
  end
end
