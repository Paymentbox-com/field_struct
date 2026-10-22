# frozen_string_literal: true

require 'bigdecimal'
require_relative 'base'

module FieldStruct
  module Types
    # BigDecimal type. Accepts a {::BigDecimal}, +Integer+, +Float+, or a
    # numeric string. Float input is converted with +Float::DIG+ precision
    # to avoid the bare +BigDecimal(Float)+ "can't omit precision" error.
    class BigDecimal < Base
      # Native options: a +round:+ Integer precision and an +in:+ Array or
      # Range of allowed values.
      #
      # @return [::Hash{::Symbol => ::Hash{::Symbol => Object}}]
      def self.own_option_schema
        {
          round: option(type: [::Integer]),
          in: option(type: [::Array, ::Range])
        }
      end

      # @return [::Integer, nil] the field-level rounding precision, or +nil+
      #   for no rounding. Subclasses override.
      def self.default_round
        nil
      end

      # @param value [::BigDecimal, Numeric, ::String, nil] +nil+ → +nil+;
      #   a +BigDecimal+ passes through; +Float+ uses +Float::DIG+
      #   precision; everything else goes through
      #   +Kernel.BigDecimal(value.to_s)+ — non-numeric strings raise
      #   ArgumentError.
      # @param round [::Integer, nil] decimal places, rounding half up (ties
      #   away from zero) whatever the global +BigDecimal.mode+; +nil+ leaves
      #   the value unrounded. The result is a BigDecimal even at +round: 0+.
      # @return [::BigDecimal, nil]
      # @raise [ArgumentError] when a value's string form cannot be parsed
      #   (e.g. a non-numeric String, or a Rational's "1/3"), or the value
      #   is NaN or ±Infinity (as a Float, a BigDecimal, or a String like "NaN")
      def coerce(value, round: self.class.default_round, **)
        return nil if value.nil?

        result = if value.is_a?(::BigDecimal)
                   value
                 elsif value.is_a?(::Float)
                   ::Kernel.BigDecimal(value, ::Float::DIG)
                 else
                   parse(value)
                 end
        # The class, never the value — see Types::Time#coerce.
        raise ArgumentError, "BigDecimal fields expect a finite number, got a non-finite #{value.class}" unless result.finite?

        # An explicit mode keeps the result a BigDecimal (bare round(0)
        # returns an Integer) and ignores the process-global
        # BigDecimal.mode, which a host may have set to banker's rounding.
        round ? result.round(round, ::BigDecimal::ROUND_HALF_UP) : result
      end

      # @return [Class] the top-level +::BigDecimal+ class
      def ruby_type
        ::BigDecimal
      end

      private

      # @param value [Object] a value that is neither a BigDecimal nor a Float
      # @return [::BigDecimal]
      # @raise [ArgumentError] when its string form is not a number; the
      #   message names the class, never the value (Kernel's echoes it)
      def parse(value)
        ::Kernel.BigDecimal(value.to_s)
      rescue ::ArgumentError
        raise ArgumentError, "BigDecimal fields could not read a #{value.class} as a number"
      end
    end
  end
end
