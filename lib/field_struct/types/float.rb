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
      def self.own_option_schema
        {
          round: option(type: [::Integer]),
          in: option(type: [::Array, ::Range])
        }
      end

      # @return [::Integer, nil] field-level rounding precision; +nil+ disables.
      def self.default_round
        nil
      end

      # @param value [Numeric, ::String, nil] +nil+ → +nil+; everything
      #   else flows through +Kernel#Float+ — strict on string parsing,
      #   rejects non-numeric strings, Symbols, Booleans, Arrays.
      # @param round [::Integer, nil] decimal places, rounding half up (ties
      #   away from zero); +nil+ leaves the value unrounded. The result is a
      #   Float even at +round: 0+.
      # @return [Float, nil] +nil+ for +nil+ input, otherwise the parsed float
      # @raise [ArgumentError, TypeError] when the value cannot be coerced,
      #   or coerces to NaN or ±Infinity (including a String like "1e400")
      def coerce(value, round: self.class.default_round, **)
        return nil if value.nil?

        result = value.is_a?(::Float) ? value : ::Kernel.Float(value)
        # The class, never the value — see Types::Time#coerce.
        raise ArgumentError, "Float fields expect a finite number, got a non-finite #{value.class}" unless result.finite?

        # Float#round returns an Integer at round: 0; .to_f keeps the
        # field's type. half: :up pins ties away from zero.
        round ? result.round(round, half: :up).to_f : result
      end

      # @return [Class] the top-level +::Float+ class
      def ruby_type
        ::Float
      end
    end
  end
end
