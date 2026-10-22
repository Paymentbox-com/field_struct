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
      # @param round [::Integer, nil] decimal places; +nil+ leaves the
      #   value unrounded
      # @return [::BigDecimal, nil]
      # @raise [ArgumentError] when a string cannot be parsed, or the value
      #   is NaN or ±Infinity (as a Float, a BigDecimal, or a String like "NaN")
      def coerce(value, round: self.class.default_round, **)
        return nil if value.nil?

        result = if value.is_a?(::BigDecimal)
                   value
                 elsif value.is_a?(::Float)
                   ::Kernel.BigDecimal(value, ::Float::DIG)
                 else
                   ::Kernel.BigDecimal(value.to_s)
                 end
        # The class, never the value — see Types::Time#coerce.
        raise ArgumentError, "BigDecimal fields expect a finite number, got a non-finite #{value.class}" unless result.finite?

        round ? result.round(round) : result
      end

      # @return [Class] the top-level +::BigDecimal+ class
      def ruby_type
        ::BigDecimal
      end
    end
  end
end
