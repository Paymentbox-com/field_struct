# frozen_string_literal: true

require 'bigdecimal'
require_relative 'base'

module FieldStruct
  module Types
    # BigDecimal type. Accepts a {::BigDecimal}, +Integer+, +Float+, or a
    # numeric string. Float input is converted with +Float::DIG+ precision
    # to avoid the bare +BigDecimal(Float)+ "can't omit precision" error.
    class BigDecimal < Base
      # @param value [Object] raw input
      # @param _options [Hash] unused
      # @return [BigDecimal, nil]
      # @raise [ArgumentError] when a string cannot be parsed
      def coerce(value, _options = {})
        return nil if value.nil?
        return value if value.is_a?(::BigDecimal)
        return ::Kernel.BigDecimal(value, ::Float::DIG) if value.is_a?(::Float)

        ::Kernel.BigDecimal(value.to_s)
      end

      # @return [Class] the top-level +::BigDecimal+ class
      def ruby_type
        ::BigDecimal
      end
    end
  end
end
