# frozen_string_literal: true

require "rails_helper"

RSpec.describe Acta::Command, :active_record do
  let(:event_class) do
    klass = Class.new(Acta::Event) do
      stream :order, key: :order_id
      attribute :order_id, :string
      attribute :customer_id, :string
      validates :order_id, :customer_id, presence: true
    end
    stub_const("OrderCreated", klass)
    klass
  end

  let(:cascade_event_class) do
    klass = Class.new(Acta::Event) do
      stream :order, key: :order_id
      attribute :order_id, :string
      attribute :line_id, :string
      validates :order_id, :line_id, presence: true
    end
    stub_const("OrderLineAdded", klass)
    klass
  end

  let(:command_class) do
    event_class

    klass = Class.new(described_class) do
      param :customer_id, :string
      validates :customer_id, presence: true

      def call
        emit OrderCreated.new(order_id: "o_#{customer_id}", customer_id:)
      end
    end
    stub_const("CreateOrder", klass)
    klass
  end

  before do
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta::Current.actor = Acta::Actor.new(type: "system")
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
  end

  describe ".param" do
    it "declares an ActiveModel attribute" do
      expect(command_class.attribute_types).to include("customer_id")
    end
  end

  describe ".call" do
    it "returns the command instance" do
      result = command_class.call(customer_id: "c_1")

      expect(result).to be_a(command_class)
    end

    it "runs the instance #call before returning" do
      result = command_class.call(customer_id: "c_1")

      expect(Acta.events.count).to eq(1)
      expect(result.emitted_events).to all(be_a(OrderCreated))
    end

    it "passes each param through to the instance" do
      klass = Class.new(described_class) do
        param :a, :integer
        param :b, :integer
        validates :a, :b, presence: true

        attr_reader :sum

        def call
          @sum = a + b
        end
      end
      stub_const("Adder", klass)

      cmd = klass.call(a: 2, b: 3)
      expect(cmd.sum).to eq(5)
    end

    it "ignores whatever the user's #call method returns" do
      klass = Class.new(described_class) do
        def call
          "trailing-string-ignored"
        end
      end
      stub_const("NoisyCommand", klass)

      expect(klass.call).to be_a(klass)
    end
  end

  describe "#emitted_events" do
    it "is empty before #call runs" do
      cmd = command_class.new(customer_id: "c_1")
      expect(cmd.emitted_events).to eq([])
    end

    it "captures every event emitted during #call, in order" do
      event_class
      cascade_event_class

      klass = Class.new(described_class) do
        param :order_id, :string
        validates :order_id, presence: true

        def call
          emit OrderCreated.new(order_id:, customer_id: "c_x")
          emit OrderLineAdded.new(order_id:, line_id: "l_1")
          emit OrderLineAdded.new(order_id:, line_id: "l_2")
        end
      end
      stub_const("CreateOrderWithLines", klass)

      cmd = klass.call(order_id: "o_1")

      expect(cmd.emitted_events.map(&:class)).to eq([
        OrderCreated, OrderLineAdded, OrderLineAdded
      ])
      expect(cmd.emitted_events.map(&:order_id)).to all(eq("o_1"))
    end

    it "is empty when the command is idempotent and emits nothing" do
      klass = Class.new(described_class) do
        def call
          # idempotent: nothing to do
        end
      end
      stub_const("NoopCommand", klass)

      cmd = klass.call
      expect(cmd.emitted_events).to eq([])
    end

    it "does not capture events emitted by nested commands invoked from #call" do
      event_class

      inner = Class.new(described_class) do
        param :order_id, :string

        def call
          emit OrderCreated.new(order_id:, customer_id: "c_inner")
        end
      end
      stub_const("InnerCommand", inner)

      outer = Class.new(described_class) do
        param :order_id, :string

        def call
          InnerCommand.call(order_id: "#{order_id}-nested")
        end
      end
      stub_const("OuterCommand", outer)

      cmd = outer.call(order_id: "o_1")

      expect(cmd.emitted_events).to eq([])
      expect(Acta.events.count).to eq(1)
    end
  end

  describe "#emit" do
    it "returns the event so callers can chain on it inside #call" do
      cmd = command_class.new(customer_id: "c_1")
      event = cmd.emit(OrderCreated.new(order_id: "o_1", customer_id: "c_1"))

      expect(event).to be_a(OrderCreated)
      expect(event.order_id).to eq("o_1")
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
      expect(e.command.errors[:customer_id]).to be_present
    end

    it "InvalidCommand is a CommandError which is an Acta::Error" do
      expect(Acta::InvalidCommand).to be < Acta::CommandError
      expect(Acta::CommandError).to be < Acta::Error
    end
  end
end
