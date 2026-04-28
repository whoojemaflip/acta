# frozen_string_literal: true

require "active_job"

module Acta
  module Testing
    DEFAULT_ACTOR_ATTRIBUTES = { type: "system", id: "rspec", source: "test" }.freeze

    # Wraps writes to `acta_managed!` AR models so the projection-write guard
    # accepts them. Useful for fixtures, factories, and ad-hoc setup that
    # needs to bypass the command + event + projection chain.
    #
    #   # spec/rails_helper.rb
    #   require "acta/testing"
    #   RSpec.configure do |config|
    #     Acta::Testing.projection_writes_helper!(config)
    #   end
    #
    #   # in any spec:
    #   with_projection_writes do
    #     Trail.create!(name: "Crank It Up", zone: zone)
    #   end
    module ProjectionWritesHelpers
      def with_projection_writes(&block)
        Acta::Projection.applying!(&block)
      end
    end

    module_function

    # Runs the given block with ActiveJob's :inline adapter, so async
    # reactors run synchronously in the caller's thread. Restores the
    # original adapter when the block returns (or raises).
    def test_mode
      original = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :inline
      yield
    ensure
      ActiveJob::Base.queue_adapter = original
    end

    # Configures RSpec to set Acta::Current.actor before every example, so
    # specs that emit (directly or via a command) don't trip Acta::MissingActor.
    # Resets Acta::Current after each example so state doesn't leak.
    #
    #   # spec/rails_helper.rb
    #   require "acta/testing"
    #   RSpec.configure do |config|
    #     Acta::Testing.default_actor!(config)
    #   end
    #
    # Override the default actor's attributes per project:
    #
    #   Acta::Testing.default_actor!(config, type: "user", id: "test-user-1", source: "spec")
    #
    # Individual specs can still override Acta::Current.actor inline (or
    # use Acta::Testing::DSL#with_actor for a scoped override).
    def default_actor!(config, **attributes)
      attrs = DEFAULT_ACTOR_ATTRIBUTES.merge(attributes)

      config.before(:each) do
        Acta::Current.actor = Acta::Actor.new(**attrs)
      end

      config.after(:each) do
        Acta::Current.reset
      end
    end

    # Includes `with_projection_writes` into every RSpec example. The helper
    # forwards to `Acta::Projection.applying!`, so blocks under it pass the
    # `acta_managed!` write guard. See ProjectionWritesHelpers.
    #
    #   # spec/rails_helper.rb
    #   require "acta/testing"
    #   RSpec.configure do |config|
    #     Acta::Testing.projection_writes_helper!(config)
    #   end
    def projection_writes_helper!(config)
      config.include(ProjectionWritesHelpers)
    end
  end
end
