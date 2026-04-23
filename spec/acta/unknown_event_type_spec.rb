# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta::UnknownEventType handling", :active_record do
  let(:event_class) do
    klass = Class.new(Acta::Event) do
      attribute :thing, :string
      validates :thing, presence: true
    end
    stub_const("StillKnown", klass)
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

  it "is an Acta::Error" do
    expect(Acta::UnknownEventType).to be < Acta::Error
  end

  it "carries the unknown event_type string" do
    err = Acta::UnknownEventType.new("GhostEvent")

    expect(err.event_type).to eq("GhostEvent")
    expect(err.message).to include("GhostEvent")
  end

  it "is raised when Acta.events hydrates a row with an unknown class" do
    Acta.emit(event_class.new(thing: "x"))

    # Insert a row whose event_type points to a class that doesn't exist
    Acta::Record.create!(
      uuid: SecureRandom.uuid,
      event_type: "NonExistentClass",
      event_version: 1,
      payload: {},
      actor_type: "system",
      occurred_at: Time.current,
      recorded_at: Time.current
    )

    expect { Acta.events.last }.to raise_error(Acta::UnknownEventType, /NonExistentClass/)
  end
end
