# frozen_string_literal: true

require "rails_helper"

RSpec.describe Acta::Record, :active_record do
  it "persists and reads a basic row" do
    record = described_class.create!(
      uuid: SecureRandom.uuid,
      event_type: "TestEvent",
      event_version: 1,
      payload: { "foo" => "bar" },
      occurred_at: Time.current,
      recorded_at: Time.current
    )

    reloaded = described_class.find(record.id)

    expect(reloaded.payload).to eq("foo" => "bar")
    expect(reloaded.event_type).to eq("TestEvent")
  end

  it "round-trips JSON payload with nested values" do
    payload = { "book_id" => "w1", "tags" => [ "red", "bc" ], "meta" => { "rating" => 5 } }

    record = described_class.create!(
      uuid: SecureRandom.uuid,
      event_type: "TestEvent",
      payload:,
      occurred_at: Time.current,
      recorded_at: Time.current
    )

    expect(described_class.find(record.id).payload).to eq(payload)
  end

  it "round-trips JSON metadata including nil" do
    record = described_class.create!(
      uuid: SecureRandom.uuid,
      event_type: "TestEvent",
      payload: {},
      metadata: nil,
      occurred_at: Time.current,
      recorded_at: Time.current
    )

    expect(described_class.find(record.id).metadata).to be_nil
  end
end
