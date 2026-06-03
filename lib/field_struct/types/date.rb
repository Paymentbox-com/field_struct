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
          iso8601: '%Y-%m-%d',
          us: '%m/%d/%Y',
          eu: '%d/%m/%Y'
        }
      end

      def self.resolve_options(options)
        TimeFormatResolver.call(options, presets)
      end

      # @param value [::Date, #to_date, ::String, nil] +nil+ → +nil+; a +Date+
      #   passes through; anything responding to +to_date+ (DateTime,
      #   Time, ActiveSupport's TimeWithZone, etc.) is converted; a
      #   String is parsed via +strptime+ if a +format:+ is set,
      #   otherwise +Date.parse+. Anything else falls through to
      #   +Date.parse(value.to_s)+ — which raises ArgumentError.
      # @param format [::String, nil] strptime/strftime format; +nil+ uses
      #   {.default_format} (which itself defaults to +nil+ = ISO-8601 path)
      # @return [::Date, nil]
      # @raise [ArgumentError] when a string cannot be parsed
      def coerce(value, format: self.class.default_format, **)
        return nil if value.nil?
        return value if value.instance_of?(::Date)
        return value.to_date if value.respond_to?(:to_date)
        return ::Date.strptime(value.to_s, format) if format

        ::Date.parse(value.to_s)
      end

      # @return [Class] the top-level +::Date+ class
      def ruby_type
        ::Date
      end
    end
  end
end
