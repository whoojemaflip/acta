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

    it "raises ArgumentError when emits is called with no arguments" do
      expect {
        Class.new(Acta::Command) { emits }
      }.to raise_error(ArgumentError, /requires at least one event class/)
    end

    it "raises ArgumentError when any of multiple emits arguments lacks stream hooks" do
      expect {
        Class.new(Acta::Command) { emits BookRenamed, String }
      }.to raise_error(ArgumentError, /stream_type and stream_key_attribute.*String/)
    end
  end

  describe "with multiple event classes (variadic)" do
    let(:other_event_class) do
      klass = Class.new(Acta::Event) do
        stream :book, key: :book_id
        attribute :book_id, :string
        attribute :reason, :string
        validates :book_id, :reason, presence: true
      end
      stub_const("BookArchived", klass)
      klass
    end

    let(:command_class) do
      other_event_class

      klass = Class.new(Acta::Command) do
        emits BookRenamed, BookArchived

        param :book_id, :string
        param :new_name, :string
        param :archive, :boolean, default: false
        param :reason, :string

        def call
          if archive
            emit BookArchived.new(book_id:, reason:)
          else
            emit BookRenamed.new(book_id:, new_name:)
          end
        end
      end
      stub_const("UpdateBook", klass)
      klass
    end

    it "exposes all listed events via emitted_event_classes" do
      expect(command_class.emitted_event_classes).to eq([ BookRenamed, BookArchived ])
    end

    it "still inherits stream_type from the first event class" do
      expect(command_class.stream_type).to eq("book")
    end

    it "still inherits stream_key_attribute from the first event class" do
      expect(command_class.stream_key_attribute).to eq(:book_id)
    end

    it "emitted_event_class returns the first event class for backward compat" do
      expect(command_class.emitted_event_class).to eq(BookRenamed)
    end

    it "lets the command emit any of the listed events at runtime" do
      command_class.call(book_id: "w_1", new_name: "Foo")
      command_class.call(book_id: "w_1", archive: true, reason: "out of print")

      events = Acta.events.all
      expect(events.map(&:class)).to eq([ BookRenamed, BookArchived ])
    end

    it "does not enforce that only listed events are emitted (emits is a hint, not a contract)" do
      Class.new(Acta::Event) do
        attribute :book_id, :string
        validates :book_id, presence: true
      end.tap { |c| stub_const("BookSurprise", c) }

      surprise_command = Class.new(Acta::Command) do
        emits BookRenamed
        param :book_id, :string

        def call
          emit BookSurprise.new(book_id:)
        end
      end
      stub_const("SurpriseCommand", surprise_command)

      expect { surprise_command.call(book_id: "w_1") }.not_to raise_error
      expect(Acta.events.last).to be_a(BookSurprise)
    end
  end
end
