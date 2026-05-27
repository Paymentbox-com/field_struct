# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Float type. Coerces via +Kernel#Float+, which parses numeric strings
    # strictly and rejects anything non-numeric.
    class Float < Base
      # @return [Integer, nil] field-level rounding precision; +nil+ disables.
      def self.default_round
        nil
      end

      # @param value [Object] raw input
      # @param options [Hash] supports +:round+ (Integer) to round to that
      #   many decimal places
      # @return [Float, nil] +nil+ for +nil+ input, otherwise the parsed float
      # @raise [ArgumentError, TypeError] when the value cannot be coerced
      def coerce(value, options = {})
        return nil if value.nil?

        result = value.is_a?(::Float) ? value : ::Kernel.Float(value)
        round = options.fetch(:round) { self.class.default_round }
        round ? result.round(round) : result
      end

      # @return [Class] the top-level +::Float+ class
      def ruby_type
        ::Float
      end
    end
  end
end
