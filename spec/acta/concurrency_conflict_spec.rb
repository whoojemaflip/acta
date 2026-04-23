# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta concurrency handling", :active_record do
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

  let(:actor) { Acta::Actor.new(type: "system") }

  before do
    Acta.reset_adapter!
    Acta::Current.actor = actor
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
  end

  it "raises Acta::ConcurrencyConflict when a concurrent writer took the sequence" do
    Acta.emit(event_class.new(book_id: "w_1", name: "First"))

    adapter = Acta.adapter
    allow(adapter).to receive(:compute_next_sequence).and_return(1)

    expect {
      Acta.emit(event_class.new(book_id: "w_1", name: "Concurrent"))
    }.to raise_error(Acta::ConcurrencyConflict) do |error|
      expect(error.stream_type).to eq("book")
      expect(error.stream_key).to eq("w_1")
      expect(error.expected_sequence).to eq(1)
      expect(error.actual_sequence).to eq(1)
    end
  end

  it "re-raises ActiveRecord::RecordNotUnique for non-stream conflicts (e.g. duplicate uuid)" do
    event = Acta.emit(event_class.new(book_id: "w_1", name: "First"))
    collision = event_class.new(uuid: event.uuid, book_id: "w_2", name: "Collision")

    expect { Acta.emit(collision) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe "the ConcurrencyConflict error" do
    subject(:error) do
      Acta::ConcurrencyConflict.new(
        stream_type: "book",
        stream_key: "w_1",
        expected_sequence: 8,
        actual_sequence: 11
      )
    end

    it "is an Acta::Error" do
      expect(error).to be_a(Acta::Error)
    end

    it "carries stream identity and both sequences" do
      expect(error.stream_type).to eq("book")
      expect(error.stream_key).to eq("w_1")
      expect(error.expected_sequence).to eq(8)
      expect(error.actual_sequence).to eq(11)
    end

    it "has a descriptive message" do
      expect(error.message).to include("book/w_1")
      expect(error.message).to include("8")
      expect(error.message).to include("11")
    end
  end
end
