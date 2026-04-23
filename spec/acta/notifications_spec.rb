# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta ActiveSupport::Notifications instrumentation", :active_record do
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

  def subscribe(pattern)
    captured = []
    sub = ActiveSupport::Notifications.subscribe(pattern) do |*args|
      captured << ActiveSupport::Notifications::Event.new(*args)
    end
    yield
    captured
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  it "instruments acta.event_emitted on Acta.emit" do
    events = subscribe("acta.event_emitted") do
      Acta.emit(event_class.new(thing: "x"))
    end

    expect(events.size).to eq(1)
    expect(events.first.payload[:event_type]).to eq("TestEvent")
    expect(events.first.payload[:event]).to be_a(event_class)
  end

  it "instruments acta.projection_applied for each projection invocation" do
    Class.new(Acta::Projection) do
      on TestEvent do |_event|
        nil
      end
    end

    events = subscribe("acta.projection_applied") do
      Acta.emit(event_class.new(thing: "x"))
    end

    expect(events.size).to eq(1)
    expect(events.first.payload[:event]).to be_a(event_class)
    expect(events.first.payload[:projection_class]).to be < Acta::Projection
  end

  it "instruments acta.reactor_enqueued for async reactors" do
    Class.new(Acta::Reactor) do
      on TestEvent do |_event|
        nil
      end
    end

    events = subscribe("acta.reactor_enqueued") do
      Acta.emit(event_class.new(thing: "x"))
    end

    expect(events.size).to eq(1)
    expect(events.first.payload[:reactor_class]).to be < Acta::Reactor
  end

  it "instruments acta.reactor_invoked for sync reactors" do
    Class.new(Acta::Reactor) do
      sync!
      on TestEvent do |_event|
        nil
      end
    end

    events = subscribe("acta.reactor_invoked") do
      Acta.emit(event_class.new(thing: "x"))
    end

    expect(events.size).to eq(1)
    expect(events.first.payload[:sync]).to be(true)
  end
end
