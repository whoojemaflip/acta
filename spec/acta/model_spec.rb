# frozen_string_literal: true

require "spec_helper"

RSpec.describe Acta::Model do
  let(:model_class) do
    klass = Class.new(described_class) do
      attribute :name, :string
      attribute :quantity, :integer
      attribute :tags, :string, default: "none"
      validates :name, presence: true
    end
    stub_const("TestModel", klass)
    klass
  end

  describe "initialization" do
    it "accepts attributes as keyword arguments" do
      instance = model_class.new(name: "widget", quantity: 3)

      expect(instance.name).to eq("widget")
      expect(instance.quantity).to eq(3)
    end

    it "coerces values via ActiveModel::Type" do
      instance = model_class.new(name: "widget", quantity: "3")

      expect(instance.quantity).to eq(3)
    end

    it "applies declared defaults for unspecified attributes" do
      instance = model_class.new(name: "widget")

      expect(instance.tags).to eq("none")
    end
  end

  describe "validations" do
    it "exposes ActiveModel validations" do
      instance = model_class.new

      expect(instance).not_to be_valid
      expect(instance.errors[:name]).to be_present
    end
  end

  describe "#to_acta_hash" do
    it "returns a hash of declared attributes in their serialized form" do
      instance = model_class.new(name: "widget", quantity: 3)

      expect(instance.to_acta_hash).to eq("name" => "widget", "quantity" => 3, "tags" => "none")
    end

    it "does not include attributes not declared on the class" do
      instance = model_class.new(name: "widget")

      expect(instance.to_acta_hash.keys).to contain_exactly("name", "quantity", "tags")
    end
  end

  describe ".from_acta_hash" do
    it "builds an instance from a hash with string keys" do
      instance = model_class.from_acta_hash("name" => "widget", "quantity" => 3)

      expect(instance.name).to eq("widget")
      expect(instance.quantity).to eq(3)
    end

    it "tolerates symbol keys" do
      instance = model_class.from_acta_hash(name: "widget", quantity: 3)

      expect(instance.name).to eq("widget")
    end

    it "filters unknown keys for schema-drift tolerance" do
      raw = { "name" => "widget", "quantity" => 3, "retired_field" => "x" }

      expect { model_class.from_acta_hash(raw) }.not_to raise_error
      instance = model_class.from_acta_hash(raw)
      expect(instance.name).to eq("widget")
    end
  end

  describe "round-trip" do
    it "to_acta_hash → from_acta_hash preserves all declared attributes" do
      original = model_class.new(name: "widget", quantity: 7)
      restored = model_class.from_acta_hash(original.to_acta_hash)

      expect(restored.to_acta_hash).to eq(original.to_acta_hash)
    end
  end
end
