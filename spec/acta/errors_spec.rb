# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Acta error hierarchy" do
  it "defines Acta::Error as a StandardError" do
    expect(Acta::Error).to be < StandardError
  end

  it "defines Acta::InvalidEvent as an Acta::Error" do
    expect(Acta::InvalidEvent).to be < Acta::Error
  end

  it "defines Acta::MissingActor as an Acta::Error" do
    expect(Acta::MissingActor).to be < Acta::Error
  end

  it "defines Acta::ConfigurationError as an Acta::Error" do
    expect(Acta::ConfigurationError).to be < Acta::Error
  end

  it "defines Acta::AdapterError as an Acta::Error" do
    expect(Acta::AdapterError).to be < Acta::Error
  end
end
