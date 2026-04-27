# frozen_string_literal: true

require "active_support/concern"

module Acta
  # Marks an ActiveRecord model as projection-managed: its rows are
  # maintained by an Acta::Projection from the event log, so writes from
  # anywhere else (controllers, console, rake tasks, callbacks on other
  # models) bypass the log and break Acta.rebuild!'s determinism.
  #
  # Opt in with `acta_managed!` on the AR class:
  #
  #   class Trail < ApplicationRecord
  #     acta_managed!   # raise on out-of-band writes
  #   end
  #
  #   class TrailAlias < ApplicationRecord
  #     acta_managed! on_violation: :warn   # warn instead, for incremental migration
  #   end
  #
  # Inside an `Acta::Projection` `on EventClass do |e| ... end` block (or
  # during `Acta.rebuild!`'s truncate phase), `Acta::Projection.applying?`
  # is true and writes are allowed. Outside, they raise
  # `Acta::ProjectionWriteError` (or warn if so configured).
  #
  # Tests, migrations, and one-off backfills can wrap intentional
  # out-of-band writes in `Acta::Projection.applying! { ... }` to bypass
  # the safety net explicitly.
  module ProjectionManaged
    extend ActiveSupport::Concern

    GUARDED_CLASS_METHODS = %i[
      update_all
      delete_all
      insert
      insert!
      insert_all
      insert_all!
      upsert
      upsert_all
    ].freeze

    GUARDED_INSTANCE_METHODS = %i[
      update_columns
      update_column
    ].freeze

    VALID_VIOLATION_ACTIONS = %i[ raise warn ].freeze

    class_methods do
      def acta_managed!(on_violation: :raise)
        unless VALID_VIOLATION_ACTIONS.include?(on_violation)
          raise ArgumentError,
                "acta_managed! on_violation must be one of #{VALID_VIOLATION_ACTIONS.inspect}, got #{on_violation.inspect}"
        end

        @acta_on_violation = on_violation

        before_save     :_acta_assert_projection_applying!
        before_destroy  :_acta_assert_projection_applying!

        singleton_class.prepend(ClassWriteGuards)
      end

      def acta_managed?
        !@acta_on_violation.nil?
      end

      def acta_on_violation
        @acta_on_violation
      end
    end

    module ClassWriteGuards
      ProjectionManaged::GUARDED_CLASS_METHODS.each do |method|
        define_method(method) do |*args, **kwargs, &block|
          ProjectionManaged.assert_projection_applying!(self, method)
          super(*args, **kwargs, &block)
        end
      end
    end

    GUARDED_INSTANCE_METHODS.each do |method|
      define_method(method) do |*args, **kwargs, &block|
        ProjectionManaged.assert_projection_applying!(self.class, method)
        super(*args, **kwargs, &block)
      end
    end

    def self.assert_projection_applying!(model_class, write_method)
      return if Acta::Projection.applying?

      action = model_class.acta_on_violation
      case action
      when :raise
        raise Acta::ProjectionWriteError.new(model_class:, write_method:)
      when :warn
        warn "[acta] #{Acta::ProjectionWriteError.new(model_class:, write_method:).message}"
      end
    end

    private

    def _acta_assert_projection_applying!
      ProjectionManaged.assert_projection_applying!(self.class, :save)
    end
  end
end
