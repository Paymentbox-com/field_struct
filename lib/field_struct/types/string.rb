# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # String type. Coerces any non-nil value via +to_s+; treats nil, empty,
    # and whitespace-only strings as missing. A field declared +strict: true+
    # accepts only scalars (String, Symbol, Integer) and objects
    # responding to +to_str+, so a Hash or Array is refused rather than stored
    # as its +inspect+ text.
    class String < Base
      # Native options: a +format:+ Regexp (or Symbol preset, used by the
      # +:uuid+ / +:url+ / +:email+ subtypes), an +enum:+ Array of
      # allowed values, and a +strict:+ Boolean.
      #
      # @return [::Hash{::Symbol => ::Hash{::Symbol => Object}}]
      def self.own_option_schema
        {
          format: option(type: [::Regexp, ::Symbol]),
          enum: option(type: [::Array]),
          strict: option(type: [::TrueClass, ::FalseClass])
        }
      end

      # @param value [#to_s, nil] anything stringable (everything in
      #   Ruby responds to +to_s+); +nil+ stays +nil+
      # @param strict [Boolean, nil] when true, refuse anything but a String,
      #   Symbol, Integer or +to_str+ object (a Float, BigDecimal or Rational
      #   is refused: its +to_s+ is +"0.12e2"+ / +"1/2"+, not the caller's text). Strict never changes
      #   what an accepted value becomes — it is still +value.to_s+.
      # @return [::String, nil] +nil+ when input is +nil+, otherwise +value.to_s+
      # @raise [TypeError] under +strict:+, for any other value
      def coerce(value, strict: false, **)
        return nil if value.nil?

        refuse_non_scalar!(value) if strict
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

      private

      # @param value [Object] a non-nil value
      # @return [void]
      # @raise [TypeError] unless +value+ is a String, Symbol, Integer, or
      #   responds to +to_str+; the message names the class, never the value
      #   (see Types::Time#coerce)
      def refuse_non_scalar!(value)
        return if value.is_a?(::String) || value.is_a?(::Symbol) || value.is_a?(::Integer)
        return if value.respond_to?(:to_str)

        raise ::TypeError, 'String fields with strict: true expect a String, Symbol, Integer ' \
                           "or an object responding to #to_str, got a #{value.class}"
      end
    end
  end
end
