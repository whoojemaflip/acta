# frozen_string_literal: true

require "rails_helper"
require "active_record/encryption"

RSpec.describe Acta::Types::EncryptedString, :active_record do
  before(:all) do
    ActiveRecord::Encryption.configure(
      primary_key: "test" * 8,
      deterministic_key: "deterministic" * 4,
      key_derivation_salt: "salt" * 8
    )
  end

  let(:event_class) do
    klass = Class.new(Acta::Event) do
      stream :credential, key: :user_id

      attribute :user_id, :string
      attribute :access_token, :encrypted_string
      attribute :refresh_token, :encrypted_string
      attribute :expires_at, :datetime

      validates :user_id, :access_token, :refresh_token, :expires_at, presence: true
    end
    stub_const("CredentialIssued", klass)
    klass
  end

  let(:actor) { Acta::Actor.new(type: "user", id: "u_1", source: "oauth") }

  before do
    Acta.reset_adapter!
    Acta::Current.actor = actor
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
  end

  describe "in-memory access" do
    it "exposes plaintext on the in-memory event" do
      event = event_class.new(
        user_id: "u_1",
        access_token: "secret_access_abc",
        refresh_token: "secret_refresh_xyz",
        expires_at: Time.current
      )

      expect(event.access_token).to eq("secret_access_abc")
      expect(event.refresh_token).to eq("secret_refresh_xyz")
    end

    it "round-trips through to_acta_hash → from_acta_hash" do
      original = event_class.new(
        user_id: "u_1",
        access_token: "plain_token",
        refresh_token: "plain_refresh",
        expires_at: Time.current
      )

      restored = event_class.from_acta_hash(original.payload_hash)

      expect(restored.access_token).to eq("plain_token")
      expect(restored.refresh_token).to eq("plain_refresh")
    end
  end

  describe "serialized payload" do
    it "stores ciphertext, not plaintext" do
      event = event_class.new(
        user_id: "u_1",
        access_token: "the_real_token",
        refresh_token: "the_real_refresh",
        expires_at: Time.current
      )

      payload = event.payload_hash

      expect(payload["access_token"]).not_to include("the_real_token")
      expect(payload["refresh_token"]).not_to include("the_real_refresh")
      expect(ActiveRecord::Encryption.encryptor.encrypted?(payload["access_token"])).to be(true)
      expect(ActiveRecord::Encryption.encryptor.encrypted?(payload["refresh_token"])).to be(true)
    end

    it "leaves non-encrypted attributes plaintext alongside encrypted ones" do
      event = event_class.new(
        user_id: "u_42",
        access_token: "secret",
        refresh_token: "secret",
        expires_at: Time.current
      )

      expect(event.payload_hash["user_id"]).to eq("u_42")
    end

    it "produces fresh ciphertext on each serialize (non-deterministic)" do
      event = event_class.new(
        user_id: "u_1",
        access_token: "same_plaintext",
        refresh_token: "same_plaintext",
        expires_at: Time.current
      )

      first = event.payload_hash["access_token"]
      second = event.payload_hash["access_token"]

      expect(first).not_to eq(second)
    end
  end

  describe "nil handling" do
    let(:nullable_class) do
      klass = Class.new(Acta::Event) do
        attribute :user_id, :string
        attribute :access_token, :encrypted_string
        validates :user_id, presence: true
      end
      stub_const("NullableTokenEvent", klass)
      klass
    end

    it "passes nil through serialize and deserialize" do
      event = nullable_class.new(user_id: "u_1", access_token: nil)

      expect(event.payload_hash["access_token"]).to be_nil

      restored = nullable_class.from_acta_hash(event.payload_hash)
      expect(restored.access_token).to be_nil
    end
  end

  describe "log persistence" do
    it "writes ciphertext to the events table and reads back plaintext" do
      event = event_class.new(
        user_id: "u_1",
        access_token: "live_access",
        refresh_token: "live_refresh",
        expires_at: Time.utc(2030, 1, 1)
      )

      Acta.emit(event)

      raw_payload = Acta::Record.last.payload
      raw = raw_payload.is_a?(Hash) ? raw_payload : JSON.parse(raw_payload)

      expect(raw["access_token"]).not_to include("live_access")
      expect(raw["refresh_token"]).not_to include("live_refresh")

      reloaded = Acta.events.last
      expect(reloaded.access_token).to eq("live_access")
      expect(reloaded.refresh_token).to eq("live_refresh")
    end
  end
end
