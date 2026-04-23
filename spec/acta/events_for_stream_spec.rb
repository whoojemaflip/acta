# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta.events.for_stream", :active_record do
  let(:book_event) do
    klass = Class.new(Acta::Event) do
      stream :book, key: :book_id
      attribute :book_id, :string
      attribute :note, :string
      validates :book_id, :note, presence: true
    end
    stub_const("BookNote", klass)
    klass
  end

  let(:publisher_event) do
    klass = Class.new(Acta::Event) do
      stream :publisher, key: :publisher_id
      attribute :publisher_id, :string
      attribute :name, :string
      validates :publisher_id, :name, presence: true
    end
    stub_const("PublisherRenamed", klass)
    klass
  end

  before do
    Acta.reset_adapter!
    Acta::Current.actor = Acta::Actor.new(type: "system")

    Acta.emit(book_event.new(book_id: "w_1", note: "A1"))
    Acta.emit(publisher_event.new(publisher_id: "wy_1", name: "WA"))
    Acta.emit(book_event.new(book_id: "w_1", note: "A2"))
    Acta.emit(book_event.new(book_id: "w_2", note: "B1"))
    Acta.emit(publisher_event.new(publisher_id: "wy_1", name: "WB"))
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
  end

  it "filters to events in the specified stream" do
    events = Acta.events.for_stream(type: :book, key: "w_1").all

    expect(events.size).to eq(2)
    expect(events.map(&:note)).to eq([ "A1", "A2" ])
  end

  it "does not include events from other streams (same type, different key)" do
    events = Acta.events.for_stream(type: :book, key: "w_1").all

    expect(events.map(&:stream_key).uniq).to eq([ "w_1" ])
  end

  it "does not include events from other stream types" do
    events = Acta.events.for_stream(type: :book, key: "w_1").all

    expect(events.map(&:class).uniq).to eq([ book_event ])
  end

  it "orders by stream_sequence (not by global id)" do
    events = Acta.events.for_stream(type: :publisher, key: "wy_1").all

    expect(events.map(&:name)).to eq([ "WA", "WB" ])
  end

  it "accepts either a symbol or string for :type" do
    symbol_result = Acta.events.for_stream(type: :book, key: "w_1").all
    string_result = Acta.events.for_stream(type: "book", key: "w_1").all

    expect(symbol_result.size).to eq(string_result.size)
    expect(symbol_result.size).to eq(2)
  end

  it "returns an empty result for streams with no events" do
    events = Acta.events.for_stream(type: :book, key: "nonexistent").all

    expect(events).to be_empty
  end

  it "supports .count and .first on the filtered result" do
    scope = Acta.events.for_stream(type: :book, key: "w_1")

    expect(scope.count).to eq(2)
    expect(scope.first.note).to eq("A1")
  end
end
