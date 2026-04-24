# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta::Command with `emits`", :active_record do
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

  describe "inheriting stream info" do
    let(:command_class) do
      klass = Class.new(Acta::Command) do
        emits BookRenamed

        param :book_id, :string
        param :new_name, :string
        validates :book_id, :new_name, presence: true

        def call
          emit BookRenamed.new(book_id:, new_name:)
        end
      end
      stub_const("RenameBookFromEmits", klass)
      klass
    end

    it "derives stream_type from the emitted event class" do
      expect(command_class.stream_type).to eq("book")
    end

    it "derives stream_key_attribute from the emitted event class" do
      expect(command_class.stream_key_attribute).to eq(:book_id)
    end

    it "exposes stream_type and stream_key on instances" do
      cmd = command_class.new(book_id: "w_1", new_name: "Foo")

      expect(cmd.stream_type).to eq("book")
      expect(cmd.stream_key).to eq("w_1")
    end

    it "runs commands normally with the inherited stream" do
      expect {
        command_class.call(book_id: "w_1", new_name: "Foo")
      }.not_to raise_error
      expect(Acta.events.count).to eq(1)
    end
  end

  describe "combined with on_concurrent_write :raise" do
    let(:command_class) do
      klass = Class.new(Acta::Command) do
        emits BookRenamed
        on_concurrent_write :raise

        param :book_id, :string
        param :new_name, :string
        validates :book_id, :new_name, presence: true

        def call
          emit BookRenamed.new(book_id:, new_name:)
        end
      end
      stub_const("RenameBookFromEmitsStrict", klass)
      klass
    end

    it "captures the inferred stream's sequence and detects concurrent writes" do
      Acta.emit(event_class.new(book_id: "w_1", new_name: "First"))

      cmd = command_class.new(book_id: "w_1", new_name: "Second")

      Acta.emit(event_class.new(book_id: "w_1", new_name: "Interloper"))

      expect { cmd.call }.to raise_error(Acta::ConcurrencyConflict)
    end
  end

  describe "explicit `stream` takes precedence over `emits`" do
    let(:other_event_class) do
      klass = Class.new(Acta::Event) do
        stream :book, key: :book_id
        attribute :book_id, :string
        validates :book_id, presence: true
      end
      stub_const("BookAdded", klass)
      klass
    end

    it "uses the explicit stream declaration and ignores the inferred one" do
      other_event_class

      command_class = Class.new(Acta::Command) do
        stream :publisher, key: :publisher_id
        emits BookAdded

        param :publisher_id, :string
      end

      expect(command_class.stream_type).to eq("publisher")
      expect(command_class.stream_key_attribute).to eq(:publisher_id)
    end
  end

  describe "validation" do
    it "raises ArgumentError when emits receives a class without stream hooks" do
      expect {
        Class.new(Acta::Command) { emits String }
      }.to raise_error(ArgumentError, /stream_type and stream_key_attribute/)
    end
  end
end
