# frozen_string_literal: true

require "active_job"

module Acta
  module Testing
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
  end
end
