# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Integer type. Coerces numerics and digit-strings via +Kernel#Integer+,
    # so float-shaped strings like "3.14" deliberately raise rather than
    # silently truncate. Float numerics, by contrast, are truncated — that
    # matches +Kernel#Integer+'s own behavior on numeric input.
    class Integer < Base
      # Native options: an +in:+ Array or Range of allowed values.
      #
      # @return [::Hash{::Symbol => ::Hash{::Symbol => Object}}]
      def self.option_schema
        super.merge(in: option(type: [::Array, ::Range]))
      end

      # @param value [Integer, Numeric, ::String, nil] +nil+ → +nil+;
      #   +Integer+ passes through; everything else flows through
      #   +Kernel#Integer+ — Floats are truncated, digit-strings parse,
      #   float-shaped strings ("3.14") and non-digit strings raise
      #   ArgumentError, Symbols/Booleans/Arrays raise TypeError.
      # @return [Integer, nil] +nil+ for +nil+ input, otherwise the parsed integer
      # @raise [ArgumentError, TypeError] when the value cannot be coerced
      def coerce(value, **)
        return nil if value.nil?
        return value if value.is_a?(::Integer)

        ::Kernel.Integer(value)
      end

      # @return [Class] the top-level +::Integer+ class
      def ruby_type
        ::Integer
      end
    end
  end
end
