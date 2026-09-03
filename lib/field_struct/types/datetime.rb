# frozen_string_literal: true

require 'date'
require_relative 'base'

module FieldStruct
  module Types
    # DateTime type. Returns a +DateTime+ as-is, builds one from a +Date+ or
    # +Time+'s components, reads a String via +DateTime.parse+ (or +strptime+
    # when the field declares a +format:+), and refuses everything else.
    #
    # Per-field +format:+ option (String or Symbol-preset) controls both
    # parsing (strptime when input is a String) and serialization
    # (strftime via +as_json+).
    class DateTime < Base
      # Native options: a +format:+ strftime/strptime String (or Symbol
      # preset; see {.presets}) and an +in:+ Array or Range of allowed values.
      #
      # @return [::Hash{::Symbol => ::Hash{::Symbol => Object}}]
      def self.own_option_schema
        {
          format: option(type: [::String, ::Symbol], presets: presets.keys),
          in: option(type: [::Array, ::Range])
        }
      end

      # @return [::String, nil] field-level strftime/strptime format; +nil+
      #   leaves the type using ISO-8601 in/out
      def self.default_format
        nil
      end

      # Named presets for the +format:+ option.
      #
      # +:iso8601+ is an {Rfc3339Format} rather than a strftime String: +%z+
      # renders +\+0000+, which RFC 3339 rejects, and no strftime string can
      # express optional fractional seconds. The interchange and display
      # presets stay strftime-based.
      #
      # @return [Hash{::Symbol=>Object}]
      def self.presets
        {
          iso8601: Rfc3339Format.timestamp,
          rfc2822: '%a, %d %b %Y %H:%M:%S %z',
          db: '%Y-%m-%d %H:%M:%S'
        }
      end

      # Resolve a Symbol +format:+ preset (see {.presets}) to its strftime
      # string at field-declaration time; other forms pass through.
      def self.resolve_options(options)
        TimeFormatResolver.call(options, presets)
      end

      # Resolve a declared +format:+ (a Symbol preset name or a strftime
      # String) into the String that {#coerce} and JSON rendering actually
      # use. Declarations are stored exactly as written, so this is where a
      # preset name becomes usable. See {TimeFormatResolver}.
      #
      # @param format [::String, ::Symbol, nil] the format as declared
      # @return [::String, nil] +nil+ when the field declares no format
      # @raise [ArgumentError] when a Symbol names no preset in {.presets}
      def self.resolve_format(format)
        TimeFormatResolver.resolve(format, presets)
      end

      # Dispatch is on explicit stdlib classes, never on a +respond_to?+ probe
      # against the value: ActiveSupport defines +String#to_datetime+, so a
      # probe that is false on plain Ruby is TRUE under Rails.
      # +DateTime.parse+ and +DateTime.strptime+ are not redefined by
      # ActiveSupport. See {Types::Time#coerce} for why cross-class conversion
      # is built from components rather than +to_datetime+.
      #
      # @param value [::String, ::DateTime, ::Date, ::Time, nil] +nil+ → +nil+;
      #   a String is read through +strptime+ when a +format:+ is set and
      #   +DateTime.parse+ otherwise; a +DateTime+ passes through; a +Date+
      #   becomes midnight and a +Time+ (including ActiveSupport's
      #   TimeWithZone) keeps its instant and offset. Anything else is refused.
      # @param format [::String, nil] strptime/strftime format; +nil+ uses
      #   {.default_format} (which itself defaults to +nil+ = ISO-8601 path)
      # @return [::DateTime, nil]
      # @raise [ArgumentError] when a String cannot be parsed, or the value is
      #   not a String or a temporal object
      def coerce(value, format: self.class.default_format, **)
        return nil if value.nil?

        fmt = self.class.resolve_format(format)

        case value
        when ::String then parse_string(value, fmt)
        # ::DateTime before ::Date — DateTime is a subclass of Date.
        when ::DateTime then value
        when ::Date then ::DateTime.new(value.year, value.mon, value.mday)
        # ActiveSupport::TimeWithZone matches here too (AS overrides Time.===)
        # and answers every reader this uses.
        when ::Time then datetime_from_time(value)
        else
          # The class, never the value — see Types::Date#coerce.
          raise ArgumentError, "expected a String, Date, DateTime or Time, got #{value.class}"
        end
      end

      # @return [Class] the top-level +::DateTime+ class
      def ruby_type
        ::DateTime
      end

      private

      # @param value [::String] the raw string
      # @param format [::String, nil] strptime format, when the field declares one
      # @return [::DateTime]
      # @raise [ArgumentError] when the string cannot be read
      def parse_string(value, format)
        # Validated first, then handed to the stdlib parser: the checks decide
        # what is ACCEPTABLE, the stdlib still decides what the value IS, so
        # the two can't drift apart. See {TemporalParser} for the three rules.
        if format.is_a?(Rfc3339Format)
          parts = format.parse(value)
          return ::DateTime.new(parts[:year], parts[:mon], parts[:mday], parts[:hour], parts[:min],
            parts[:sec] + parts[:sec_fraction], ::Kernel.Rational(parts[:offset], 86_400))
        end

        if format
          TemporalParser.strptime_parts(value, format)
          return ::DateTime.strptime(value, format)
        end

        TemporalParser.parse_parts(value)
        ::DateTime.parse(value)
      end

      # @param value [::Time] the value to convert
      # @return [::DateTime] the same instant, at the same offset, sub-second
      #   precision preserved
      def datetime_from_time(value)
        ::DateTime.new(value.year, value.mon, value.mday, value.hour, value.min,
          value.sec + ::Kernel.Rational(value.nsec, 1_000_000_000),
          ::Kernel.Rational(value.utc_offset, 86_400))
      end
    end
  end
end
