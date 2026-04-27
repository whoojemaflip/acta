# frozen_string_literal: true

module Acta
  module Adapters
    class Postgres < Base
      def uuid_column_type
        :uuid
      end

      def json_column_type
        :jsonb
      end

      def insert_event(attributes)
        stream_type = attributes[:stream_type]
        stream_key = attributes[:stream_key]

        if stream_type && stream_key
          insert_streamed(attributes, stream_type:, stream_key:)
        else
          Acta::Record.create!(**attributes)
        end
      end

      def fetch_records
        Acta::Record.order(:id)
      end

      private

      def insert_streamed(attributes, stream_type:, stream_key:)
        Acta::Record.transaction(requires_new: true) do
          acquire_stream_lock(stream_type, stream_key)
          sequence = compute_next_sequence(stream_type, stream_key)
          Acta::Record.create!(**attributes, stream_sequence: sequence)
        end
      rescue ActiveRecord::RecordNotUnique => e
        raise unless stream_conflict?(e)

        actual = current_stream_max(stream_type, stream_key) || 0
        raise Acta::VersionConflict.new(
          stream_type:,
          stream_key:,
          expected_version: actual + 1,
          actual_version: actual
        )
      end

      def acquire_stream_lock(stream_type, stream_key)
        key = "#{stream_type}:#{stream_key}"
        Acta::Record.connection.execute(
          "SELECT pg_advisory_xact_lock(hashtext(#{ActiveRecord::Base.connection.quote(key)}))"
        )
      end

      def compute_next_sequence(stream_type, stream_key)
        (current_stream_max(stream_type, stream_key) || 0) + 1
      end

      def current_stream_max(stream_type, stream_key)
        Acta::Record
          .where(stream_type:, stream_key:)
          .maximum(:stream_sequence)
      end

      def stream_conflict?(error)
        message = error.message
        message.include?("stream_sequence") ||
          message.include?("index_events_on_stream_identity")
      end
    end
  end
end
