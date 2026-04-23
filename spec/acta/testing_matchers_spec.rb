# frozen_string_literal: true

require "rails_helper"
require "acta/testing/matchers"

RSpec.describe "Acta testing matchers", :active_record do
  let(:event_class) do
    klass = Class.new(Acta::Event) do
      attribute :foo, :string
      validates :foo, presence: true
    end
    stub_const("FooHappened", klass)
    klass
  end

  let(:other_event_class) do
    klass = Class.new(Acta::Event) do
      attribute :bar, :string
      validates :bar, presence: true
    end
    stub_const("BarHappened", klass)
    klass
  end

  before do
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta::Current.actor = Acta::Actor.new(type: "system")
    event_class
    other_event_class
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
  end

  describe "emit" do
    it "passes when the block emits the expected event class" do
      expect {
        Acta.emit(event_class.new(foo: "x"))
      }.to emit(event_class)
    end

    it "fails when the block emits nothing" do
      expect {
        expect { nil }.to emit(event_class)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "fails when the block emits a different event class" do
      expect {
        expect {
          Acta.emit(other_event_class.new(bar: "x"))
        }.to emit(event_class)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    describe "with matching attributes" do
      it "passes when a matching event is emitted" do
        expect {
          Acta.emit(event_class.new(foo: "hello"))
        }.to emit(event_class).with(foo: "hello")
      end

      it "fails when no emitted event has the expected attributes" do
        expect {
          expect {
            Acta.emit(event_class.new(foo: "hello"))
          }.to emit(event_class).with(foo: "different")
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
      end
    end
  end

  describe "emit_events" do
    it "passes when the block emits events of matching classes in order" do
      expect {
        Acta.emit(event_class.new(foo: "1"))
        Acta.emit(other_event_class.new(bar: "2"))
      }.to emit_events([ event_class, other_event_class ])
    end

    it "fails when the order does not match" do
      expect {
        expect {
          Acta.emit(other_event_class.new(bar: "1"))
          Acta.emit(event_class.new(foo: "2"))
        }.to emit_events([ event_class, other_event_class ])
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "fails when counts don't match" do
      expect {
        expect {
          Acta.emit(event_class.new(foo: "1"))
        }.to emit_events([ event_class, other_event_class ])
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end

  describe "emit_any_events" do
    it "passes (negated) when the block emits no events" do
      expect { nil }.not_to emit_any_events
    end

    it "fails (negated) when the block emits an event" do
      expect {
        expect { Acta.emit(event_class.new(foo: "x")) }.not_to emit_any_events
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "passes (positive) when the block emits something" do
      expect {
        Acta.emit(event_class.new(foo: "x"))
      }.to emit_any_events
    end
  end
end
