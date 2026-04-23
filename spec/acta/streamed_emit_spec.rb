# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta.emit with streams", :active_record do
  let(:streamed_class) do
    klass = Class.new(Acta::Event) do
      stream :book, key: :book_id
      attribute :book_id, :string
      attribute :new_name, :string
      validates :book_id, :new_name, presence: true
    end
    stub_const("BookRenamed", klass)
    klass
  end

  let(:streamless_class) do
    klass = Class.new(Acta::Event) do
      attribute :thing, :string
      validates :thing, presence: true
    end
    stub_const("ThingHappened", klass)
    klass
  end

  let(:actor) { Acta::Actor.new(type: "user", id: "u_1", source: "admin_ui") }

  before do
    Acta.reset_adapter!
    Acta::Current.actor = actor
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
  end

  it "assigns sequence=1 to the first event in a stream" do
    event = Acta.emit(streamed_class.new(book_id: "w_1", new_name: "First"))
    row = Acta::Record.find_by(uuid: event.uuid)

    expect(row.stream_type).to eq("book")
    expect(row.stream_key).to eq("w_1")
    expect(row.stream_sequence).to eq(1)
  end

  it "increments sequence within the same stream" do
    emitted = 3.times.map do |i|
      Acta.emit(streamed_class.new(book_id: "w_1", new_name: "Change ##{i}"))
    end

    sequences = emitted.map { |e| Acta::Record.find_by(uuid: e.uuid).stream_sequence }

    expect(sequences).to eq([ 1, 2, 3 ])
  end

  it "tracks separate sequences for separate streams" do
    a1 = Acta.emit(streamed_class.new(book_id: "w_a", new_name: "A1"))
    b1 = Acta.emit(streamed_class.new(book_id: "w_b", new_name: "B1"))
    a2 = Acta.emit(streamed_class.new(book_id: "w_a", new_name: "A2"))

    expect(Acta::Record.find_by(uuid: a1.uuid).stream_sequence).to eq(1)
    expect(Acta::Record.find_by(uuid: b1.uuid).stream_sequence).to eq(1)
    expect(Acta::Record.find_by(uuid: a2.uuid).stream_sequence).to eq(2)
  end

  it "leaves stream columns nil for stream-less events" do
    event = Acta.emit(streamless_class.new(thing: "x"))
    row = Acta::Record.find_by(uuid: event.uuid)

    expect(row.stream_type).to be_nil
    expect(row.stream_key).to be_nil
    expect(row.stream_sequence).to be_nil
  end

  it "round-trips streamed events through Acta.events" do
    Acta.emit(streamed_class.new(book_id: "w_1", new_name: "First"))
    Acta.emit(streamed_class.new(book_id: "w_1", new_name: "Second"))

    names = Acta.events.all.map(&:new_name)

    expect(names).to eq([ "First", "Second" ])
  end
end
