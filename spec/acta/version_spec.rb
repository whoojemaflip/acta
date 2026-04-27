# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta stream versioning", :active_record do
  let(:event_class) do
    klass = Class.new(Acta::Event) do
      stream :order, key: :order_id
      attribute :order_id, :string
      attribute :note, :string
      validates :order_id, presence: true
    end
    stub_const("OrderNoted", klass)
    klass
  end

  let(:streamless_class) do
    klass = Class.new(Acta::Event) do
      attribute :payload, :string
    end
    stub_const("StreamlessEvent", klass)
    klass
  end

  before do
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta::Current.actor = Acta::Actor.new(type: "system")
    event_class
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
  end

  describe ".version_of" do
    it "returns 0 for a stream that has never been emitted to" do
      expect(Acta.version_of(stream_type: :order, stream_key: "o_1")).to eq(0)
    end

    it "returns the current sequence after emits" do
      Acta.emit(event_class.new(order_id: "o_1", note: "first"))
      expect(Acta.version_of(stream_type: :order, stream_key: "o_1")).to eq(1)

      Acta.emit(event_class.new(order_id: "o_1", note: "second"))
      Acta.emit(event_class.new(order_id: "o_1", note: "third"))
      expect(Acta.version_of(stream_type: :order, stream_key: "o_1")).to eq(3)
    end

    it "scopes per (stream_type, stream_key) tuple" do
      Acta.emit(event_class.new(order_id: "o_1", note: "x"))
      Acta.emit(event_class.new(order_id: "o_2", note: "y"))
      Acta.emit(event_class.new(order_id: "o_2", note: "z"))

      expect(Acta.version_of(stream_type: :order, stream_key: "o_1")).to eq(1)
      expect(Acta.version_of(stream_type: :order, stream_key: "o_2")).to eq(2)
      expect(Acta.version_of(stream_type: :order, stream_key: "o_3")).to eq(0)
    end

    it "accepts string or symbol stream_type" do
      Acta.emit(event_class.new(order_id: "o_1", note: "x"))
      expect(Acta.version_of(stream_type: :order, stream_key: "o_1")).to eq(1)
      expect(Acta.version_of(stream_type: "order", stream_key: "o_1")).to eq(1)
    end
  end

  describe ".emit with if_version:" do
    it "succeeds when the stream is at the asserted version" do
      Acta.emit(event_class.new(order_id: "o_1", note: "first"))

      expect {
        Acta.emit(event_class.new(order_id: "o_1", note: "second"), if_version: 1)
      }.not_to raise_error
    end

    it "succeeds with if_version: 0 for a fresh stream" do
      expect {
        Acta.emit(event_class.new(order_id: "o_1", note: "first"), if_version: 0)
      }.not_to raise_error
    end

    it "raises VersionConflict when the stream has moved past the asserted version" do
      Acta.emit(event_class.new(order_id: "o_1", note: "first"))
      Acta.emit(event_class.new(order_id: "o_1", note: "second"))

      expect {
        Acta.emit(event_class.new(order_id: "o_1", note: "third"), if_version: 1)
      }.to raise_error(Acta::VersionConflict) do |error|
        expect(error.stream_type).to eq("order")
        expect(error.stream_key).to eq("o_1")
        expect(error.expected_version).to eq(1)
        expect(error.actual_version).to eq(2)
      end
    end

    it "raises VersionConflict when expecting a fresh stream that already has events" do
      Acta.emit(event_class.new(order_id: "o_1", note: "first"))

      expect {
        Acta.emit(event_class.new(order_id: "o_1", note: "second"), if_version: 0)
      }.to raise_error(Acta::VersionConflict)
    end

    it "raises ArgumentError when if_version is given but the event has no stream" do
      expect {
        Acta.emit(streamless_class.new(payload: "x"), if_version: 0)
      }.to raise_error(ArgumentError, /if_version requires the event to declare a stream/)
    end

    it "skips the version check entirely when if_version is nil (default)" do
      Acta.emit(event_class.new(order_id: "o_1", note: "first"))
      Acta.emit(event_class.new(order_id: "o_1", note: "second"))

      expect {
        Acta.emit(event_class.new(order_id: "o_1", note: "third"))
      }.not_to raise_error
    end
  end

  describe "Acta::VersionConflict" do
    it "carries the stream identity and version mismatch details" do
      error = Acta::VersionConflict.new(
        stream_type: "order",
        stream_key: "o_42",
        expected_version: 3,
        actual_version: 5
      )

      expect(error.stream_type).to eq("order")
      expect(error.stream_key).to eq("o_42")
      expect(error.expected_version).to eq(3)
      expect(error.actual_version).to eq(5)
      expect(error.message).to include("order/o_42")
      expect(error.message).to include("expected version 3")
      expect(error.message).to include("at version 5")
    end
  end
end
