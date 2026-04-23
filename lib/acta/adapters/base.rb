# frozen_string_literal: true

module Acta
  module Adapters
    class Base
      def install_schema(connection, table_name: :events)
        uuid_type = uuid_column_type
        json_type = json_column_type

        connection.create_table(table_name) do |t|
          t.send(uuid_type, :uuid, null: false)
          t.string  :event_type, null: false
          t.integer :event_version, null: false, default: 1

          t.string  :stream_type
          t.string  :stream_key
          t.integer :stream_sequence

          t.send(json_type, :payload, null: false)

          t.string :actor_type
          t.string :actor_id
          t.string :source
          t.send(json_type, :metadata)

          t.datetime :occurred_at, null: false
          t.datetime :recorded_at, null: false
        end

        connection.add_index table_name, :uuid, unique: true
        connection.add_index table_name,
                             [ :stream_type, :stream_key, :stream_sequence ],
                             unique: true,
                             where: "stream_type IS NOT NULL",
                             name: "index_events_on_stream_identity"
        connection.add_index table_name, :event_type
        connection.add_index table_name, [ :actor_type, :actor_id ]
        connection.add_index table_name, :source
        connection.add_index table_name, :occurred_at
      end

      def uuid_column_type
        :string
      end

      def json_column_type
        :json
      end

      def insert_event(_attributes)
        raise NotImplementedError, "#{self.class}#insert_event"
      end

      def fetch_records
        raise NotImplementedError, "#{self.class}#fetch_records"
      end
    end
  end
end
