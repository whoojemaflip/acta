# frozen_string_literal: true

require "spec_helper"

RSpec.describe Acta::Actor do
  describe "initialization" do
    it "accepts type, id, source, and metadata" do
      actor = described_class.new(type: "user", id: "u_1", source: "web", metadata: { ip: "127.0.0.1" })

      expect(actor.type).to eq("user")
      expect(actor.id).to eq("u_1")
      expect(actor.source).to eq("web")
      expect(actor.metadata).to eq({ ip: "127.0.0.1" })
    end

    it "requires a type" do
      expect { described_class.new(id: "u_1") }.to raise_error(ArgumentError, /type/)
    end

    it "rejects nil or empty type" do
      expect { described_class.new(type: nil) }.to raise_error(ArgumentError, /type/)
      expect { described_class.new(type: "") }.to raise_error(ArgumentError, /type/)
    end

    it "allows id, source, and metadata to be omitted" do
      actor = described_class.new(type: "system")

      expect(actor.id).to be_nil
      expect(actor.source).to be_nil
      expect(actor.metadata).to eq({})
    end

    it "accepts any non-empty string type (apps define their own vocabulary)" do
      expect { described_class.new(type: "user") }.not_to raise_error
      expect { described_class.new(type: "service_account") }.not_to raise_error
      expect { described_class.new(type: "worker") }.not_to raise_error
      expect { described_class.new(type: "anything") }.not_to raise_error
    end

    it "coerces symbol types to strings" do
      actor = described_class.new(type: :worker)

      expect(actor.type).to eq("worker")
    end
  end

  describe "equality" do
    it "is equal when type, id, source, and metadata match" do
      a = described_class.new(type: "user", id: "1", source: "app")
      b = described_class.new(type: "user", id: "1", source: "app")

      expect(a).to eq(b)
    end

    it "is not equal when any field differs" do
      a = described_class.new(type: "user", id: "1")
      b = described_class.new(type: "user", id: "2")

      expect(a).not_to eq(b)
    end
  end

  describe "serialization" do
    it "round-trips through a hash" do
      original = described_class.new(type: "worker", id: "job_42", source: "background", metadata: { host: "app-1" })
      restored = described_class.from_h(original.to_h)

      expect(restored).to eq(original)
    end

    it "to_h returns a hash with the four fields" do
      actor = described_class.new(type: "user", id: "u_1", source: "mobile", metadata: { v: 1 })

      expect(actor.to_h).to eq(type: "user", id: "u_1", source: "mobile", metadata: { v: 1 })
    end
  end
end
