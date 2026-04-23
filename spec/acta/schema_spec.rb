# frozen_string_literal: true

require "rails_helper"

RSpec.describe Acta::Schema do
  describe "installed events table" do
    let(:connection) { ActiveRecord::Base.connection }

    it "has the expected columns" do
      columns = connection.columns(:events).map(&:name)

      expect(columns).to include(
        "id",
        "uuid",
        "event_type",
        "event_version",
        "stream_type",
        "stream_key",
        "stream_sequence",
        "payload",
        "actor_type",
        "actor_id",
        "source",
        "metadata",
        "occurred_at",
        "recorded_at"
      )
    end

    it "enforces uuid uniqueness" do
      indexes = connection.indexes(:events)
      uuid_index = indexes.find { |i| i.columns == [ "uuid" ] }

      expect(uuid_index).to be_present
      expect(uuid_index.unique).to be(true)
    end

    it "enforces per-stream sequence uniqueness with a partial index" do
      indexes = connection.indexes(:events)
      stream_index = indexes.find { |i| i.name == "index_events_on_stream_identity" }

      expect(stream_index).to be_present
      expect(stream_index.unique).to be(true)
      expect(stream_index.where).to include("stream_type")
    end

    it "indexes event_type, actor, source, and occurred_at" do
      indexes = connection.indexes(:events).map(&:columns)

      expect(indexes).to include([ "event_type" ])
      expect(indexes).to include([ "actor_type", "actor_id" ])
      expect(indexes).to include([ "source" ])
      expect(indexes).to include([ "occurred_at" ])
    end

    it "requires non-null uuid, event_type, event_version, payload, occurred_at, recorded_at" do
      columns_by_name = connection.columns(:events).index_by(&:name)

      %w[ uuid event_type event_version payload occurred_at recorded_at ].each do |name|
        expect(columns_by_name[name].null).to be(false), "expected #{name} to be NOT NULL"
      end
    end
  end
end
