# frozen_string_literal: true

require "rails_helper"
require "acta/testing"

RSpec.describe Acta::Testing, ".projection_writes_helper!" do
  let(:rspec_config) { RSpec::Core::Configuration.new }

  let(:example_group) do
    RSpec.describe("acta projection_writes host")
  end

  def run_example(example_group, &body)
    example_group.example("projection writes host", &body)
    runner = RSpec::Core::Reporter.new(rspec_config)
    example_group.run(runner)
  end

  it "exposes with_projection_writes to every example" do
    described_class.projection_writes_helper!(example_group)

    flag_inside = nil
    run_example(example_group) do
      with_projection_writes do
        flag_inside = Acta::Projection.applying?
      end
    end

    expect(flag_inside).to be(true)
  end

  it "restores the previous applying? state after the block" do
    described_class.projection_writes_helper!(example_group)

    flag_after = nil
    run_example(example_group) do
      with_projection_writes { }
      flag_after = Acta::Projection.applying?
    end

    expect(flag_after).to be(false)
  end

  it "yields the block's return value" do
    described_class.projection_writes_helper!(example_group)

    returned = nil
    run_example(example_group) do
      returned = with_projection_writes { 42 }
    end

    expect(returned).to eq(42)
  end
end
