# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Float type. Coerces via +Kernel#Float+, which parses numeric strings
    # strictly and rejects anything non-numeric.
    class Float < Base
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

      # @return [::Integer, nil] field-level rounding precision; +nil+ disables.
      def self.default_round
        nil
      end

      # @param value [Numeric, ::String, nil] +nil+ → +nil+; everything
      #   else flows through +Kernel#Float+ — strict on string parsing,
      #   rejects non-numeric strings, Symbols, Booleans, Arrays.
      # @param round [::Integer, nil] decimal places; +nil+ leaves the value unrounded
      # @return [Float, nil] +nil+ for +nil+ input, otherwise the parsed float
      # @raise [ArgumentError, TypeError] when the value cannot be coerced
      def coerce(value, round: self.class.default_round, **)
        return nil if value.nil?

        result = value.is_a?(::Float) ? value : ::Kernel.Float(value)
        round ? result.round(round) : result
      end

      # @return [Class] the top-level +::Float+ class
      def ruby_type
        ::Float
      end
    end
  end
end
