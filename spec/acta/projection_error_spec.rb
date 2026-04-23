# frozen_string_literal: true

require "rails_helper"

RSpec.describe Acta::ProjectionError, :active_record do
  let(:event_class) do
    klass = Class.new(Acta::Event) do
      attribute :thing, :string
      validates :thing, presence: true
    end
    stub_const("TestEvent", klass)
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
    expect(described_class).to be < Acta::Error
  end

  context "when a projection raises" do
    let(:projection_class) do
      klass = Class.new(Acta::Projection) do
        on TestEvent do |_event|
          raise "original failure"
        end
      end
      stub_const("FailingProjection", klass)
      klass
    end

    before { projection_class }

    it "wraps the exception as ProjectionError" do
      expect {
        Acta.emit(event_class.new(thing: "x"))
      }.to raise_error(described_class)
    end

    it "carries the event, projection class, and original exception" do
      Acta.emit(event_class.new(thing: "x"))
    rescue described_class => e
      expect(e.event).to be_a(event_class)
      expect(e.projection_class).to eq(projection_class)
      expect(e.original).to be_a(RuntimeError)
      expect(e.original.message).to eq("original failure")
    end

    it "includes the event type, projection class, and original message in its message" do
      Acta.emit(event_class.new(thing: "x"))
    rescue described_class => e
      expect(e.message).to include("TestEvent")
      expect(e.message).to include("FailingProjection")
      expect(e.message).to include("original failure")
    end
  end

  context "when a base handler raises" do
    before do
      Class.new(Acta::Handler) do
        on TestEvent do |_event|
          raise "handler boom"
        end
      end
    end

    it "propagates the original exception unwrapped" do
      expect {
        Acta.emit(event_class.new(thing: "x"))
      }.to raise_error(RuntimeError, /handler boom/)
    end
  end
end
