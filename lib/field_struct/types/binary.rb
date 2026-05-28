# frozen_string_literal: true

require_relative 'string'

module FieldStruct
  module Types
    # Binary type — coerces input to a String and forces +ASCII-8BIT+
    # encoding. Intended for raw bytes (file contents, BLOBs, etc.)
    # where whitespace bytes (+\x20+, +\n+, etc.) are meaningful data,
    # not "missing" content.
    #
    # +missing?+ is therefore +nil+-or-empty only — unlike
    # {Types::String} which treats whitespace-only as missing.
    class Binary < FieldStruct::Types::String
      # @param value [#to_s, nil] anything stringable; +nil+ stays +nil+
      # @return [::String, nil] +nil+ when input is +nil+, otherwise a
      #   fresh ASCII-8BIT-encoded copy of +value.to_s+
      def coerce(value, **)
        result = super
        return nil if result.nil?

        result.dup.force_encoding(::Encoding::ASCII_8BIT)
      end

      # Missing if nil or empty. Whitespace bytes are meaningful in
      # binary data, so they don't count as missing.
      #
      # @param value [Object]
      # @return [Boolean]
      def missing?(value)
        return true if value.nil?
        return true if value.respond_to?(:empty?) && value.empty?

        false
      end
    end
  end
end
