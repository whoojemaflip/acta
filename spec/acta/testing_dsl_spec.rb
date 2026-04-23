# frozen_string_literal: true

require "rails_helper"
require "acta/testing/dsl"

RSpec.describe Acta::Testing::DSL, :active_record do
  include described_class

  let(:added_class) do
    klass = Class.new(Acta::Event) do
      stream :book, key: :book_id
      attribute :book_id, :string
      attribute :name, :string
      validates :book_id, :name, presence: true
    end
    stub_const("BookAdded", klass)
    klass
  end

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

  let(:command_class) do
    klass = Class.new(Acta::Command) do
      stream :book, key: :book_id

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
    added_class
    renamed_class
    command_class
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
  end

  it "given/when/then covers a full command spec" do
    given_events do
      Acta.emit(added_class.new(book_id: "w_1", name: "Foo"))
    end

    when_command command_class.new(book_id: "w_1", new_name: "Foo Reserve")

    then_emitted renamed_class, new_name: "Foo Reserve"
    then_emitted_nothing_else
  end

  it "when_event allows direct emission inside the block" do
    when_event do
      Acta.emit(added_class.new(book_id: "w_1", name: "Foo"))
    end

    then_emitted added_class, book_id: "w_1"
  end

  it "then_emitted_nothing_else fails when unmatched events remain" do
    when_event do
      Acta.emit(added_class.new(book_id: "w_1", name: "Foo"))
      Acta.emit(renamed_class.new(book_id: "w_1", new_name: "Bar"))
    end
    then_emitted added_class, book_id: "w_1"

    expect { then_emitted_nothing_else }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it "then_emitted fails when no matching event is present" do
    when_event do
      Acta.emit(added_class.new(book_id: "w_1", name: "Foo"))
    end

    expect { then_emitted renamed_class }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it "baseline excludes events from given_events" do
    given_events do
      Acta.emit(added_class.new(book_id: "w_1", name: "Existing"))
    end

    when_event do
      Acta.emit(renamed_class.new(book_id: "w_1", new_name: "New"))
    end

    then_emitted renamed_class
    then_emitted_nothing_else
  end
end
