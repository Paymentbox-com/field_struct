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
      # preset; see {.presets}), an +in:+ Array or Range of allowed values,
      # and a +zone:+ String (+"UTC"+ or +"±HH:MM"+; see {ZoneOption}).
      #
      # @return [::Hash{::Symbol => ::Hash{::Symbol => Object}}]
      def self.own_option_schema
        {
          format: option(type: [::String, ::Symbol], presets: presets.keys),
          in: option(type: [::Array, ::Range]),
          zone: option(type: [::String])
        }
      end

      # @return [::String, nil]
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

      # Validate a Symbol +format:+ preset (see {.presets}) and a +zone:+
      # (see {ZoneOption}) at field-declaration time.
      #
      # @param options [::Hash{::Symbol => Object, nil}] the per-field options
      # @return [::Hash{::Symbol => Object, nil}] the options, unchanged
      # @raise [ArgumentError] on an unknown preset or an unreadable +zone:+
      def self.resolve_options(options)
        ZoneOption.validate!('Time', TimeFormatResolver.call(options, presets))
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
      # @param zone [::String, nil] +"UTC"+ or +"±HH:MM"+: the offset for a
      #   String that names none, and for a +Date+'s midnight. Input carrying
      #   its own offset keeps it. +nil+ means the process zone. See {ZoneOption}.
      # @return [::Time, nil]
      # @raise [ArgumentError] when a String cannot be parsed, or the value is
      #   not a String or a temporal object
      def coerce(value, format: self.class.default_format, zone: nil, **)
        return nil if value.nil?

        fmt = self.class.resolve_format(format)

        case value
        when ::String then parse_string(value, fmt, zone)
        # ::DateTime before ::Date — DateTime is a subclass of Date, and only
        # this arm carries the time of day.
        when ::DateTime then time_from_datetime(value)
        when ::Date then zone ? ZoneOption.midnight(value, zone) : ::Time.new(value.year, value.mon, value.mday)
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
      # @param zone [::String, nil] the field's +zone:+, if declared
      # @return [::Time]
      # @raise [ArgumentError] when the string cannot be read
      def parse_string(value, format, zone)
        # Validated first, then handed to the stdlib parser: the checks decide
        # what is ACCEPTABLE, the stdlib still decides what the value IS, so
        # the two can't drift apart. See {TemporalParser} for the three rules.
        if format.is_a?(Rfc3339Format)
          parts = format.parse(value)
          return ::Time.new(parts[:year], parts[:mon], parts[:mday], parts[:hour], parts[:min],
            parts[:sec] + parts[:sec_fraction], parts[:offset])
        end

        if format
          parts = TemporalParser.strptime_parts(value, format)
          return ZoneOption.time_at(value, format, zone) if zone && ZoneOption.zoneless?(parts)

          return ::Time.strptime(value, format)
        end

        parts = TemporalParser.parse_parts(value)
        return ZoneOption.time_at(value, nil, zone) if zone && ZoneOption.zoneless?(parts)

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
