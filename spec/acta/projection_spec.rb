# frozen_string_literal: true

require "rails_helper"

RSpec.describe Acta::Projection, :active_record do
  let(:event_class) do
    klass = Class.new(Acta::Event) do
      attribute :book_id, :string
      attribute :name, :string
      validates :book_id, :name, presence: true
    end
    stub_const("BookAdded", klass)
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

  it "inherits from Acta::Handler" do
    expect(described_class.ancestors).to include(Acta::Handler)
  end

  it "runs on emit via the on(event) DSL" do
    invocations = []
    Class.new(described_class) do
      on BookAdded do |event|
        invocations << event.book_id
      end
    end

    Acta.emit(event_class.new(book_id: "w1", name: "A"))

    expect(invocations).to eq([ "w1" ])
  end

  it "runs inside the insert transaction — raising a projection rolls back the insert" do
    Class.new(described_class) do
      on BookAdded do |_event|
        raise "projection exploded"
      end
    end

    initial_count = Acta::Record.count

    expect {
      Acta.emit(event_class.new(book_id: "w1", name: "A"))
    }.to raise_error(Acta::ProjectionError, /projection exploded/)

    expect(Acta::Record.count).to eq(initial_count)
  end

  it "runs projections BEFORE base handlers" do
    order = []

    Class.new(described_class) do
      on BookAdded do |_e|
        order << :projection
      end
    end

    Class.new(Acta::Handler) do
      on BookAdded do |_e|
        order << :handler
      end
    end

    Acta.emit(event_class.new(book_id: "w1", name: "A"))

    expect(order).to eq([ :projection, :handler ])
  end

  it "a failing projection prevents base handlers from running" do
    handler_ran = false

    Class.new(described_class) do
      on BookAdded do |_e|
        raise "nope"
      end
    end

    Class.new(Acta::Handler) do
      on BookAdded do |_e|
        handler_ran = true
      end
    end

    begin
      Acta.emit(event_class.new(book_id: "w1", name: "A"))
    rescue StandardError
      # expected
    end

    expect(handler_ran).to be(false)
  end
end
