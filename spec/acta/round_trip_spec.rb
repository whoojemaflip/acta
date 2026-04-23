# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta.emit round-trip", :active_record do
  let(:event_class) do
    klass = Class.new(Acta::Event) do
      attribute :book_id, :string
      attribute :new_name, :string
      validates :book_id, :new_name, presence: true
    end
    stub_const("BookRenamed", klass)
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

  it "persists an event and reads it back as the same class" do
    event = event_class.new(book_id: "w_1", new_name: "Foo Reserve")
    emitted = Acta.emit(event)

    expect(emitted.recorded_at).not_to be_nil

    reloaded = Acta.events.last

    expect(reloaded).to be_a(event_class)
    expect(reloaded.book_id).to eq("w_1")
    expect(reloaded.new_name).to eq("Foo Reserve")
    expect(reloaded.uuid).to eq(event.uuid)
    expect(reloaded.actor).to eq(actor)
  end

  it "preserves occurred_at across round-trip" do
    occurred_at = Time.utc(2026, 4, 23, 12, 0, 0)
    event = event_class.new(book_id: "w_1", new_name: "Foo", occurred_at:)

    Acta.emit(event)

    expect(Acta.events.last.occurred_at).to be_within(1.second).of(occurred_at)
  end

  it "raises Acta::MissingActor when no actor is set anywhere" do
    Acta::Current.reset
    event = event_class.new(book_id: "w_1", new_name: "Foo")

    expect { Acta.emit(event) }.to raise_error(Acta::MissingActor)
  end

  it "accepts an explicit actor: override at emit time" do
    Acta::Current.reset
    event = event_class.new(book_id: "w_1", new_name: "Foo")
    override = Acta::Actor.new(type: "system", source: "migration_2026_04_23")

    Acta.emit(event, actor: override)

    expect(Acta.events.last.actor).to eq(override)
  end

  it "orders events by id (insertion order) by default" do
    Acta.emit(event_class.new(book_id: "w_1", new_name: "First"))
    Acta.emit(event_class.new(book_id: "w_2", new_name: "Second"))
    Acta.emit(event_class.new(book_id: "w_3", new_name: "Third"))

    names = Acta.events.all.map(&:new_name)

    expect(names).to eq([ "First", "Second", "Third" ])
  end
end
