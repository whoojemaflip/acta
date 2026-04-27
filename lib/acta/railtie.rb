# frozen_string_literal: true

require "rails/railtie"

module Acta
  # Forces projection / handler / reactor classes to load at boot, so they can
  # register themselves with Acta before the first event is emitted.
  #
  # Without this, Zeitwerk lazy-loads them on first reference. A projection that
  # nothing has touched yet is silently unsubscribed — emits succeed, the event
  # row is written, but the projection never runs and the read model goes stale.
  # No error, no warning. See https://github.com/whoojemaflip/acta/issues/7.
  #
  # Configurable via `config.acta.{projection,handler,reactor}_paths` if your app
  # puts subscribers somewhere other than the conventional `app/projections`,
  # `app/handlers`, `app/reactors`. Set a path list to `[]` to opt out.
  class Railtie < ::Rails::Railtie
    DEFAULT_PROJECTION_PATHS = %w[app/projections].freeze
    DEFAULT_HANDLER_PATHS    = %w[app/handlers].freeze
    DEFAULT_REACTOR_PATHS    = %w[app/reactors].freeze

    config.acta = ActiveSupport::OrderedOptions.new

    initializer "acta.subscriber_path_defaults" do |app|
      cfg = app.config.acta
      cfg.projection_paths = DEFAULT_PROJECTION_PATHS.dup if cfg.projection_paths.nil?
      cfg.handler_paths    = DEFAULT_HANDLER_PATHS.dup    if cfg.handler_paths.nil?
      cfg.reactor_paths    = DEFAULT_REACTOR_PATHS.dup    if cfg.reactor_paths.nil?
    end

    initializer "acta.eager_load_subscribers" do |app|
      app.config.to_prepare do
        Acta::Railtie.eager_load_subscribers!(app)
      end
    end

    def self.eager_load_subscribers!(app)
      subscriber_paths(app).each { |path| eager_load_path(path) }
    end

    def self.subscriber_paths(app)
      cfg = app.config.acta
      relative = [ *cfg.projection_paths, *cfg.handler_paths, *cfg.reactor_paths ].compact.uniq
      relative.map { |path| app.root.join(path).to_s }.select { |path| Dir.exist?(path) }
    end

    def self.eager_load_path(path)
      if rails_zeitwerk_loader_for(path)&.respond_to?(:eager_load_dir)
        rails_zeitwerk_loader_for(path).eager_load_dir(path)
      else
        Dir.glob(File.join(path, "**/*.rb")).sort.each { |file| require file }
      end
    end

    def self.rails_zeitwerk_loader_for(path)
      return nil unless defined?(::Rails) && ::Rails.respond_to?(:autoloaders)

      autoloaders = ::Rails.autoloaders
      [ autoloaders.main, autoloaders.once ].compact.find do |loader|
        loader.respond_to?(:dirs) && loader.dirs.any? { |dir| path == dir || path.start_with?("#{dir}/") }
      end
    end
    private_class_method :rails_zeitwerk_loader_for
  end
end
