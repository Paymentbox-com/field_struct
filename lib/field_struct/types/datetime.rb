# frozen_string_literal: true

require 'date'
require_relative 'base'

module FieldStruct
  module Types
    # DateTime type. Uses +to_datetime+ for anything that responds (Date,
    # Time, DateTime itself), and otherwise parses via +DateTime.parse+,
    # which raises +ArgumentError+ on garbage.
    class DateTime < Base
      # @param value [Object] raw input
      # @param _options [Hash] unused
      # @return [DateTime, nil]
      # @raise [ArgumentError] when a string cannot be parsed
      def coerce(value, _options = {})
        return nil if value.nil?
        return value.to_datetime if value.respond_to?(:to_datetime)

        ::DateTime.parse(value.to_s)
      end

      # @return [Class] the top-level +::DateTime+ class
      def ruby_type
        ::DateTime
      end
    end
  end
end
