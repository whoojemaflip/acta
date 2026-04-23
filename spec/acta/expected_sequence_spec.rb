# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta.emit with expected_sequence", :active_record do
  let(:event_class) do
    klass = Class.new(Acta::Event) do
      stream :book, key: :book_id
      attribute :book_id, :string
      attribute :name, :string
      validates :book_id, :name, presence: true
    end
    stub_const("Renamed", klass)
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

  before do
    Acta.reset_adapter!
    Acta::Current.actor = Acta::Actor.new(type: "system")
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
  end

  it "accepts expected_sequence: 0 for a fresh stream" do
    expect {
      Acta.emit(event_class.new(book_id: "w_new", name: "First"), expected_sequence: 0)
    }.not_to raise_error
  end

  it "writes successfully when the stream is at the expected sequence" do
    Acta.emit(event_class.new(book_id: "w_1", name: "First"))

    expect {
      Acta.emit(event_class.new(book_id: "w_1", name: "Second"), expected_sequence: 1)
    }.not_to raise_error
  end

  it "raises ConcurrencyConflict when the stream has advanced since expected" do
    Acta.emit(event_class.new(book_id: "w_1", name: "First"))
    Acta.emit(event_class.new(book_id: "w_1", name: "Second"))

    expect {
      Acta.emit(event_class.new(book_id: "w_1", name: "Stale"), expected_sequence: 1)
    }.to raise_error(Acta::ConcurrencyConflict) do |error|
      expect(error.expected_sequence).to eq(1)
      expect(error.actual_sequence).to eq(2)
    end
  end

  it "raises ConcurrencyConflict when expecting a fresh stream that already has events" do
    Acta.emit(event_class.new(book_id: "w_1", name: "First"))

    expect {
      Acta.emit(event_class.new(book_id: "w_1", name: "Stale"), expected_sequence: 0)
    }.to raise_error(Acta::ConcurrencyConflict)
  end

  it "raises ArgumentError when expected_sequence is given but the event has no stream" do
    expect {
      Acta.emit(streamless_class.new(thing: "x"), expected_sequence: 0)
    }.to raise_error(ArgumentError, /stream/)
  end

  it "does not check when expected_sequence is nil (default)" do
    Acta.emit(event_class.new(book_id: "w_1", name: "First"))
    Acta.emit(event_class.new(book_id: "w_1", name: "Second"))

    expect {
      Acta.emit(event_class.new(book_id: "w_1", name: "Third"))
    }.not_to raise_error
  end
end
