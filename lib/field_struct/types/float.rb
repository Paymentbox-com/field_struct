# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Float type. Coerces via +Kernel#Float+, which parses numeric strings
    # strictly and rejects anything non-numeric.
    class Float < Base
      # @param value [Object] raw input
      # @param _options [Hash] unused
      # @return [Float, nil] +nil+ for +nil+ input, otherwise the parsed float
      # @raise [ArgumentError, TypeError] when the value cannot be coerced
      def coerce(value, _options = {})
        return nil if value.nil?
        return value if value.is_a?(::Float)

        ::Kernel.Float(value)
      end

      # @return [Class] the top-level +::Float+ class
      def ruby_type
        ::Float
      end
    end
  end
end
