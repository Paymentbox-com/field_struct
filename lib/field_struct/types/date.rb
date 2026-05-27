# frozen_string_literal: true

require 'date'
require_relative 'base'

module FieldStruct
  module Types
    # Date type. Returns Date as-is, converts DateTime/Time/anything that
    # responds to +to_date+ down to a plain Date, and otherwise parses
    # +Date.parse(value.to_s)+ — which raises +ArgumentError+ on garbage.
    class Date < Base
      # @param value [Object] raw input
      # @param _options [Hash] unused
      # @return [Date, nil]
      # @raise [ArgumentError] when a string cannot be parsed
      def coerce(value, _options = {})
        return nil if value.nil?
        return value if value.instance_of?(::Date)
        return value.to_date if value.respond_to?(:to_date)

        ::Date.parse(value.to_s)
      end

      # @return [Class] the top-level +::Date+ class
      def ruby_type
        ::Date
      end
    end
  end
end
