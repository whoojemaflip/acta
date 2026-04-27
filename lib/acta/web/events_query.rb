# frozen_string_literal: true

module Acta
  module Web
    # Builds the filtered Acta::Record scope that drives the event log
    # admin UI. Extracted from EventsController so it can be unit-tested
    # without a Rails-app fixture, and reused if other admin surfaces want
    # the same filter semantics.
    #
    # All filter values are user-supplied. String LIKE values are passed
    # through ActiveRecord::Base.sanitize_sql_like to neutralise %/_
    # wildcards in user input.
    class EventsQuery
      # Names of params accepted; used by callers to build current-filter
      # views and by tests to check the param surface.
      FILTER_KEYS = %i[event_type stream_type actor_id stream_key q].freeze

      def initialize(params = {})
        @event_type  = presence(params[:event_type])
        @stream_type = presence(params[:stream_type])
        @actor_id    = presence(params[:actor_id])
        @stream_key  = presence(params[:stream_key])
        @q           = presence(params[:q])
      end

      # Returns an unloaded ActiveRecord::Relation over Acta::Record with
      # the configured filters applied. Caller is responsible for ordering,
      # offset, limit, and any further scope chaining.
      def scope
        scope = Acta::Record.all
        scope = scope.where(event_type: @event_type)   if @event_type
        scope = scope.where(stream_type: @stream_type) if @stream_type
        scope = scope.where(actor_id: @actor_id)       if @actor_id
        scope = apply_stream_key(scope)                if @stream_key
        scope = apply_q(scope)                         if @q
        scope
      end

      # Returns only the filters that are actually present, with symbol keys.
      # Useful to build filter-chip UIs.
      def active_filters
        {
          event_type: @event_type,
          stream_type: @stream_type,
          actor_id: @actor_id,
          stream_key: @stream_key,
          q: @q,
        }.compact
      end

      private

      def presence(value)
        return nil if value.nil?

        s = value.to_s
        s.empty? ? nil : s
      end

      # ActiveRecord::Base.sanitize_sql_like escapes %, _, and \ by prefixing
      # with \. The LIKE clause must declare ESCAPE '\\' for those escapes to
      # take effect — otherwise the sanitized backslash is treated as a
      # literal character and user-supplied wildcards continue to match.
      LIKE_ESCAPE = "\\".freeze

      def apply_stream_key(scope)
        sanitized = ActiveRecord::Base.sanitize_sql_like(@stream_key)
        scope.where("stream_key LIKE ? ESCAPE ?", "%#{sanitized}%", LIKE_ESCAPE)
      end

      def apply_q(scope)
        sanitized = ActiveRecord::Base.sanitize_sql_like(@q)
        like = "%#{sanitized}%"
        scope.where(
          "(event_type LIKE :q ESCAPE :e OR stream_type LIKE :q ESCAPE :e OR stream_key LIKE :q ESCAPE :e OR actor_id LIKE :q ESCAPE :e OR source LIKE :q ESCAPE :e)",
          q: like, e: LIKE_ESCAPE,
        )
      end
    end
  end
end
