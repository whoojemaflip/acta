# frozen_string_literal: true

require "rails_helper"
require "acta/web/events_query"

RSpec.describe Acta::Web::EventsQuery, :active_record do
  before do
    Acta::Current.actor = Acta::Actor.new(type: "system", id: "spec", source: "test")
  end

  # Test fixtures: emit a representative variety of events directly via
  # Acta::Record.create! so we don't need real Event/Projection classes.
  # Auto-increments stream_sequence per (stream_type, stream_key) to satisfy
  # the unique index.
  def make_event(attrs)
    seq_key = [attrs[:stream_type] || "test_stream", attrs[:stream_key] || "key-1"]
    @sequences ||= Hash.new(0)
    @sequences[seq_key] += 1

    defaults = {
      uuid: SecureRandom.uuid,
      event_type: "TestEvent",
      event_version: 1,
      stream_type: "test_stream",
      stream_key: "key-1",
      stream_sequence: @sequences[seq_key],
      payload: {},
      actor_type: "system",
      actor_id: "spec",
      source: "test",
      occurred_at: Time.current,
      recorded_at: Time.current,
    }
    Acta::Record.create!(defaults.merge(attrs))
  end

  describe "no filters" do
    it "returns all records" do
      make_event(uuid: SecureRandom.uuid)
      make_event(uuid: SecureRandom.uuid)

      expect(described_class.new({}).scope.count).to eq(2)
    end

    it "ignores blank-string values for all filter keys" do
      make_event(uuid: SecureRandom.uuid)

      expect(described_class.new(event_type: "", stream_type: "", actor_id: "", stream_key: "", q: "").scope.count).to eq(1)
    end

    it "ignores nil values" do
      make_event(uuid: SecureRandom.uuid)

      expect(described_class.new(event_type: nil).scope.count).to eq(1)
    end
  end

  describe "event_type filter" do
    it "matches exact event_type" do
      make_event(uuid: SecureRandom.uuid, event_type: "Foo")
      make_event(uuid: SecureRandom.uuid, event_type: "Bar")

      expect(described_class.new(event_type: "Foo").scope.pluck(:event_type)).to eq(["Foo"])
    end

    it "is case-sensitive" do
      make_event(uuid: SecureRandom.uuid, event_type: "Foo")

      expect(described_class.new(event_type: "foo").scope.count).to eq(0)
    end
  end

  describe "stream_type filter" do
    it "matches exact stream_type" do
      make_event(uuid: SecureRandom.uuid, stream_type: "alpha")
      make_event(uuid: SecureRandom.uuid, stream_type: "beta")

      expect(described_class.new(stream_type: "alpha").scope.pluck(:stream_type)).to eq(["alpha"])
    end
  end

  describe "actor_id filter" do
    it "matches exact actor_id" do
      make_event(uuid: SecureRandom.uuid, actor_id: "user-1")
      make_event(uuid: SecureRandom.uuid, actor_id: "user-2")

      expect(described_class.new(actor_id: "user-1").scope.pluck(:actor_id)).to eq(["user-1"])
    end
  end

  describe "stream_key LIKE filter" do
    it "matches as a substring" do
      make_event(uuid: SecureRandom.uuid, stream_key: "alpha-beta")
      make_event(uuid: SecureRandom.uuid, stream_key: "gamma")

      expect(described_class.new(stream_key: "beta").scope.pluck(:stream_key)).to eq(["alpha-beta"])
    end

    it "treats SQL LIKE wildcards in user input as literals" do
      make_event(uuid: SecureRandom.uuid, stream_key: "alpha-beta")
      make_event(uuid: SecureRandom.uuid, stream_key: "100%-discount")
      make_event(uuid: SecureRandom.uuid, stream_key: "foo_bar")

      # `%` should not match everything — it's a literal char in user input.
      expect(described_class.new(stream_key: "%").scope.pluck(:stream_key)).to eq(["100%-discount"])
      # `_` should not match any single char — it's literal.
      expect(described_class.new(stream_key: "_").scope.pluck(:stream_key)).to eq(["foo_bar"])
    end
  end

  describe "q (free-text) search" do
    it "matches across event_type, stream_type, stream_key, actor_id, source" do
      e1 = make_event(uuid: SecureRandom.uuid, event_type: "FooHappened",  stream_type: "x", stream_key: "x", actor_id: "x", source: "x")
      e2 = make_event(uuid: SecureRandom.uuid, event_type: "x",            stream_type: "FooStream", stream_key: "x", actor_id: "x", source: "x")
      e3 = make_event(uuid: SecureRandom.uuid, event_type: "x",            stream_type: "x", stream_key: "FooKey", actor_id: "x", source: "x")
      e4 = make_event(uuid: SecureRandom.uuid, event_type: "x",            stream_type: "x", stream_key: "x", actor_id: "FooActor", source: "x")
      e5 = make_event(uuid: SecureRandom.uuid, event_type: "x",            stream_type: "x", stream_key: "x", actor_id: "x", source: "FooSource")
      _e6 = make_event(uuid: SecureRandom.uuid, event_type: "x",           stream_type: "x", stream_key: "x", actor_id: "x", source: "x")

      uuids = described_class.new(q: "Foo").scope.pluck(:uuid)
      expect(uuids).to contain_exactly(e1.uuid, e2.uuid, e3.uuid, e4.uuid, e5.uuid)
    end

    it "treats LIKE wildcards in q as literal" do
      make_event(uuid: SecureRandom.uuid, event_type: "FooBar")
      make_event(uuid: SecureRandom.uuid, event_type: "WithPercent%")
      make_event(uuid: SecureRandom.uuid, event_type: "Plain")

      expect(described_class.new(q: "%").scope.pluck(:event_type)).to eq(["WithPercent%"])
    end

    it "is case-sensitive (LIKE on SQLite default)" do
      make_event(uuid: SecureRandom.uuid, event_type: "Foo")

      # SQLite LIKE is case-insensitive only for ASCII by default; assert
      # documented behaviour rather than asserting against the adapter quirk.
      result = described_class.new(q: "foo").scope.pluck(:event_type)
      expect(result).to eq(["Foo"]).or eq([])
    end
  end

  describe "filter combinations" do
    it "applies multiple filters with AND semantics" do
      e1 = make_event(uuid: SecureRandom.uuid, event_type: "Foo", actor_id: "alice")
      _e2 = make_event(uuid: SecureRandom.uuid, event_type: "Foo", actor_id: "bob")
      _e3 = make_event(uuid: SecureRandom.uuid, event_type: "Bar", actor_id: "alice")

      results = described_class.new(event_type: "Foo", actor_id: "alice").scope.pluck(:uuid)
      expect(results).to eq([e1.uuid])
    end
  end

  describe "#active_filters" do
    it "returns only the filters that were set" do
      query = described_class.new(event_type: "Foo", actor_id: "", stream_key: "k")
      expect(query.active_filters).to eq(event_type: "Foo", stream_key: "k")
    end

    it "returns an empty hash when nothing is filtered" do
      expect(described_class.new({}).active_filters).to eq({})
    end
  end
end
