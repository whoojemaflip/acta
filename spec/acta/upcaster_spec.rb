# frozen_string_literal: true

require "rails_helper"

RSpec.describe Acta::Upcaster, :active_record do
  before do
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta.reset_upcasters!
    Acta::Current.actor = Acta::Actor.new(type: "system", id: "rspec", source: "test")
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta.reset_upcasters!
  end

  describe "DSL validation" do
    it "rejects non-integer from/to" do
      klass = Module.new do
        include Acta::Upcaster
      end

      expect { klass.upcasts("Foo", from: "1", to: 2) { |e, _| e } }
        .to raise_error(Acta::UpcasterRegistryError, /from must be an Integer/)
      expect { klass.upcasts("Foo", from: 1, to: 2.0) { |e, _| e } }
        .to raise_error(Acta::UpcasterRegistryError, /to must be an Integer/)
    end

    it "rejects to < from" do
      klass = Module.new { include Acta::Upcaster }
      expect { klass.upcasts("Foo", from: 2, to: 1) { |e, _| e } }
        .to raise_error(Acta::UpcasterRegistryError, /to .* must be >= from/)
    end

    it "rejects a registration without a block" do
      klass = Module.new { include Acta::Upcaster }
      expect { klass.upcasts("Foo", from: 1, to: 2) }
        .to raise_error(Acta::UpcasterRegistryError, /block required/)
    end

    it "raises on conflicting (event_type, from) registrations across classes" do
      a = Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 2 do |e, _|
          e.upcast_to(schema_version: 2)
        end
      end
      b = Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 2 do |e, _|
          e.upcast_to(schema_version: 2)
        end
      end
      stub_const("UpcasterA", a)
      stub_const("UpcasterB", b)

      Acta.register_upcaster(UpcasterA)
      expect { Acta.register_upcaster(UpcasterB) }
        .to raise_error(Acta::UpcasterRegistryError, /Conflicting upcasters/)
    end

    it "is idempotent — re-registering the same class is a no-op" do
      klass = Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 2 do |e, _|
          e.upcast_to(schema_version: 2)
        end
      end
      stub_const("OneAndDone", klass)

      Acta.register_upcaster(OneAndDone)
      expect { Acta.register_upcaster(OneAndDone) }.not_to raise_error
    end
  end

  describe "pipeline" do
    let(:context) { Acta::Upcaster::Context.new }
    let(:record) do
      Acta::Record.new(
        uuid: SecureRandom.uuid,
        event_type: "Foo",
        event_version: 1,
        payload: { "value" => "v1" },
        actor_type: "system",
        actor_id: "rspec",
        source: "test",
        occurred_at: Time.current,
        recorded_at: Time.current
      )
    end

    it "is identity when no upcasters are registered" do
      results = described_class.upcast(record, context)
      expect(results.length).to eq(1)
      expect(results.first.event_type).to eq("Foo")
      expect(results.first.event_version).to eq(1)
      expect(results.first.payload).to eq({ "value" => "v1" })
    end

    it "applies a single-step transform" do
      Acta.register_upcaster(Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 2 do |e, _|
          e.upcast_to(payload: e.payload.merge("added" => true), schema_version: 2)
        end
      end)

      results = described_class.upcast(record, context)

      expect(results.length).to eq(1)
      expect(results.first.event_version).to eq(2)
      expect(results.first.payload).to eq({ "value" => "v1", "added" => true })
    end

    it "chains across N versions" do
      Acta.register_upcaster(Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 2 do |e, _|
          e.upcast_to(payload: e.payload.merge("v2" => true), schema_version: 2)
        end
        upcasts "Foo", from: 2, to: 3 do |e, _|
          e.upcast_to(payload: e.payload.merge("v3" => true), schema_version: 3)
        end
      end)

      results = described_class.upcast(record, context)
      expect(results.first.event_version).to eq(3)
      expect(results.first.payload).to eq({ "value" => "v1", "v2" => true, "v3" => true })
    end

    it "supports type-changing transforms" do
      Acta.register_upcaster(Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 2 do |e, _|
          e.upcast_to(type: "Bar", payload: e.payload, schema_version: 2)
        end
      end)

      results = described_class.upcast(record, context)
      expect(results.first.event_type).to eq("Bar")
    end

    it "fans out 1-to-many, then chains each branch independently" do
      Acta.register_upcaster(Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 2 do |e, _|
          [
            e.upcast_to(type: "Left",  payload: { "side" => "L" }, schema_version: 2),
            e.upcast_to(type: "Right", payload: { "side" => "R" }, schema_version: 2)
          ]
        end
        upcasts "Left", from: 2, to: 3 do |e, _|
          e.upcast_to(payload: e.payload.merge("chained" => true), schema_version: 3)
        end
      end)

      results = described_class.upcast(record, context)
      expect(results.map(&:event_type)).to eq([ "Left", "Right" ])
      expect(results.map(&:event_version)).to eq([ 3, 2 ])
      expect(results[0].payload).to eq({ "side" => "L", "chained" => true })
      expect(results[1].payload).to eq({ "side" => "R" })
    end

    it "drops the record when an upcaster returns nil" do
      Acta.register_upcaster(Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 2 do |_e, _ctx|
          nil
        end
      end)

      expect(described_class.upcast(record, context)).to eq([])
    end

    it "drops the record when an upcaster returns an empty array" do
      Acta.register_upcaster(Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 2 do |_e, _ctx|
          []
        end
      end)

      expect(described_class.upcast(record, context)).to eq([])
    end

    it "halts with ReplayHaltedByUpcaster when context.fail_replay! is called" do
      Acta.register_upcaster(Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 2 do |_e, ctx|
          ctx.fail_replay!("simulated failure")
        end
      end)

      expect { described_class.upcast(record, context) }
        .to raise_error(Acta::ReplayHaltedByUpcaster, /simulated failure/)
    end

    it "raises FutureSchemaVersion when stored version exceeds known max" do
      record.event_version = 5
      Acta.register_upcaster(Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 2 do |e, _|
          e.upcast_to(schema_version: 2)
        end
      end)

      expect { described_class.upcast(record, context) }
        .to raise_error(Acta::FutureSchemaVersion, /only knows up to v2/)
    end

    it "treats NO_OP as a terminal pass-through at the current version" do
      Acta.register_upcaster(Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 1, &Acta::Upcaster::NO_OP
      end)

      results = described_class.upcast(record, context)
      expect(results.length).to eq(1)
      expect(results.first.event_version).to eq(1)
    end

    it "rejects non-View return values" do
      Acta.register_upcaster(Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 2 do |_e, _ctx|
          "not a view"
        end
      end)

      expect { described_class.upcast(record, context) }
        .to raise_error(Acta::UpcasterRegistryError, /expected an Acta::Upcaster::View/)
    end

    it "carries context state across records in a single replay pass" do
      seen = []
      Acta.register_upcaster(Module.new do
        include Acta::Upcaster
        upcasts "Foo", from: 1, to: 2 do |e, ctx|
          ctx[:seen][e.payload["value"]] = true
          e.upcast_to(payload: e.payload.merge("prior" => ctx[:seen].keys), schema_version: 2)
        end
      end)

      record1 = record.dup
      record1.payload = { "value" => "first" }
      record2 = Acta::Record.new(
        uuid: SecureRandom.uuid, event_type: "Foo", event_version: 1,
        payload: { "value" => "second" }, actor_type: "system", actor_id: "rspec",
        source: "test", occurred_at: Time.current, recorded_at: Time.current
      )

      seen << described_class.upcast(record1, context).first.payload
      seen << described_class.upcast(record2, context).first.payload

      expect(seen[0]["prior"]).to eq([ "first" ])
      expect(seen[1]["prior"]).to eq([ "first", "second" ])
    end
  end
end
