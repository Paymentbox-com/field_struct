# frozen_string_literal: true

require 'date'
require_relative 'base'

module FieldStruct
  module Types
    # DateTime type. Uses +to_datetime+ for anything that responds (Date,
    # Time, DateTime itself), and otherwise parses via +DateTime.parse+,
    # which raises +ArgumentError+ on garbage.
    #
    # Per-field +format:+ option (String or Symbol-preset) controls both
    # parsing (strptime when input is a String) and serialization
    # (strftime via +as_json+).
    class DateTime < Base
      # @return [String, nil] field-level strftime/strptime format; +nil+
      #   leaves the type using ISO-8601 in/out
      def self.default_format
        nil
      end

      # @return [Hash{Symbol=>String}] named presets for the +format:+ option
      def self.presets
        {
          iso8601: '%Y-%m-%dT%H:%M:%S%z',
          rfc2822: '%a, %d %b %Y %H:%M:%S %z',
          db: '%Y-%m-%d %H:%M:%S'
        }
      end

      def self.resolve_options(options)
        TimeFormatResolver.call(options, presets)
      end

      # @param value [Object] raw input
      # @param options [Hash] supports +:format+ (strptime string)
      # @return [DateTime, nil]
      # @raise [ArgumentError] when a string cannot be parsed
      def coerce(value, options = {})
        return nil if value.nil?

        fmt = options[:format] || self.class.default_format
        if value.is_a?(::String) && fmt
          return ::DateTime.strptime(value, fmt)
        end
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
