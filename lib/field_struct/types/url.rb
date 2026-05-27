# frozen_string_literal: true

require_relative 'string'

module FieldStruct
  module Types
    # URL type — a {Types::String} that pre-fills the field's +format:+
    # option with a practical http(s) URL pattern. Same shape as
    # {Types::UUID}: bad-format input is a Phase 1 validation error,
    # not a coercion failure.
    #
    # The default pattern matches +http://+ and +https://+ URLs with a
    # non-empty host. It is intentionally pragmatic, not RFC 3986
    # exhaustive — users can override via +format: /.../+ if they need
    # different schemes or stricter host rules.
    class URL < FieldStruct::Types::String
      # @return [Regexp] practical http(s) pattern; override per-field via +format:+
      def self.default_format
        %r{\Ahttps?://[^\s/$.?#][^\s]*\z}i
      end

      # @return [Hash{Symbol=>Regexp}] named presets for +format:+
      def self.presets
        {
          http: default_format,
          https_only: %r{\Ahttps://[^\s/$.?#][^\s]*\z}i,
          any_scheme: %r{\A[a-z][a-z0-9+\-.]*://[^\s/$.?#][^\s]*\z}i
        }
      end

      def self.resolve_options(options)
        PresetResolver.call(options, :format, presets, label: ':url format')
      end
    end
  end
end
