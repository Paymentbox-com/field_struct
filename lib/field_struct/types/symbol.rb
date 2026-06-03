# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Symbol type. Accepts an existing +Symbol+ or a +String+. Anything else
    # raises +TypeError+, which the parent's +coercion_policy+ handles.
    #
    # Empty symbols (+:""+) are unusual; like other scalar non-string types,
    # +missing?+ is nil-only — an empty symbol counts as present.
    class Symbol < Base
      # Native options: an +enum:+ Array of allowed values (symbols are
      # string-like, so they share +enum:+ with {Types::String}).
      #
      # @return [::Hash{::Symbol => ::Hash{::Symbol => Object}}]
      def self.option_schema
        super.merge(enum: option(type: [::Array]))
      end

      # @param value [Symbol, ::String, nil] anything else raises TypeError
      # @return [Symbol, nil]
      # @raise [TypeError] when input is not nil/Symbol/String
      def coerce(value, **)
        return nil if value.nil?
        return value if value.is_a?(::Symbol)
        return value.to_sym if value.is_a?(::String)

        raise ::TypeError, "expected Symbol or String, got #{value.class}"
      end

      # @return [Class] the top-level +::Symbol+ class
      def ruby_type
        ::Symbol
      end
    end
  end
end
