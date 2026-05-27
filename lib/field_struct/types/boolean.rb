# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Boolean type. Accepts the literal +true+/+false+, the strings
    # "true"/"false" (case-insensitive), and the integers/strings 1/0.
    # Anything else raises +ArgumentError+.
    #
    # Ruby has no Boolean class, so {#ruby_type} returns the pair
    # +[TrueClass, FalseClass]+. The (deferred) RBS generator can map
    # that to the +bool+ alias.
    class Boolean < Base
      TRUTHY_STRINGS = %w[true 1].freeze
      FALSEY_STRINGS = %w[false 0].freeze

      # @param value [Object] raw input
      # @param _options [Hash] unused
      # @return [Boolean, nil]
      # @raise [ArgumentError] when the value can't be mapped to true/false
      def coerce(value, _options = {})
        return nil if value.nil?
        return value if value == true || value == false # rubocop:disable Style/MultipleComparison
        return true if value == 1
        return false if value == 0

        if value.is_a?(::String)
          downcased = value.downcase
          return true if TRUTHY_STRINGS.include?(downcased)
          return false if FALSEY_STRINGS.include?(downcased)
        end

        raise ArgumentError, "cannot coerce #{value.inspect} to boolean"
      end

      # @return [Array(Class, Class)] +[TrueClass, FalseClass]+
      def ruby_type
        [TrueClass, FalseClass]
      end
    end
  end
end
