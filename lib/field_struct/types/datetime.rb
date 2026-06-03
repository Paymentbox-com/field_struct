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
      # Native options: a +format:+ strftime/strptime String (or Symbol
      # preset; see {.presets}) and an +in:+ Array or Range of allowed values.
      #
      # @return [Hash{Symbol=>Hash}]
      def self.option_schema
        super.merge(
          format: option(type: [::String, ::Symbol], presets: presets.keys),
          in: option(type: [::Array, ::Range])
        )
      end

      # @return [::String, nil] field-level strftime/strptime format; +nil+
      #   leaves the type using ISO-8601 in/out
      def self.default_format
        nil
      end

      # @return [Hash{::Symbol=>::String}] named presets for the +format:+ option
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

      # @param value [::DateTime, #to_datetime, ::String, nil] +nil+ → +nil+;
      #   a +String+ is parsed via +strptime+ when +format:+ is set,
      #   otherwise via +DateTime.parse+; anything responding to
      #   +to_datetime+ (Date, Time, etc.) is converted.
      # @param format [::String, nil] strptime/strftime format; +nil+ uses
      #   {.default_format} (which itself defaults to +nil+ = ISO-8601 path)
      # @return [::DateTime, nil]
      # @raise [ArgumentError] when a string cannot be parsed
      def coerce(value, format: self.class.default_format, **)
        return nil if value.nil?
        return ::DateTime.strptime(value, format) if value.is_a?(::String) && format
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
