# frozen_string_literal: true

require "spec_helper"
require "acta/web"
require "action_view"
require "action_view/helpers"
require_relative "../../../app/helpers/acta/web/application_helper"

RSpec.describe Acta::Web::ApplicationHelper do
  # Mix the helper into a struct that also stubs `params` and `request` —
  # the helper's URL builders depend on those for the host context.
  let(:fake_request) { double("request", path: "/acta/events") }
  let(:fake_params) { ActiveSupport::HashWithIndifferentAccess.new }

  let(:helper) do
    request_local = fake_request
    params_local = fake_params
    fake = Object.new.extend(described_class)
    fake.define_singleton_method(:request) { request_local }
    fake.define_singleton_method(:params) { params_local }
    fake
  end

  describe "#acta_chip_hue" do
    it "returns a hue between 0 and 359" do
      h = helper.acta_chip_hue("AnyEventType")
      expect(h).to be_between(0, 359)
    end

    it "is deterministic for the same input" do
      a = helper.acta_chip_hue("RideEffortRecorded")
      b = helper.acta_chip_hue("RideEffortRecorded")
      expect(a).to eq(b)
    end

    it "yields different hues for different inputs (typically)" do
      hues = %w[Foo Bar Baz Qux Quux].map { |t| helper.acta_chip_hue(t) }
      expect(hues.uniq.length).to be > 1
    end

    it "handles symbol input" do
      expect { helper.acta_chip_hue(:SymbolName) }.not_to raise_error
    end
  end

  describe "#acta_dot_color" do
    it "wraps the hue in an oklch() string" do
      color = helper.acta_dot_color("Foo")
      expect(color).to match(/\Aoklch\(0\.70 0\.14 \d+\)\z/)
    end
  end

  describe "#acta_fmt_time" do
    it "returns '-' for nil" do
      expect(helper.acta_fmt_time(nil)).to eq("-")
    end

    it "formats a Time as HH:MM:SS.mmm" do
      t = Time.utc(2026, 4, 27, 12, 34, 56, 789_000)
      expect(helper.acta_fmt_time(t)).to eq("12:34:56.789")
    end

    it "accepts a String and parses it" do
      expect(helper.acta_fmt_time("2026-04-27T12:34:56.789Z")).to eq("12:34:56.789")
    end

    it "normalises non-UTC times to UTC" do
      t = Time.new(2026, 4, 27, 5, 34, 56, "-07:00") # 12:34:56 UTC
      expect(helper.acta_fmt_time(t)).to start_with("12:34:56")
    end
  end

  describe "#acta_fmt_abs" do
    it "returns '-' for nil" do
      expect(helper.acta_fmt_abs(nil)).to eq("-")
    end

    it "formats with the date prefix" do
      t = Time.utc(2026, 4, 27, 12, 34, 56, 789_000)
      expect(helper.acta_fmt_abs(t)).to eq("2026-04-27 12:34:56.789Z")
    end
  end

  describe "#acta_preview_payload" do
    it "returns '{}' for non-Hash input" do
      expect(helper.acta_preview_payload(nil)).to eq("{}")
      expect(helper.acta_preview_payload("foo")).to eq("{}")
      expect(helper.acta_preview_payload([])).to eq("{}")
    end

    it "returns '{}' for an empty hash" do
      expect(helper.acta_preview_payload({})).to eq("{}")
    end

    it "shows the first 3 keys joined" do
      payload = { a: 1, b: 2, c: 3, d: 4, e: 5 }
      preview = helper.acta_preview_payload(payload)
      expect(preview).to include("a=1", "b=2", "c=3")
      expect(preview).not_to include("d=", "e=")
    end
  end

  describe "#acta_pretty_json" do
    it "pretty-prints a hash" do
      json = helper.acta_pretty_json({ key: "value" })
      expect(json).to include("\"key\"")
      expect(json).to include("\"value\"")
      expect(json).to include("\n")
    end

    it "falls back to to_s on serialization failure" do
      bad = Object.new
      def bad.to_s; "weird-object"; end
      def bad.to_json(*); raise "boom"; end

      expect(helper.acta_pretty_json(bad)).to eq("weird-object")
    end
  end

  describe "#acta_filter_url" do
    it "builds a query string from the merged params" do
      url = helper.acta_filter_url(event_type: "Foo")
      expect(url).to start_with("/acta/events?")
      expect(url).to include("event_type=Foo")
    end

    it "URL-encodes special chars" do
      url = helper.acta_filter_url(q: "hello world")
      expect(url).to include("q=hello+world").or include("q=hello%20world")
    end

    it "drops :page when a filter param changes" do
      allow(helper).to receive(:params).and_return(
        ActiveSupport::HashWithIndifferentAccess.new(page: "5", event_type: "OldType")
      )
      url = helper.acta_filter_url(event_type: "NewType")
      expect(url).to include("event_type=NewType")
      expect(url).not_to include("page=")
    end

    it "drops :selected when a filter param changes" do
      allow(helper).to receive(:params).and_return(
        ActiveSupport::HashWithIndifferentAccess.new(selected: "abc-uuid", event_type: "OldType")
      )
      url = helper.acta_filter_url(event_type: "NewType")
      expect(url).not_to include("selected=")
    end

    it "preserves :page when only :page itself changes" do
      allow(helper).to receive(:params).and_return(
        ActiveSupport::HashWithIndifferentAccess.new(event_type: "Foo", page: "1")
      )
      url = helper.acta_filter_url(page: "2")
      expect(url).to include("event_type=Foo")
      expect(url).to include("page=2")
    end

    it "drops :page when explicitly set to '0'" do
      url = helper.acta_filter_url(event_type: "Foo", page: "0")
      expect(url).not_to include("page=0")
    end

    it "returns just the path when no filters are set" do
      url = helper.acta_filter_url({})
      expect(url).to eq("/acta/events")
    end
  end
end
