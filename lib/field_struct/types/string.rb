# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # String type. Coerces any non-nil value via +to_s+; treats nil, empty,
    # and whitespace-only strings as missing.
    class String < Base
      # @param value [#to_s, nil] anything stringable (everything in
      #   Ruby responds to +to_s+); +nil+ stays +nil+
      # @return [String, nil] +nil+ when input is +nil+, otherwise +value.to_s+
      def coerce(value, **)
        return nil if value.nil?

        value.to_s
      end

      # Missing if nil, empty, or whitespace-only.
      #
      # @param value [Object]
      # @return [Boolean]
      def missing?(value)
        return true if value.nil?
        return true if value.respond_to?(:strip) && value.strip.empty?

        false
      end

      # @return [Class] the top-level +::String+ class
      def ruby_type
        ::String
      end
    end
  end
end
