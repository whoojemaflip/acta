# frozen_string_literal: true

require "rails_helper"

RSpec.describe Acta::Serializable, :active_record do
  before do
    unless ActiveRecord::Base.connection.table_exists?(:test_addresses)
      ActiveRecord::Base.connection.create_table(:test_addresses) do |t|
        t.string :street
        t.string :city
        t.string :postal_code
        t.timestamps
      end
    end
  end

  let(:address_class) do
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "test_addresses"
      include Acta::Serializable
    end
    stub_const("TestAddress", klass)
    klass
  end

  describe "#to_acta_hash" do
    it "returns the AR attributes hash by default" do
      addr = address_class.new(street: "123 Main", city: "Vancouver", postal_code: "V6B 1A1")

      hash = addr.to_acta_hash

      expect(hash).to include(
        "street" => "123 Main",
        "city" => "Vancouver",
        "postal_code" => "V6B 1A1"
      )
    end

    it "honours acta_serialize except: to exclude columns" do
      address_class.acta_serialize except: [ :created_at, :updated_at ]
      addr = address_class.new(street: "123 Main", city: "V")

      keys = addr.to_acta_hash.keys

      expect(keys).not_to include("created_at", "updated_at")
      expect(keys).to include("street", "city")
    end

    it "honours acta_serialize only: to restrict columns" do
      address_class.acta_serialize only: [ :street, :city ]
      addr = address_class.new(street: "1 Main", city: "V", postal_code: "V6B")

      expect(addr.to_acta_hash.keys).to contain_exactly("street", "city")
    end

    it "rejects passing both :only and :except" do
      expect {
        address_class.acta_serialize except: [ :x ], only: [ :y ]
      }.to raise_error(ArgumentError, /only one of/)
    end
  end

  describe ".from_acta_hash" do
    it "builds a new (unpersisted) AR instance" do
      addr = address_class.from_acta_hash(
        "street" => "1 Main",
        "city" => "V",
        "postal_code" => "V6B"
      )

      expect(addr).to be_a(address_class)
      expect(addr).to be_new_record
      expect(addr.street).to eq("1 Main")
      expect(addr.city).to eq("V")
    end

    it "filters unknown keys for schema-drift tolerance" do
      raw = { "street" => "1 Main", "retired_column" => "x" }

      expect { address_class.from_acta_hash(raw) }.not_to raise_error
      expect(address_class.from_acta_hash(raw).street).to eq("1 Main")
    end

    it "returns nil when given nil" do
      expect(address_class.from_acta_hash(nil)).to be_nil
    end

    it "accepts symbol or string keys" do
      from_sym = address_class.from_acta_hash(street: "S", city: "C")
      from_str = address_class.from_acta_hash("street" => "S", "city" => "C")

      expect(from_sym.street).to eq(from_str.street)
      expect(from_sym.city).to eq(from_str.city)
    end
  end

  describe "round-trip" do
    it "to_acta_hash → from_acta_hash preserves attribute values" do
      original = address_class.new(
        street: "1 Main",
        city: "Vancouver",
        postal_code: "V6B 1A1"
      )
      restored = address_class.from_acta_hash(original.to_acta_hash)

      expect(restored.street).to eq(original.street)
      expect(restored.city).to eq(original.city)
      expect(restored.postal_code).to eq(original.postal_code)
    end
  end
end
