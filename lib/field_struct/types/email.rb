# frozen_string_literal: true

require_relative 'string'

module FieldStruct
  module Types
    # Email type — a {Types::String} that pre-fills the field's +format:+
    # option with a pragmatic email pattern. Same shape as
    # {Types::UUID} / {Types::URL}: bad-format input is a validation
    # error, not a coercion failure.
    #
    # The default pattern is deliberately not RFC 5322 strict — those
    # regexes are unwieldy and reject real-world addresses. It checks
    # +local@domain.tld+ shape with no internal whitespace or extra +@+
    # characters; users can override via +format: /.../+ for stricter
    # rules.
    class Email < FieldStruct::Types::String
      # @return [Regexp] pragmatic +local@domain.tld+ shape, no internal
      #   whitespace or extra +@+; deliberately not RFC 5322 strict.
      #   Override per-field via +format:+ (Regexp or Symbol preset).
      def self.default_format
        /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
      end

      # @return [Hash{Symbol=>Regexp}] named presets for +format:+
      def self.presets
        {
          permissive: /\A[^@\s]+@[^@\s]+\z/,
          default: default_format,
          strict: /\A[\w.+-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+\z/
        }
      end

      def self.resolve_options(options)
        PresetResolver.call(options, :format, presets, label: ':email format')
      end
    end
  end
end
