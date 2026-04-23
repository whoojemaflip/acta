# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta::Command with streams", :active_record do
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

  let(:command_class) do
    klass = Class.new(Acta::Command) do
      stream :book, key: :book_id
      expected_sequence :loaded

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

  before do
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta::Current.actor = Acta::Actor.new(type: "system")
    event_class
    command_class
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
  end

  describe "stream declaration" do
    it "exposes stream_type and stream_key_attribute on the class" do
      expect(command_class.stream_type).to eq("book")
      expect(command_class.stream_key_attribute).to eq(:book_id)
    end

    it "exposes stream_type and stream_key on instances" do
      cmd = command_class.new(book_id: "w_1", new_name: "Foo")

      expect(cmd.stream_type).to eq("book")
      expect(cmd.stream_key).to eq("w_1")
    end
  end

  describe "expected_sequence :loaded" do
    it "emits successfully when no one else is writing to the stream" do
      expect {
        command_class.call(book_id: "w_1", new_name: "Foo")
      }.not_to raise_error

      expect(Acta.events.count).to eq(1)
    end

    it "emits successfully when the stream state matches what was captured" do
      Acta.emit(event_class.new(book_id: "w_1", new_name: "First"))

      expect {
        command_class.call(book_id: "w_1", new_name: "Second")
      }.not_to raise_error
    end

    it "raises ConcurrencyConflict when another writer advances the stream after instantiation" do
      Acta.emit(event_class.new(book_id: "w_1", new_name: "First"))

      # Capture expected sequence at instantiation (sequence 1)
      cmd = command_class.new(book_id: "w_1", new_name: "Second")

      # Another writer advances the stream
      Acta.emit(event_class.new(book_id: "w_1", new_name: "Interloper"))

      expect { cmd.call }.to raise_error(Acta::ConcurrencyConflict)
    end

    it "raises ConfigurationError if stream_key is missing at instantiation" do
      klass = Class.new(Acta::Command) do
        stream :book, key: :book_id
        expected_sequence :loaded

        param :book_id, :string
        # no validation — book_id can be nil
      end
      stub_const("NoKeyCommand", klass)

      expect {
        klass.new(book_id: nil)
      }.to raise_error(Acta::ConfigurationError, /stream declaration/)
    end

    it "raises ArgumentError for unsupported modes" do
      expect {
        Class.new(Acta::Command) { expected_sequence :something_else }
      }.to raise_error(ArgumentError, /:loaded/)
    end
  end

  describe "commands without expected_sequence" do
    let(:plain_command_class) do
      klass = Class.new(Acta::Command) do
        param :book_id, :string
        param :new_name, :string
        validates :book_id, :new_name, presence: true

        def call
          emit BookRenamed.new(book_id:, new_name:)
        end
      end
      stub_const("PlainRenameBook", klass)
      klass
    end

    it "emits without concurrency checking" do
      # Advance stream via direct emit
      Acta.emit(event_class.new(book_id: "w_1", new_name: "First"))
      Acta.emit(event_class.new(book_id: "w_1", new_name: "Second"))

      # Plain command doesn't capture expected sequence
      expect {
        plain_command_class.call(book_id: "w_1", new_name: "Third")
      }.not_to raise_error
    end
  end
end
