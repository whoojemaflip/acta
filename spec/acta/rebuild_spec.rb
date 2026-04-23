# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta.rebuild!", :active_record do
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

  it "invokes truncate! on each registered projection class" do
    truncated = []

    p1 = Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { truncated << :one }
    end
    p2 = Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { truncated << :two }
    end
    stub_const("P1", p1)
    stub_const("P2", p2)

    Acta.rebuild!

    expect(truncated).to contain_exactly(:one, :two)
  end

  it "replays events through projections in insertion order" do
    state = []

    projection = Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { state.clear }
      on BookAdded do |event|
        state << event.book_id
      end
    end
    stub_const("CollectProjection", projection)

    Acta.emit(event_class.new(book_id: "w1", name: "A"))
    Acta.emit(event_class.new(book_id: "w2", name: "B"))
    Acta.emit(event_class.new(book_id: "w3", name: "C"))

    state.clear
    state << "stale_data"

    Acta.rebuild!

    expect(state).to eq([ "w1", "w2", "w3" ])
  end

  it "does not invoke base handlers during replay" do
    handler_invocations = 0
    handler = Class.new(Acta::Handler) do
      on BookAdded do |_event|
        handler_invocations += 1
      end
    end
    stub_const("HandlerOnly", handler)

    Acta.emit(event_class.new(book_id: "w1", name: "A"))
    expect(handler_invocations).to eq(1)

    Acta.rebuild!

    expect(handler_invocations).to eq(1)
  end

  it "Acta::Projection.truncate! default is a no-op" do
    klass = Class.new(Acta::Projection)
    stub_const("DefaultProjection", klass)

    expect { klass.truncate! }.not_to raise_error
  end

  it "replays deterministically — running rebuild twice yields the same projected state" do
    state = []

    projection = Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { state.clear }
      on BookAdded do |event|
        state << event.book_id
      end
    end
    stub_const("DetProjection", projection)

    Acta.emit(event_class.new(book_id: "w1", name: "A"))
    Acta.emit(event_class.new(book_id: "w2", name: "B"))

    Acta.rebuild!
    first_pass = state.dup

    Acta.rebuild!
    second_pass = state.dup

    expect(second_pass).to eq(first_pass)
  end
end
