# frozen_string_literal: true

require "active_model/type"
require "zlib"
require "active_record/encryption"

module Acta
  module Types
    # Per-attribute opt-in encryption for event payloads. Declare with
    # `attribute :token, :encrypted_string` (or pass an instance directly).
    #
    # Encryption uses Rails' built-in ActiveRecord::Encryption — the same
    # primary/deterministic/derivation keys configured for AR-encrypted
    # columns. Configure once via `bin/rails db:encryption:init` and
    # Rails credentials; key rotation works the same way (append a new
    # primary, keep old keys for decryption).
    #
    # In-memory values are always plaintext: `event.token` returns the
    # raw secret. The encrypted form only appears in the serialized
    # payload that's written to the events table.
    class EncryptedString < ActiveModel::Type::Value
      def initialize(deterministic: false)
        super()
        @deterministic = deterministic
      end

      def cast(value)
        return nil if value.nil?

        value.to_s
      end

      def serialize(value)
        return nil if value.nil?

        encryptor.encrypt(value.to_s, **encrypt_options)
      end

      def deserialize(value)
        return nil if value.nil?

        str = value.to_s
        return str unless encryptor.encrypted?(str)

        encryptor.decrypt(str)
      end

      private

      def encryptor
        ActiveRecord::Encryption.encryptor
      end

      def encrypt_options
        return {} unless @deterministic

        { key_provider: ActiveRecord::Encryption.deterministic_key_provider }
      end
    end
  end
end

ActiveModel::Type.register(:encrypted_string, Acta::Types::EncryptedString)
