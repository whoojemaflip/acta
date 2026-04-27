# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta::Command with `emits`", :active_record do
  let(:renamed_class) do
    klass = Class.new(Acta::Event) do
      stream :book, key: :book_id
      attribute :book_id, :string
      attribute :new_name, :string
      validates :book_id, :new_name, presence: true
    end
    stub_const("BookRenamed", klass)
    klass
  end

  let(:archived_class) do
    klass = Class.new(Acta::Event) do
      stream :book, key: :book_id
      attribute :book_id, :string
      attribute :reason, :string
      validates :book_id, :reason, presence: true
    end
    stub_const("BookArchived", klass)
    klass
  end

  before do
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta::Current.actor = Acta::Actor.new(type: "system")
    renamed_class
    archived_class
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
  end

  describe "single event class" do
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
      stub_const("RenameBook", klass)
      klass
    end

    it "exposes the listed event class via emitted_event_class" do
      expect(command_class.emitted_event_class).to eq(BookRenamed)
    end

    it "exposes the list via emitted_event_classes" do
      expect(command_class.emitted_event_classes).to eq([ BookRenamed ])
    end

    it "runs the command and emits the event normally" do
      expect {
        command_class.call(book_id: "w_1", new_name: "Foo")
      }.not_to raise_error
      expect(Acta.events.count).to eq(1)
    end
  end

  describe "variadic — multiple event classes" do
    let(:command_class) do
      klass = Class.new(Acta::Command) do
        emits BookRenamed, BookArchived

        param :book_id, :string
        param :new_name, :string
        param :reason, :string
        param :archive, :boolean, default: false

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

    it "exposes the first as the primary via emitted_event_class" do
      expect(command_class.emitted_event_class).to eq(BookRenamed)
    end

    it "runs the command emitting whichever event matches the conditional" do
      command_class.call(book_id: "w_1", new_name: "Foo")
      command_class.call(book_id: "w_2", reason: "stale", archive: true)

      types = Acta.events.map(&:event_type)
      expect(types).to contain_exactly("BookRenamed", "BookArchived")
    end
  end

  describe "validation" do
    it "raises ArgumentError when emits is called with no arguments" do
      expect {
        Class.new(Acta::Command) { emits }
      }.to raise_error(ArgumentError, /requires at least one event class/)
    end

    it "raises ArgumentError when emits receives a class without stream hooks" do
      expect {
        Class.new(Acta::Command) { emits String }
      }.to raise_error(ArgumentError, /stream_type and stream_key_attribute/)
    end

    it "raises ArgumentError when any of multiple emits arguments lacks stream hooks" do
      expect {
        Class.new(Acta::Command) { emits BookRenamed, String }
      }.to raise_error(ArgumentError, /stream_type and stream_key_attribute.*String/)
    end
  end
end
