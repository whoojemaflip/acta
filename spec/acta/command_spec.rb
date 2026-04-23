# frozen_string_literal: true

require "spec_helper"

RSpec.describe Acta::Command do
  let(:command_class) do
    klass = Class.new(described_class) do
      param :name, :string
      validates :name, presence: true

      def call
        "hello, #{name}"
      end
    end
    stub_const("SayHello", klass)
    klass
  end

  describe ".param" do
    it "declares an ActiveModel attribute" do
      expect(command_class.attribute_types).to include("name")
    end
  end

  describe ".call" do
    it "instantiates with params and runs the instance #call" do
      result = command_class.call(name: "World")

      expect(result).to eq("hello, World")
    end

    it "passes each param through to the instance" do
      klass = Class.new(described_class) do
        param :a, :integer
        param :b, :integer
        validates :a, :b, presence: true

        def call
          a + b
        end
      end
      stub_const("Adder", klass)

      expect(klass.call(a: 2, b: 3)).to eq(5)
    end
  end

  describe "validation on initialize" do
    it "raises InvalidCommand when validation fails" do
      expect { command_class.call }.to raise_error(Acta::InvalidCommand)
    end

    it "carries the invalid command on the exception" do
      command_class.call
    rescue Acta::InvalidCommand => e
      expect(e.command).to be_a(command_class)
      expect(e.command.errors[:name]).to be_present
    end

    it "InvalidCommand is a CommandError which is an Acta::Error" do
      expect(Acta::InvalidCommand).to be < Acta::CommandError
      expect(Acta::CommandError).to be < Acta::Error
    end
  end
end
