# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Class-typed event attributes", :active_record do
  let(:point_class) do
    klass = Class.new(Acta::Model) do
      attribute :lat, :float
      attribute :lng, :float
    end
    stub_const("GeoPoint", klass)
    klass
  end

  let(:event_class) do
    klass = Class.new(Acta::Event) do
      attribute :location, GeoPoint
      attribute :label, :string
      validates :label, presence: true
    end
    stub_const("LocationNoted", klass)
    klass
  end

  before do
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta::Current.actor = Acta::Actor.new(type: "system")
    point_class
    event_class
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
  end

  describe "Acta::Model payload attributes" do
    it "accepts a typed instance directly" do
      point = point_class.new(lat: 49.2, lng: -123.1)
      event = event_class.new(label: "Home", location: point)

      expect(event.location).to be_a(point_class)
      expect(event.location.lat).to eq(49.2)
    end

    it "casts a hash into the declared class" do
      event = event_class.new(label: "Home", location: { lat: 49.2, lng: -123.1 })

      expect(event.location).to be_a(point_class)
      expect(event.location.lat).to eq(49.2)
      expect(event.location.lng).to eq(-123.1)
    end

    it "accepts nil" do
      event = event_class.new(label: "Home", location: nil)

      expect(event.location).to be_nil
    end

    it "serialises to a nested hash in payload_hash" do
      event = event_class.new(label: "Home", location: { lat: 49.2, lng: -123.1 })

      expect(event.payload_hash["location"]).to eq("lat" => 49.2, "lng" => -123.1)
    end

    it "round-trips through Acta.emit and Acta.events" do
      event = event_class.new(label: "Home", location: { lat: 49.2, lng: -123.1 })
      Acta.emit(event)

      reloaded = Acta.events.last

      expect(reloaded.location).to be_a(point_class)
      expect(reloaded.location.lat).to eq(49.2)
      expect(reloaded.location.lng).to eq(-123.1)
    end
  end

  describe "Acta::Serializable AR attributes" do
    before do
      unless ActiveRecord::Base.connection.table_exists?(:test_addresses)
        ActiveRecord::Base.connection.create_table(:test_addresses) do |t|
          t.string :street
          t.string :city
          t.string :postal_code
          t.timestamps
        end
      end
      stub_const("TestAddress", address_class)
      stub_const("PublisherRelocated", publisher_event_class)
    end

    let(:address_class) do
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "test_addresses"
        include Acta::Serializable
        acta_serialize except: [ :created_at, :updated_at, :id ]
      end
      stub_const("TestAddress", klass)
      klass
    end

    let(:publisher_event_class) do
      klass = Class.new(Acta::Event) do
        attribute :publisher_id, :string
        attribute :address, TestAddress
        validates :publisher_id, presence: true
      end
      stub_const("PublisherRelocated", klass)
      klass
    end

    before do
      address_class
      publisher_event_class
    end

    it "accepts an AR instance as the attribute value" do
      addr = address_class.new(street: "1 Main", city: "Vancouver", postal_code: "V6B")
      event = publisher_event_class.new(publisher_id: "w_1", address: addr)

      expect(event.address).to be_a(address_class)
      expect(event.address.street).to eq("1 Main")
    end

    it "casts a hash payload to an AR instance" do
      event = publisher_event_class.new(
        publisher_id: "w_1",
        address: { street: "1 Main", city: "V", postal_code: "V6B" }
      )

      expect(event.address).to be_a(address_class)
      expect(event.address).to be_new_record
      expect(event.address.street).to eq("1 Main")
    end

    it "round-trips an AR-backed payload through Acta.emit / Acta.events" do
      addr = address_class.new(street: "1 Main", city: "V", postal_code: "V6B")
      event = publisher_event_class.new(publisher_id: "w_1", address: addr)

      Acta.emit(event)
      reloaded = Acta.events.last

      expect(reloaded.address).to be_a(address_class)
      expect(reloaded.address).to be_new_record
      expect(reloaded.address.street).to eq("1 Main")
    end
  end
end
