# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Float type. Coerces via +Kernel#Float+, which parses numeric strings
    # strictly and rejects anything non-numeric. Strings are base 10, as for
    # {Types::Integer}: a hex string like "0x1A", which +Kernel#Float+ would
    # read as 26.0, is refused.
    class Float < Base
      # A string +Kernel#Float+ would read as hex: optional whitespace and
      # sign, then +0x+. (Binary and octal prefixes it already refuses.)
      # @return [::Regexp]
      HEX_PREFIX = /\A\s*[+-]?0x/i
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
      #   rejects non-numeric strings, Symbols, Booleans, Arrays, and
      #   hex strings ("0x1A").
      # @param round [::Integer, nil] decimal places, rounding half up (ties
      #   away from zero); +nil+ leaves the value unrounded. The result is a
      #   Float even at +round: 0+.
      # @return [::Float, nil] +nil+ for +nil+ input, otherwise the parsed float
      # @raise [ArgumentError, TypeError] when the value cannot be coerced
      #   (a String that is not a number, a Complex), or coerces to NaN or
      #   ±Infinity (including a String like "1e400")
      def coerce(value, round: self.class.default_round, **)
        return nil if value.nil?

        result = value.is_a?(::Float) ? value : parse(value)
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

      private

      # @param value [Object] a non-Float value
      # @return [::Float]
      # @raise [ArgumentError] when it is a hex string or +Kernel#Float+
      #   refuses it; the message names the class, never the value
      #   (Kernel's own message echoes it)
      def parse(value)
        if value.is_a?(::String) && HEX_PREFIX.match?(value)
          raise ArgumentError, 'Float fields expect a base-10 number, got a String that is not one'
        end

        begin
          ::Kernel.Float(value)
        rescue ::ArgumentError, ::RangeError
          raise ArgumentError, "Float fields could not read a #{value.class} as a number", cause: nil
        end
      end
    end
  end
end
