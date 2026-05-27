# frozen_string_literal: true

require 'time'
require_relative 'base'

module FieldStruct
  module Types
    # Time type. Returns Time as-is, converts Date/DateTime via +to_time+,
    # and parses anything stringy via +Time.parse+ — which raises
    # +ArgumentError+ on garbage.
    class Time < Base
      # @param value [Object] raw input
      # @param _options [Hash] unused
      # @return [Time, nil]
      # @raise [ArgumentError] when a string cannot be parsed
      def coerce(value, _options = {})
        return nil if value.nil?
        return value.to_time if value.respond_to?(:to_time)

        ::Time.parse(value.to_s)
      end

      # @return [Class] the top-level +::Time+ class
      def ruby_type
        ::Time
      end
    end
  end
end
