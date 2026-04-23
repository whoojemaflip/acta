# frozen_string_literal: true

require "rails_helper"
require "acta/testing"

RSpec.describe Acta::Testing, :active_record do
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
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  describe ".test_mode" do
    it "runs async reactors inline for the duration of the block" do
      invocations = []
      reactor = Class.new(Acta::Reactor) do
        on TestEvent do |event|
          invocations << event.thing
        end
      end
      stub_const("AsyncReactor", reactor)

      Acta.emit(event_class.new(thing: "outside"))
      expect(invocations).to be_empty

      described_class.test_mode do
        Acta.emit(event_class.new(thing: "inside"))
      end

      expect(invocations).to eq([ "inside" ])
    end

    it "restores the original queue adapter after the block" do
      original = ActiveJob::Base.queue_adapter
      described_class.test_mode { }

      expect(ActiveJob::Base.queue_adapter).to eq(original)
    end

    it "restores the adapter even when the block raises" do
      original = ActiveJob::Base.queue_adapter

      expect {
        described_class.test_mode { raise "boom" }
      }.to raise_error(RuntimeError, "boom")

      expect(ActiveJob::Base.queue_adapter).to eq(original)
    end
  end
end
