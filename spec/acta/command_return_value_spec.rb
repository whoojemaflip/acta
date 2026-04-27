# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta::Command.call return value", :active_record do
  let(:created_class) do
    klass = Class.new(Acta::Event) do
      stream :order, key: :order_id
      attribute :order_id, :string
      attribute :customer_id, :string
      validates :order_id, :customer_id, presence: true
    end
    stub_const("OrderCreated", klass)
    klass
  end

  let(:cascade_class) do
    klass = Class.new(Acta::Event) do
      stream :order, key: :order_id
      attribute :order_id, :string
      attribute :line_id, :string
      validates :order_id, :line_id, presence: true
    end
    stub_const("OrderLineAdded", klass)
    klass
  end

  before do
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta::Current.actor = Acta::Actor.new(type: "system")
    created_class
    cascade_class
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
  end

  describe "with `emits` declared" do
    let(:command_class) do
      klass = Class.new(Acta::Command) do
        emits OrderCreated

        param :customer_id, :string

        def call
          emit OrderCreated.new(order_id: "o_#{customer_id}", customer_id:)
        end
      end
      stub_const("CreateOrder", klass)
      klass
    end

    it "returns the emitted event" do
      result = command_class.call(customer_id: "c_1")

      expect(result).to be_a(OrderCreated)
      expect(result.order_id).to eq("o_c_1")
      expect(result.customer_id).to eq("c_1")
    end

    it "returns the event regardless of what the user's #call returns" do
      noisy_command = Class.new(Acta::Command) do
        emits OrderCreated
        param :customer_id, :string

        def call
          emit OrderCreated.new(order_id: "o_1", customer_id:)
          "trailing-string-ignored"
        end
      end
      stub_const("NoisyCommand", noisy_command)

      expect(noisy_command.call(customer_id: "c_1")).to be_a(OrderCreated)
    end

    it "returns nil when the command is idempotent and emits nothing" do
      noop_command = Class.new(Acta::Command) do
        emits OrderCreated
        param :customer_id, :string

        def call
          # idempotent: nothing to do
        end
      end
      stub_const("NoopCommand", noop_command)

      expect(noop_command.call(customer_id: "c_1")).to be_nil
    end

    it "returns the primary event for cascade commands that emit additional events" do
      cascade_command = Class.new(Acta::Command) do
        emits OrderCreated

        param :customer_id, :string

        def call
          emit OrderCreated.new(order_id: "o_99", customer_id:)
          emit OrderLineAdded.new(order_id: "o_99", line_id: "l_1")
          emit OrderLineAdded.new(order_id: "o_99", line_id: "l_2")
        end
      end
      stub_const("CascadeCommand", cascade_command)

      result = cascade_command.call(customer_id: "c_1")

      expect(result).to be_a(OrderCreated)
      expect(result.order_id).to eq("o_99")
    end

    it "exposes all emitted events on the instance via #emitted_events" do
      cascade_command = Class.new(Acta::Command) do
        emits OrderCreated
        param :customer_id, :string

        def call
          emit OrderCreated.new(order_id: "o_1", customer_id:)
          emit OrderLineAdded.new(order_id: "o_1", line_id: "l_1")
        end
      end
      stub_const("InstanceCommand", cascade_command)

      instance = cascade_command.new(customer_id: "c_1")
      instance.call

      expect(instance.emitted_events.map(&:class)).to eq([ OrderCreated, OrderLineAdded ])
    end

    it "Command#emit still returns the emitted event so user code can chain on it" do
      capture = nil

      capturing_command = Class.new(Acta::Command) do
        emits OrderCreated
        param :customer_id, :string
        param :captor, :string

        define_method(:call) do
          captured = emit OrderCreated.new(order_id: "o_1", customer_id:)
          # simulate the user grabbing the event id mid-call
          capture = captured
          captured
        end
      end
      stub_const("CapturingCommand", capturing_command)

      capturing_command.call(customer_id: "c_1", captor: "yes")

      expect(capture).to be_a(OrderCreated)
      expect(capture.order_id).to eq("o_1")
    end
  end

  describe "without `emits` declared" do
    it "returns whatever the user's #call returns (legacy behavior preserved)" do
      adder = Class.new(Acta::Command) do
        param :a, :integer
        param :b, :integer
        validates :a, :b, presence: true

        def call
          a + b
        end
      end
      stub_const("Adder", adder)

      expect(adder.call(a: 2, b: 3)).to eq(5)
    end

    it "returns whatever the user's #call returns even when the command does emit events" do
      # Without `emits`, Acta has no way to know which event is "primary",
      # so it doesn't try to guess — it returns the user's return value.
      stream_command = Class.new(Acta::Command) do
        stream :order, key: :order_id
        param :order_id, :string
        param :customer_id, :string

        def call
          emit OrderCreated.new(order_id:, customer_id:)
          :explicit_return
        end
      end
      stub_const("StreamCommand", stream_command)

      result = stream_command.call(order_id: "o_1", customer_id: "c_1")
      expect(result).to eq(:explicit_return)
    end
  end
end
