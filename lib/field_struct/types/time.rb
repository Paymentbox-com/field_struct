# frozen_string_literal: true

require 'time'
require_relative 'base'

module FieldStruct
  module Types
    # Time type. Returns Time as-is, converts Date/DateTime via +to_time+,
    # and parses anything stringy via +Time.parse+ — which raises
    # +ArgumentError+ on garbage.
    #
    # Per-field +format:+ option (String or Symbol-preset) controls both
    # parsing (strptime when input is a String) and serialization
    # (strftime via +as_json+).
    class Time < Base
      # @return [String, nil]
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
      # @return [Time, nil]
      # @raise [ArgumentError] when a string cannot be parsed
      def coerce(value, options = {})
        return nil if value.nil?

        fmt = options[:format] || self.class.default_format
        if value.is_a?(::String) && fmt
          return ::Time.strptime(value, fmt)
        end
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
