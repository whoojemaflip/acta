# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Acta::Event stream DSL" do
  describe "when a stream is declared" do
    let(:event_class) do
      klass = Class.new(Acta::Event) do
        stream :book, key: :book_id
        attribute :book_id, :string
        attribute :new_name, :string
        validates :book_id, :new_name, presence: true
      end
      stub_const("BookRenamed", klass)
      klass
    end

    it "exposes stream_type on the class" do
      expect(event_class.stream_type).to eq("book")
    end

    it "exposes stream_key_attribute on the class" do
      expect(event_class.stream_key_attribute).to eq(:book_id)
    end

    it "exposes stream_type on an instance" do
      event = event_class.new(book_id: "w_1", new_name: "Foo")

      expect(event.stream_type).to eq("book")
    end

    it "extracts stream_key from the declared attribute on an instance" do
      event = event_class.new(book_id: "w_1", new_name: "Foo")

      expect(event.stream_key).to eq("w_1")
    end

    it "accepts a string type and coerces to string" do
      klass = Class.new(Acta::Event) do
        stream "order", key: :order_id
        attribute :order_id, :string
        validates :order_id, presence: true
      end
      stub_const("OrderPlaced", klass)

      expect(klass.stream_type).to eq("order")
    end
  end

  describe "when no stream is declared" do
    let(:event_class) do
      klass = Class.new(Acta::Event) do
        attribute :thing, :string
        validates :thing, presence: true
      end
      stub_const("ThingHappened", klass)
      klass
    end

    it "has nil stream_type on the class" do
      expect(event_class.stream_type).to be_nil
    end

    it "has nil stream_key_attribute on the class" do
      expect(event_class.stream_key_attribute).to be_nil
    end

    it "has nil stream_type and stream_key on instances" do
      event = event_class.new(thing: "x")

      expect(event.stream_type).to be_nil
      expect(event.stream_key).to be_nil
    end
  end
end
