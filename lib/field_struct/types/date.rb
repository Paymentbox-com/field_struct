# frozen_string_literal: true

require 'date'
require_relative 'base'

module FieldStruct
  module Types
    # Date type. Returns Date as-is, converts DateTime/Time/anything that
    # responds to +to_date+ down to a plain Date, and otherwise parses
    # +Date.parse(value.to_s)+ — which raises +ArgumentError+ on garbage.
    #
    # Per-field +format:+ option (String or Symbol-preset) controls both
    # parsing (strptime when input is a String) and serialization
    # (strftime when emitting via +as_json+ / +to_json+). When no format
    # is set, the type uses +Date.parse+ for input and ISO-8601 for output.
    class Date < Base
      # @return [String, nil] field-level strftime/strptime format; +nil+
      #   leaves the type using ISO-8601 in/out
      def self.default_format
        nil
      end

      # @return [Hash{Symbol=>String}] named presets for the +format:+ option
      def self.presets
        {
          iso8601: '%Y-%m-%d',
          us: '%m/%d/%Y',
          eu: '%d/%m/%Y'
        }
      end

      def self.resolve_options(options)
        TimeFormatResolver.call(options, presets)
      end

      # @param value [Object] raw input
      # @param options [Hash] supports +:format+ (strptime string)
      # @return [Date, nil]
      # @raise [ArgumentError] when a string cannot be parsed
      def coerce(value, options = {})
        return nil if value.nil?
        return value if value.instance_of?(::Date)
        return value.to_date if value.respond_to?(:to_date)

        fmt = options[:format] || self.class.default_format
        return ::Date.strptime(value.to_s, fmt) if fmt

        ::Date.parse(value.to_s)
      end

      # @return [Class] the top-level +::Date+ class
      def ruby_type
        ::Date
      end
    end
  end
end
