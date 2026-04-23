# frozen_string_literal: true

require "rails_helper"
require "support/postgres_adapter"

RSpec.describe Acta::Adapters::Postgres do
  before(:all) do
    @pg_available = PostgresAdapterSupport.available?
    skip "Postgres not available (set ACTA_PG_* env vars to configure)" unless @pg_available
  end

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

  let(:actor) { Acta::Actor.new(type: "user", id: "u_1") }

  around do |example|
    PostgresAdapterSupport.with_connection do
      Acta::Current.actor = actor
      example.run
      Acta::Current.reset
    end
  end

  it "auto-detects the Postgres adapter" do
    expect(Acta.adapter).to be_a(Acta::Adapters::Postgres)
  end

  it "creates the schema with jsonb and uuid columns" do
    columns = ActiveRecord::Base.connection.columns(:events).index_by(&:name)

    expect(columns["payload"].sql_type).to eq("jsonb")
    expect(columns["metadata"].sql_type).to eq("jsonb")
    expect(columns["uuid"].sql_type).to eq("uuid")
  end

  it "round-trips an event through emit/events" do
    event = Acta.emit(event_class.new(book_id: "w_1", new_name: "Foo"))

    reloaded = Acta.events.last
    expect(reloaded).to be_a(event_class)
    expect(reloaded.book_id).to eq("w_1")
    expect(reloaded.new_name).to eq("Foo")
    expect(reloaded.uuid).to eq(event.uuid)
  end

  it "assigns per-stream sequences" do
    e1 = Acta.emit(event_class.new(book_id: "w_1", new_name: "First"))
    e2 = Acta.emit(event_class.new(book_id: "w_1", new_name: "Second"))

    expect(Acta::Record.find_by(uuid: e1.uuid).stream_sequence).to eq(1)
    expect(Acta::Record.find_by(uuid: e2.uuid).stream_sequence).to eq(2)
  end

  it "raises ConcurrencyConflict on duplicate stream sequence" do
    Acta.emit(event_class.new(book_id: "w_1", new_name: "First"))

    adapter = Acta.adapter
    allow(adapter).to receive(:compute_next_sequence).and_return(1)

    expect {
      Acta.emit(event_class.new(book_id: "w_1", new_name: "Conflict"))
    }.to raise_error(Acta::ConcurrencyConflict)
  end

  it "enforces uuid uniqueness" do
    event = Acta.emit(event_class.new(book_id: "w_1", new_name: "First"))

    expect {
      Acta.emit(event_class.new(uuid: event.uuid, book_id: "w_2", new_name: "Dup"))
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe "genuine concurrent writers" do
    it "serialises writes to the same stream via advisory locks — no duplicates, no missing sequences" do
      concurrency = 10
      threads = []
      errors = []

      mutex = Mutex.new
      concurrency.times.map do |i|
        threads << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Acta::Current.actor = Acta::Actor.new(type: "system", id: "t#{i}")
            Acta.emit(event_class.new(book_id: "shared", new_name: "writer-#{i}"))
          rescue StandardError => e
            mutex.synchronize { errors << e }
          end
        end
      end

      threads.each(&:join)

      expect(errors).to be_empty
      sequences = Acta::Record
                    .where(stream_type: "book", stream_key: "shared")
                    .order(:stream_sequence)
                    .pluck(:stream_sequence)

      expect(sequences).to eq((1..concurrency).to_a)
    end
  end
end
