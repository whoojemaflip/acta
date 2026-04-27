# frozen_string_literal: true

require "rails_helper"
require "acta/testing"

RSpec.describe Acta::Testing, ".default_actor!" do
  let(:rspec_config) { RSpec::Core::Configuration.new }

  let(:example_group) do
    RSpec.describe("acta default_actor host") do
      include Acta::Testing
    end
  end

  def run_example(example_group, &body)
    example_group.example("default actor host", &body)
    runner = RSpec::Core::Reporter.new(rspec_config)
    example_group.run(runner)
  end

  before do
    Acta::Current.reset
  end

  after do
    Acta::Current.reset
  end

  it "sets Acta::Current.actor before each example with a default system actor" do
    described_class.default_actor!(example_group)

    captured = nil
    run_example(example_group) { captured = Acta::Current.actor }

    expect(captured).to be_a(Acta::Actor)
    expect(captured.type).to eq("system")
    expect(captured.id).to eq("rspec")
    expect(captured.source).to eq("test")
  end

  it "accepts overrides for the actor's attributes" do
    described_class.default_actor!(example_group, type: "user", id: "test-user-1", source: "spec")

    captured = nil
    run_example(example_group) { captured = Acta::Current.actor }

    expect(captured.type).to eq("user")
    expect(captured.id).to eq("test-user-1")
    expect(captured.source).to eq("spec")
  end

  it "merges overrides on top of the defaults" do
    described_class.default_actor!(example_group, id: "custom-id")

    captured = nil
    run_example(example_group) { captured = Acta::Current.actor }

    expect(captured.type).to eq("system")
    expect(captured.id).to eq("custom-id")
    expect(captured.source).to eq("test")
  end

  it "resets Acta::Current after each example" do
    described_class.default_actor!(example_group)

    run_example(example_group) { } # set actor in before; reset in after

    expect(Acta::Current.actor).to be_nil
  end

  it "lets an individual example override the actor inline" do
    described_class.default_actor!(example_group)

    captured = nil
    run_example(example_group) do
      Acta::Current.actor = Acta::Actor.new(type: "user", id: "u_1", source: "web")
      captured = Acta::Current.actor
    end

    expect(captured.type).to eq("user")
    expect(captured.id).to eq("u_1")
  end
end
