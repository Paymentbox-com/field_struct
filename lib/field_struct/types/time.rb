# frozen_string_literal: true

require 'time'
require_relative 'base'

module FieldStruct
  module Types
    # Time type. Returns a +Time+ as-is, builds one from a +Date+ or
    # +DateTime+'s components, reads a String via +Time.parse+ (or +strptime+
    # when the field declares a +format:+), and refuses everything else.
    #
    # Per-field +format:+ option (String or Symbol-preset) controls both
    # parsing (strptime when input is a String) and serialization
    # (strftime via +as_json+).
    class Time < Base
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

      # @return [::String, nil]
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
      # against the value. ActiveSupport defines +String#to_time+, and it
      # returns +nil+ for a string with no time in it rather than raising — so
      # under Rails "not-a-time" was coerced to nil and reported VALID. The
      # probe is gone; +Time.parse+ and +Time.strptime+ behave the same with or
      # without ActiveSupport loaded.
      #
      # Cross-class conversion builds a Time from components rather than
      # calling +to_time+, which ActiveSupport redefines: under AS 7.2
      # +DateTime#to_time+ converts to the system-local zone and emits a
      # deprecation warning, while 8.x preserves the offset. Constructing from
      # parts gives the same instant and the same offset in all three
      # environments, which is what makes the behaviour host-independent rather
      # than merely documented.
      #
      # @param value [::String, ::Time, ::Date, ::DateTime, nil] +nil+ → +nil+;
      #   a String is read through +strptime+ when a +format:+ is set and
      #   +Time.parse+ otherwise; a +Time+ passes through; a +DateTime+, +Date+
      #   or Time-like value (ActiveSupport's TimeWithZone) is converted.
      #   Anything else is refused.
      # @param format [::String, nil] strptime/strftime format; +nil+ uses
      #   {.default_format} (which itself defaults to +nil+ = ISO-8601 path)
      # @return [::Time, nil]
      # @raise [ArgumentError] when a String cannot be parsed, or the value is
      #   not a String or a temporal object
      def coerce(value, format: self.class.default_format, **)
        return nil if value.nil?

        fmt = self.class.resolve_format(format)

        case value
        when ::String then parse_string(value, fmt)
        # ::DateTime before ::Date — DateTime is a subclass of Date, and only
        # this arm carries the time of day.
        when ::DateTime then time_from_datetime(value)
        when ::Date then ::Time.new(value.year, value.mon, value.mday)
        # A TimeWithZone matches here (AS overrides Time.===) but is NOT an
        # instance of ::Time, so it must be converted rather than passed
        # through — otherwise a :time field would store a TWZ.
        when ::Time then value.instance_of?(::Time) ? value : ::Time.at(value.to_r).getlocal(value.utc_offset)
        else
          # The class, never the value — see Types::Date#coerce.
          raise ArgumentError, "expected a String, Date, DateTime or Time, got #{value.class}"
        end
      end

      # @return [Class] the top-level +::Time+ class
      def ruby_type
        ::Time
      end

      private

      # @param value [::String] the raw string
      # @param format [::String, nil] strptime format, when the field declares one
      # @return [::Time]
      # @raise [ArgumentError] when the string cannot be read
      def parse_string(value, format)
        # Validated first, then handed to the stdlib parser: the checks decide
        # what is ACCEPTABLE, the stdlib still decides what the value IS, so
        # the two can't drift apart. See {TemporalParser} for the three rules.
        if format
          TemporalParser.strptime_parts(value, format)
          return ::Time.strptime(value, format)
        end

        TemporalParser.parse_parts(value)
        ::Time.parse(value)
      end

      # @param value [::DateTime] the value to convert
      # @return [::Time] the same instant, at the same offset, sub-second
      #   precision preserved
      def time_from_datetime(value)
        ::Time.new(value.year, value.mon, value.mday, value.hour, value.min,
          value.sec + value.sec_fraction, value.zone)
      end
    end
  end
end
