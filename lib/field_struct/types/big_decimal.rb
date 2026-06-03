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
      def self.option_schema
        super.merge(
          round: option(type: [::Integer]),
          in: option(type: [::Array, ::Range])
        )
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
      # @raise [ArgumentError] when a string cannot be parsed
      def coerce(value, round: self.class.default_round, **)
        return nil if value.nil?

        result = if value.is_a?(::BigDecimal)
                   value
                 elsif value.is_a?(::Float)
                   ::Kernel.BigDecimal(value, ::Float::DIG)
                 else
                   ::Kernel.BigDecimal(value.to_s)
                 end

        round ? result.round(round) : result
      end

      # @return [Class] the top-level +::BigDecimal+ class
      def ruby_type
        ::BigDecimal
      end
    end
  end
end
