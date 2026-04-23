# frozen_string_literal: true

require "spec_helper"

RSpec.describe Acta::Current do
  after { described_class.reset }

  it "is a subclass of ActiveSupport::CurrentAttributes" do
    expect(described_class.ancestors).to include(ActiveSupport::CurrentAttributes)
  end

  it "starts with no actor" do
    expect(described_class.actor).to be_nil
  end

  it "can set and read an actor" do
    actor = Acta::Actor.new(type: "user", id: "u_1")
    described_class.actor = actor

    expect(described_class.actor).to eq(actor)
  end

  it "resets the actor on .reset" do
    described_class.actor = Acta::Actor.new(type: "system")
    described_class.reset

    expect(described_class.actor).to be_nil
  end
end
