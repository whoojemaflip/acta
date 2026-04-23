# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta handler dispatch", :active_record do
  let(:event_class) do
    klass = Class.new(Acta::Event) do
      attribute :book_id, :string
      attribute :note, :string
      validates :book_id, :note, presence: true
    end
    stub_const("BookNoted", klass)
    klass
  end

  let(:other_event_class) do
    klass = Class.new(Acta::Event) do
      attribute :thing, :string
      validates :thing, presence: true
    end
    stub_const("Unrelated", klass)
    klass
  end

  before do
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta::Current.actor = Acta::Actor.new(type: "system")
    # Force both event classes to exist before handler registration
    event_class
    other_event_class
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
  end

  it "invokes handlers registered for the event type" do
    invocations = []

    Class.new(Acta::Handler) do
      on BookNoted do |event|
        invocations << event.note
      end
    end

    Acta.emit(event_class.new(book_id: "w1", note: "Great finish"))

    expect(invocations).to eq([ "Great finish" ])
  end

  it "does not invoke a handler for unrelated event types" do
    invocations = []

    Class.new(Acta::Handler) do
      on BookNoted do |_event|
        invocations << :book
      end
    end

    Acta.emit(other_event_class.new(thing: "x"))

    expect(invocations).to be_empty
  end

  it "invokes multiple handlers for the same event" do
    invocations = []

    Class.new(Acta::Handler) do
      on BookNoted do |_event|
        invocations << :first
      end
    end

    Class.new(Acta::Handler) do
      on BookNoted do |_event|
        invocations << :second
      end
    end

    Acta.emit(event_class.new(book_id: "w1", note: "x"))

    expect(invocations).to contain_exactly(:first, :second)
  end

  it "passes the same event instance that emit returned" do
    captured = nil
    Class.new(Acta::Handler) do
      on BookNoted do |event|
        captured = event
      end
    end

    emitted = Acta.emit(event_class.new(book_id: "w1", note: "x"))

    expect(captured).to be(emitted)
  end

  it "a single handler class can subscribe to multiple event types" do
    invocations = []
    Class.new(Acta::Handler) do
      on BookNoted do |_event|
        invocations << :book
      end

      on Unrelated do |_event|
        invocations << :other
      end
    end

    Acta.emit(event_class.new(book_id: "w1", note: "x"))
    Acta.emit(other_event_class.new(thing: "y"))

    expect(invocations).to eq([ :book, :other ])
  end

  it "reset_handlers! clears all registrations" do
    Class.new(Acta::Handler) do
      on BookNoted do |_event|
        raise "should not run"
      end
    end

    Acta.reset_handlers!

    expect {
      Acta.emit(event_class.new(book_id: "w1", note: "x"))
    }.not_to raise_error
  end
end
