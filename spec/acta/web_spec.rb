# frozen_string_literal: true

require "spec_helper"
require "acta/web"

RSpec.describe Acta::Web do
  before { described_class.reset_configuration! }
  after  { described_class.reset_configuration! }

  describe ".base_controller_class" do
    it "raises ConfigurationError when not set" do
      expect { described_class.base_controller_class }.to raise_error(
        Acta::Web::ConfigurationError, /not set/
      )
    end

    it "includes setup instructions in the error message" do
      expect { described_class.base_controller_class }.to raise_error(
        Acta::Web::ConfigurationError,
        /config\/initializers\/acta_web\.rb/
      )
    end

    it "warns about public-access risk in the error message" do
      expect { described_class.base_controller_class }.to raise_error(
        Acta::Web::ConfigurationError,
        /publicly accessible|isn't publicly accessible|authentication/i
      )
    end

    it "returns the configured class string" do
      described_class.base_controller_class = "ApplicationController"
      expect(described_class.base_controller_class).to eq("ApplicationController")
    end

    it "accepts arbitrary class names" do
      described_class.base_controller_class = "Admin::BaseController"
      expect(described_class.base_controller_class).to eq("Admin::BaseController")
    end
  end

  describe ".reset_configuration!" do
    it "clears the configured class" do
      described_class.base_controller_class = "Foo"
      described_class.reset_configuration!
      expect { described_class.base_controller_class }.to raise_error(Acta::Web::ConfigurationError)
    end
  end
end
