# frozen_string_literal: true

require "uri"
require "json"

module Acta
  module Web
    module ApplicationHelper
      def acta_chip_hue(event_type)
        h = event_type.to_s.chars.reduce(0) { |acc, c| ((acc * 31 + c.ord) & 0xFFFFFFFF) }
        h.abs % 360
      end

      def acta_dot_color(event_type)
        "oklch(0.70 0.14 #{acta_chip_hue(event_type)})"
      end

      def acta_fmt_time(time)
        return "-" unless time
        t = time.respond_to?(:utc) ? time.utc : Time.parse(time.to_s).utc
        ms = t.strftime("%3N")
        t.strftime("%H:%M:%S") + ".#{ms}"
      end

      def acta_fmt_abs(time)
        return "-" unless time
        t = time.respond_to?(:utc) ? time.utc : Time.parse(time.to_s).utc
        ms = t.strftime("%3N")
        t.strftime("%Y-%m-%d %H:%M:%S") + ".#{ms}Z"
      end

      def acta_preview_payload(payload)
        return "{}" unless payload.is_a?(Hash) && payload.any?
        masked = acta_mask_encrypted(payload)
        masked.keys.first(3).map { |k| "#{k}=#{masked[k].inspect}" }.join(" ")
      rescue StandardError
        "{}"
      end

      def acta_pretty_json(obj)
        JSON.pretty_generate(acta_mask_encrypted(obj))
      rescue StandardError
        obj.to_s
      end

      # Replace any AR::Encryption-recognized ciphertext leaf in `obj`
      # with "********". Walks hashes and arrays; non-encrypted scalars
      # pass through unchanged. Used by the admin UI so encrypted payload
      # values aren't displayed as raw ciphertext envelopes.
      ACTA_MASK = "********"

      def acta_mask_encrypted(obj)
        case obj
        when Hash  then obj.each_with_object({}) { |(k, v), acc| acc[k] = acta_mask_encrypted(v) }
        when Array then obj.map { |v| acta_mask_encrypted(v) }
        when String then acta_encrypted_value?(obj) ? ACTA_MASK : obj
        else obj
        end
      end

      def acta_encrypted_value?(value)
        return false unless defined?(ActiveRecord::Encryption)

        ActiveRecord::Encryption.encryptor.encrypted?(value)
      rescue StandardError
        false
      end

      # Build a URL for the events index, merging +overrides+ into current params.
      # Pass nil for a key to remove it. Resets page when filters change.
      def acta_filter_url(overrides = {})
        current = {
          event_type: params[:event_type],
          stream_type: params[:stream_type],
          actor_id: params[:actor_id],
          stream_key: params[:stream_key],
          q: params[:q],
          selected: params[:selected],
          page: params[:page]
        }.compact_blank

        overrides = overrides.transform_keys(&:to_sym)
        filter_keys = %i[event_type stream_type actor_id stream_key q]
        current.delete(:page) if (overrides.keys & filter_keys).any?
        current.delete(:selected) if (overrides.keys & filter_keys).any?

        merged = current.merge(overrides)
        merged.compact_blank!
        merged.delete(:page) if merged[:page].to_s == "0"

        encode_params(merged)
      end

      private

      def encode_params(hash)
        query = hash.map { |k, v| "#{enc(k)}=#{enc(v)}" }.join("&")
        query.empty? ? request.path : "#{request.path}?#{query}"
      end

      def enc(val)
        URI.encode_www_form_component(val.to_s)
      end
    end
  end
end
