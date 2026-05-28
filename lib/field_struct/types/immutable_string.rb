# frozen_string_literal: true

require_relative 'string'

module FieldStruct
  module Types
    # Like {Types::String}, but the coerced value is frozen. Useful when
    # downstream code must not mutate a stored string.
    class ImmutableString < FieldStruct::Types::String
      # @param value [#to_s, nil] anything stringable; +nil+ stays +nil+
      # @return [::String, nil] frozen string, or +nil+ if input is +nil+
      def coerce(value, **)
        result = super
        result.nil? ? nil : result.dup.freeze
      end
    end
  end
end
