# frozen_string_literal: true

require "rails_helper"
require "acta/testing/dsl"

RSpec.describe "Acta::Testing::DSL#ensure_replay_deterministic", :active_record do
  include Acta::Testing::DSL

  let(:event_class) do
    klass = Class.new(Acta::Event) do
      attribute :book_id, :string
      attribute :name, :string
      validates :book_id, :name, presence: true
    end
    stub_const("BookAdded", klass)
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

  it "passes when the projection is deterministic" do
    state = []
    Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { state.clear }
      on BookAdded do |event|
        state << event.book_id
      end
    end

    Acta.emit(event_class.new(book_id: "w_1", name: "A"))
    Acta.emit(event_class.new(book_id: "w_2", name: "B"))

    expect {
      ensure_replay_deterministic { state.dup }
    }.not_to raise_error
  end

  it "fails when the projection uses non-deterministic input" do
    state = []
    Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { state.clear }
      on BookAdded do |event|
        # deliberately non-deterministic — different on each pass
        state << [ event.book_id, rand ]
      end
    end

    Acta.emit(event_class.new(book_id: "w_1", name: "A"))

    expect {
      ensure_replay_deterministic { state.dup }
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /not deterministic/)
  end
end
