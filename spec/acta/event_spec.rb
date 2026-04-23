# frozen_string_literal: true

require "spec_helper"

RSpec.describe Acta::Event do
  let(:event_class) do
    klass = Class.new(described_class) do
      attribute :book_id, :string
      attribute :new_name, :string
      validates :book_id, :new_name, presence: true
    end
    stub_const("BookRenamed", klass)
    klass
  end

  before { Acta::Current.reset }
  after { Acta::Current.reset }

  describe "envelope" do
    it "auto-generates a uuid" do
      event = event_class.new(book_id: "w1", new_name: "New")

      expect(event.uuid).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "accepts a provided uuid" do
      uuid = SecureRandom.uuid
      event = event_class.new(uuid:, book_id: "w1", new_name: "New")

      expect(event.uuid).to eq(uuid)
    end

    it "auto-sets occurred_at to around Time.current" do
      before = Time.current
      event = event_class.new(book_id: "w1", new_name: "New")
      after = Time.current

      expect(event.occurred_at).to be_between(before, after)
    end

    it "accepts a provided occurred_at" do
      occurred_at = Time.utc(2020, 1, 1)
      event = event_class.new(occurred_at:, book_id: "w1", new_name: "New")

      expect(event.occurred_at).to eq(occurred_at)
    end

    it "leaves recorded_at nil until persisted" do
      event = event_class.new(book_id: "w1", new_name: "New")

      expect(event.recorded_at).to be_nil
    end

    it "derives event_type from the class name" do
      event = event_class.new(book_id: "w1", new_name: "New")

      expect(event.event_type).to eq("BookRenamed")
    end

    it "defaults event_version to 1" do
      event = event_class.new(book_id: "w1", new_name: "New")

      expect(event.event_version).to eq(1)
    end
  end

  describe "actor threading" do
    it "pulls actor from Acta::Current when not provided explicitly" do
      actor = Acta::Actor.new(type: "user", id: "u_1")
      Acta::Current.actor = actor
      event = event_class.new(book_id: "w1", new_name: "New")

      expect(event.actor).to eq(actor)
    end

    it "accepts an explicit actor override" do
      actor = Acta::Actor.new(type: "system")
      event = event_class.new(actor:, book_id: "w1", new_name: "New")

      expect(event.actor).to eq(actor)
    end

    it "is nil when neither Current nor explicit is set" do
      event = event_class.new(book_id: "w1", new_name: "New")

      expect(event.actor).to be_nil
    end
  end

  describe "payload" do
    it "accepts user-declared attributes" do
      event = event_class.new(book_id: "w1", new_name: "Foo")

      expect(event.book_id).to eq("w1")
      expect(event.new_name).to eq("Foo")
    end

    it "#payload_hash returns only user attributes, not envelope" do
      event = event_class.new(book_id: "w1", new_name: "Foo")

      expect(event.payload_hash).to eq("book_id" => "w1", "new_name" => "Foo")
    end
  end

  describe "validation on initialize" do
    it "raises Acta::InvalidEvent when validations fail" do
      expect { event_class.new(book_id: "w1") }.to raise_error(Acta::InvalidEvent)
    end

    it "carries the invalid event on the exception" do
      event_class.new(book_id: "w1")
    rescue Acta::InvalidEvent => e
      expect(e.event).to be_a(event_class)
      expect(e.event.errors[:new_name]).to be_present
    end
  end

  describe ".event_type" do
    it "is the class name by default" do
      expect(event_class.event_type).to eq("BookRenamed")
    end
  end

  describe ".event_version" do
    it "defaults to 1" do
      expect(event_class.event_version).to eq(1)
    end

    it "can be overridden on subclasses" do
      klass = Class.new(described_class) do
        attribute :foo, :string

        def self.event_version = 2
      end
      stub_const("V2Event", klass)

      expect(klass.event_version).to eq(2)
    end
  end
end
