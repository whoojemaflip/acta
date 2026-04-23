# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta attribute with array_of:", :active_record do
  let(:tag_class) do
    klass = Class.new(Acta::Model) do
      attribute :label, :string
      attribute :value, :integer
    end
    stub_const("Tag", klass)
    klass
  end

  let(:event_class) do
    klass = Class.new(Acta::Event) do
      attribute :tags, array_of: Tag
      attribute :category, :string
      validates :category, presence: true
    end
    stub_const("Tagged", klass)
    klass
  end

  before do
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta::Current.actor = Acta::Actor.new(type: "system")
    tag_class
    event_class
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
  end

  it "accepts typed instances in the array" do
    tags = [
      tag_class.new(label: "a", value: 1),
      tag_class.new(label: "b", value: 2)
    ]
    event = event_class.new(category: "x", tags:)

    expect(event.tags).to all be_a(tag_class)
    expect(event.tags.map(&:label)).to eq([ "a", "b" ])
  end

  it "coerces an array of hashes into typed instances" do
    event = event_class.new(
      category: "x",
      tags: [ { label: "a", value: 1 }, { label: "b", value: 2 } ]
    )

    expect(event.tags).to all be_a(tag_class)
    expect(event.tags[1].value).to eq(2)
  end

  it "serialises to an array of hashes in payload_hash" do
    event = event_class.new(category: "x", tags: [ { label: "a", value: 1 } ])

    expect(event.payload_hash["tags"]).to eq([ { "label" => "a", "value" => 1 } ])
  end

  it "round-trips through emit/events" do
    event = event_class.new(
      category: "x",
      tags: [ { label: "a", value: 1 }, { label: "b", value: 2 } ]
    )
    Acta.emit(event)

    reloaded = Acta.events.last

    expect(reloaded.tags).to all be_a(tag_class)
    expect(reloaded.tags.map(&:label)).to eq([ "a", "b" ])
  end

  it "accepts nil" do
    event = event_class.new(category: "x", tags: nil)

    expect(event.tags).to be_nil
  end

  it "accepts an empty array" do
    event = event_class.new(category: "x", tags: [])

    expect(event.tags).to eq([])
  end

  it "supports array_of: scalar types like :string" do
    klass = Class.new(Acta::Event) do
      attribute :labels, array_of: :string
      attribute :category, :string
      validates :category, presence: true
    end
    stub_const("LabeledEvent", klass)

    event = klass.new(category: "x", labels: [ "a", "b", "c" ])

    expect(event.labels).to eq([ "a", "b", "c" ])
  end
end
