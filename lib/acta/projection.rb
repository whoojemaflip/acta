# frozen_string_literal: true

module Acta
  class Projection < Handler
    APPLYING_FLAG = :acta_projection_applying

    def self.inherited(subclass)
      super
      Acta.register_projection(subclass)
    end

    def self.truncate!
      # default no-op; apps override to clear their projected state
    end

    # Mark the current thread as inside projection-side code for the
    # duration of the block. Acta sets this internally when invoking
    # projection handlers and during `Acta.rebuild!`'s truncate phase, so
    # `acta_managed!` AR models know to allow the writes.
    #
    # Apps can wrap fixture setup, migrations, or one-off backfill
    # operations in `Acta::Projection.applying! { ... }` to bypass the
    # safety net intentionally.
    def self.applying!
      previous = Thread.current[APPLYING_FLAG]
      Thread.current[APPLYING_FLAG] = true
      yield
    ensure
      Thread.current[APPLYING_FLAG] = previous
    end

    def self.applying?
      Thread.current[APPLYING_FLAG] == true
    end
  end
end
