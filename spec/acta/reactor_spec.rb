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

  describe "queue configuration" do
    around do |example|
      original = Acta.reactor_queue
      example.run
    ensure
      Acta.reactor_queue = original
    end

    it "lands on ActiveJob's default queue when nothing is configured" do
      klass = Class.new(described_class) do
        on TestEvent do |_event|
        end
      end
      stub_const("DefaultQueueReactor", klass)

      Acta.emit(event_class.new(thing: "x"))

      expect(enqueued_jobs.first[:queue]).to eq("default")
    end

    it "uses the per-class queue_as when declared" do
      klass = Class.new(described_class) do
        queue_as :fast
        on TestEvent do |_event|
        end
      end
      stub_const("FastQueueReactor", klass)

      Acta.emit(event_class.new(thing: "x"))

      expect(enqueued_jobs.first[:queue]).to eq("fast")
    end

    it "falls back to Acta.reactor_queue when the class declares nothing" do
      Acta.reactor_queue = :background
      klass = Class.new(described_class) do
        on TestEvent do |_event|
        end
      end
      stub_const("GlobalQueueReactor", klass)

      Acta.emit(event_class.new(thing: "x"))

      expect(enqueued_jobs.first[:queue]).to eq("background")
    end

    it "per-class queue_as takes precedence over Acta.reactor_queue" do
      Acta.reactor_queue = :slow
      klass = Class.new(described_class) do
        queue_as :fast
        on TestEvent do |_event|
        end
      end
      stub_const("OverrideQueueReactor", klass)

      Acta.emit(event_class.new(thing: "x"))

      expect(enqueued_jobs.first[:queue]).to eq("fast")
    end

    it "is ignored for sync! reactors (no job is enqueued at all)" do
      Acta.reactor_queue = :should_not_matter
      klass = Class.new(described_class) do
        sync!
        queue_as :also_should_not_matter
        on TestEvent do |_event|
        end
      end
      stub_const("SyncQueueReactor", klass)

      Acta.emit(event_class.new(thing: "x"))

      expect(enqueued_jobs).to be_empty
    end
  end
end
