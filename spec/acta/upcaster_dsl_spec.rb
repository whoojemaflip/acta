# frozen_string_literal: true

require "rails_helper"
require "acta/testing/dsl"

RSpec.describe "Acta::Testing::DSL upcaster helpers", :active_record do
  include Acta::Testing::DSL

  before do
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta.reset_upcasters!
    Acta::Current.actor = Acta::Actor.new(type: "system", id: "rspec", source: "test")

    item_added = Class.new(Acta::Event) do
      attribute :item_id, :string
      attribute :title, :string
      validates :item_id, :title, presence: true
    end
    stub_const("ItemAdded", item_added)
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta.reset_upcasters!
  end

  describe "#acta_seed_event" do
    it "inserts a record with the specified event_version" do
      acta_seed_event(type: "ItemAdded", event_version: 1, payload: { "item_id" => "x", "title" => "X" })

      record = Acta::Record.last
      expect(record.event_type).to eq("ItemAdded")
      expect(record.event_version).to eq(1)
      expect(record.payload).to eq("item_id" => "x", "title" => "X")
    end

    it "round-trips through hydration when no upcaster is registered" do
      acta_seed_event(type: "ItemAdded", payload: { "item_id" => "x", "title" => "X" })

      event = Acta.events.last
      expect(event).to be_an(ItemAdded)
      expect(event.item_id).to eq("x")
    end
  end

  describe "#acta_replay" do
    it "registers upcasters, seeds events, and triggers rebuild" do
      seen = []
      stub_const("CapProj", Class.new(Acta::Projection) do
        define_singleton_method(:truncate!) { seen.clear }
        on(ItemAdded) { |e| seen << [ e.item_id, e.title ] }
      end)

      upcaster = Module.new do
        include Acta::Upcaster
        upcasts "ItemAdded", from: 1, to: 2 do |event, _ctx|
          event.upcast_to(payload: event.payload.merge("title" => "upcasted:#{event.payload['title']}"),
                          schema_version: 2)
        end
      end
      stub_const("DemoUpcaster", upcaster)

      acta_replay(
        upcasters: [ DemoUpcaster ],
        events: [
          { type: "ItemAdded", event_version: 1, payload: { "item_id" => "a", "title" => "one" } },
          { type: "ItemAdded", event_version: 1, payload: { "item_id" => "b", "title" => "two" } }
        ]
      )

      expect(seen).to eq([ [ "a", "upcasted:one" ], [ "b", "upcasted:two" ] ])
    end
  end
end
