# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Integer type. Strings parse in base 10 unless the field declares a
    # +base:+, so "010" is ten (not octal eight) and "0x1A" is refused rather
    # than read as hex. Float-shaped strings like "3.14" raise rather than
    # silently truncate. Float numerics, by contrast, are truncated — that
    # matches +Kernel#Integer+'s own behavior on numeric input — unless the
    # field declares +strict: true+, which refuses any non-integral value.
    class Integer < Base
      # The radixes +Kernel#Integer+ accepts for a +base:+ option.
      # @return [::Range<::Integer>]
      BASES = (2..36)

      # Native options: an +in:+ Array or Range of allowed values, a
      # +base:+ Integer radix (2..36) for string input, and a +strict:+
      # Boolean.
      #
      # @return [::Hash{::Symbol => ::Hash{::Symbol => Object}}]
      def self.own_option_schema
        {
          in: option(type: [::Array, ::Range]),
          base: option(type: [::Integer]),
          strict: option(type: [::TrueClass, ::FalseClass])
        }
      end

      # Refuse a +base:+ outside 2..36 at field-declaration time. A
      # non-Integer +base:+ is left for the option-shape check to report.
      #
      # @param options [::Hash{::Symbol => Object, nil}] the per-field options hash
      # @return [::Hash{::Symbol => Object, nil}] the options, unchanged
      # @raise [ArgumentError] when +base:+ is an Integer outside 2..36
      def self.resolve_options(options)
        base = options[:base]
        if base.is_a?(::Integer) && !BASES.cover?(base)
          raise ArgumentError, "base: on Integer expects an Integer from 2 to 36, got #{base}"
        end

        options
      end

      # @param value [::Integer, Numeric, ::String, nil] +nil+ → +nil+;
      #   +Integer+ passes through; a String parses in +base+ (surrounding
      #   whitespace and digit underscores allowed; float-shaped or
      #   out-of-base strings raise ArgumentError); other numerics flow
      #   through +Kernel#Integer+ — Floats are truncated;
      #   Symbols/Booleans/Arrays raise TypeError.
      # @param base [::Integer, nil] radix (2..36) for String input; +nil+
      #   means 10
      # @param strict [Boolean, nil] when true, refuse a value that is not a
      #   whole number (+12.7+, a +Time+) instead of truncating it; an
      #   integral one (+12.0+) still becomes its Integer
      # @return [::Integer, nil] +nil+ for +nil+ input, otherwise the parsed integer
      # @raise [ArgumentError, TypeError] when the value cannot be coerced,
      #   including a NaN or ±Infinity Numeric (Float, BigDecimal) and a
      #   Complex with an imaginary part
      def coerce(value, base: 10, strict: false, **)
        return nil if value.nil?
        return value if value.is_a?(::Integer)
        return parse_string(value, base || 10) if value.is_a?(::String)
        if value.is_a?(::Numeric) && !value.finite?
          # The class, never the value — see Types::Time#coerce.
          raise ArgumentError, "Integer fields expect a finite number, got a non-finite #{value.class}"
        end

        refuse_huge_decimal!(value)

        whole = begin
          ::Kernel.Integer(value)
        rescue ::RangeError
          # A Complex with an imaginary part; Kernel's message echoes the value.
          raise ArgumentError, "Integer fields could not read a #{value.class} as a number", cause: nil
        end
        refuse_inexact!(value, whole) if strict
        whole
      end

      # The most integer digits a decimal may expand to. +BigDecimal('1e10000000')+
      # is 11 bytes, but its Integer takes seconds to build, so untrusted JSON
      # could burn CPU. The same limit as Python's int/str conversion
      # (CVE-2020-10735).
      #
      # @return [::Integer]
      MAX_DECIMAL_DIGITS = 4300

      # @return [Class] the top-level +::Integer+ class
      def ruby_type
        ::Integer
      end

      private

      # @param value [Object]
      # @return [void]
      # @raise [ArgumentError] when +value+ is a decimal whose integer part has
      #   more than {MAX_DECIMAL_DIGITS} digits
      def refuse_huge_decimal!(value)
        return unless defined?(::BigDecimal) && value.is_a?(::BigDecimal)
        return if value.exponent <= MAX_DECIMAL_DIGITS

        raise ArgumentError, "Integer fields read a decimal of at most #{MAX_DECIMAL_DIGITS} digits, " \
                             "got a larger #{value.class}"
      end

      # @param value [Object] the input, already read by +Kernel#Integer+
      # @param whole [::Integer] what +Kernel#Integer+ made of it
      # @return [void]
      # @raise [ArgumentError] unless +whole+ equals +value+ — i.e. the read
      #   truncated a fraction, or went through +to_i+ on a non-number
      def refuse_inexact!(value, whole)
        return if whole == value

        # The class, never the value — see Types::Time#coerce.
        raise ArgumentError, "Integer fields with strict: true expect a whole number, got a #{value.class} that is not one"
      end

      # @param value [::String]
      # @param base [::Integer]
      # @return [::Integer]
      # @raise [ArgumentError] when the string is not an integer in +base+
      def parse_string(value, base)
        ::Kernel.Integer(value, base)
      rescue ::ArgumentError
        # The class, never the value — see Types::Time#coerce.
        raise ArgumentError, "Integer fields expect a base-#{base} integer, got a String that is not one", cause: nil
      end
    end
  end
end
