# frozen_string_literal: true

require "rails_helper"

RSpec.describe Acta::Reactor, :active_record do
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

  def enqueued_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs
  end

  it "inherits from Acta::Handler" do
    expect(described_class.ancestors).to include(Acta::Handler)
  end

  describe "default async via ActiveJob" do
    it "enqueues an Acta::ReactorJob instead of invoking the block at emit time" do
      invocations = []
      klass = Class.new(described_class) do
        on TestEvent do |event|
          invocations << event.thing
        end
      end
      stub_const("AsyncReactor", klass)

      Acta.emit(event_class.new(thing: "x"))

      expect(invocations).to be_empty
      expect(enqueued_jobs.size).to eq(1)
      expect(enqueued_jobs.first[:job]).to eq(Acta::ReactorJob)
    end

    it "invokes the block when the job is performed (via :inline adapter)" do
      invocations = []
      klass = Class.new(described_class) do
        on TestEvent do |event|
          invocations << event.thing
        end
      end
      stub_const("AsyncReactor", klass)

      ActiveJob::Base.queue_adapter = :inline
      Acta.emit(event_class.new(thing: "x"))

      expect(invocations).to eq([ "x" ])
    end
  end

  describe "sync! opt-in" do
    it "invokes the block synchronously without enqueuing a job" do
      invocations = []
      klass = Class.new(described_class) do
        sync!
        on TestEvent do |event|
          invocations << event.thing
        end
      end
      stub_const("SyncReactor", klass)

      Acta.emit(event_class.new(thing: "x"))

      expect(invocations).to eq([ "x" ])
      expect(enqueued_jobs).to be_empty
    end

    it "reports sync? correctly" do
      sync_reactor = Class.new(described_class) { sync! }
      async_reactor = Class.new(described_class)

      expect(sync_reactor.sync?).to be(true)
      expect(async_reactor.sync?).to be(false)
    end
  end

  describe "replay" do
    it "does not invoke reactors during Acta.rebuild!" do
      invocations = []
      klass = Class.new(described_class) do
        sync!
        on TestEvent do |_event|
          invocations << :ran
        end
      end
      stub_const("ReplayReactor", klass)

      Acta.emit(event_class.new(thing: "x"))
      invocations.clear

      Acta.rebuild!

      expect(invocations).to be_empty
    end
  end

  describe "actor propagation" do
    it "exposes Acta::Current.actor to sync reactors" do
      seen_actor = nil
      klass = Class.new(described_class) do
        sync!
        on TestEvent do |_event|
          seen_actor = Acta::Current.actor
        end
      end
      stub_const("ActorSyncReactor", klass)

      my_actor = Acta::Actor.new(type: "user", id: "u_1", source: "admin_ui")
      Acta::Current.actor = my_actor

      Acta.emit(event_class.new(thing: "x"))

      expect(seen_actor).to eq(my_actor)
    end
  end
end
