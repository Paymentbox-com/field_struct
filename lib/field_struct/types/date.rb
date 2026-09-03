# frozen_string_literal: true

require 'date'
require_relative 'base'

module FieldStruct
  module Types
    # Date type. Returns a +Date+ as-is, narrows a +DateTime+ or +Time+ down
    # to a plain Date, reads a String via +Date.parse+ (or +strptime+ when the
    # field declares a +format:+), and refuses everything else.
    #
    # Per-field +format:+ option (String or Symbol-preset) controls both
    # parsing (strptime when input is a String) and serialization
    # (strftime when emitting via +as_json+ / +to_json+). When no format
    # is set, the type uses +Date.parse+ for input and ISO-8601 for output.
    class Date < Base
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

      # @return [Hash{::Symbol=>::String}] named presets for the +format:+ option
      def self.presets
        {
          iso8601: '%Y-%m-%d',
          us: '%m/%d/%Y',
          eu: '%d/%m/%Y'
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
      # against the value. ActiveSupport defines +String#to_date+, so a probe
      # that is false on plain Ruby is TRUE under Rails, and the type would take
      # a different branch there than it does in its own suite — which is
      # exactly how a declared +format:+ came to be ignored under Rails while
      # every spec here passed. +Date.parse+ and +Date.strptime+ are not
      # redefined by ActiveSupport, so dispatching on them gives one behaviour
      # in both worlds.
      #
      # @param value [::String, ::Date, ::DateTime, ::Time, nil] +nil+ → +nil+;
      #   a String is read through +strptime+ when a +format:+ is set and
      #   +Date.parse+ otherwise; a +Date+ passes through; a +DateTime+ or
      #   +Time+ (including ActiveSupport's TimeWithZone) is narrowed to a
      #   plain +Date+. Anything else is refused.
      # @param format [::String, nil] strptime/strftime format; +nil+ uses
      #   {.default_format} (which itself defaults to +nil+ = ISO-8601 path)
      # @return [::Date, nil]
      # @raise [ArgumentError] when a String cannot be parsed, or the value is
      #   not a String or a temporal object
      def coerce(value, format: self.class.default_format, **)
        return nil if value.nil?

        fmt = self.class.resolve_format(format)

        case value
        when ::String then parse_string(value, fmt)
        # ::DateTime is a ::Date, so this arm narrows both. A plain Date is
        # returned untouched; a DateTime is rebuilt as one.
        when ::Date then value.instance_of?(::Date) ? value : ::Date.new(value.year, value.mon, value.mday)
        # ActiveSupport::TimeWithZone lands here: AS overrides Time.=== so it
        # matches, even though it is not an instance of ::Time.
        when ::Time then ::Date.new(value.year, value.mon, value.mday)
        else
          # The class, never the value. FieldStruct wraps this as "could not be
          # coerced: <message>" and that string reaches API responses and audit
          # rows, so a value echoed here is a value published.
          raise ArgumentError, "expected a String, Date, DateTime or Time, got #{value.class}"
        end
      end

      # @return [Class] the top-level +::Date+ class
      def ruby_type
        ::Date
      end

      private

      # @param value [::String] the raw string
      # @param format [::String, nil] strptime format, when the field declares one
      # @return [::Date]
      # @raise [ArgumentError] when the string cannot be read
      def parse_string(value, format)
        # Validated first, then handed to the stdlib parser: the checks decide
        # what is ACCEPTABLE, the stdlib still decides what the value IS, so
        # the two can't drift apart. See {TemporalParser} for the three rules.
        if format
          TemporalParser.strptime_parts(value, format)
          return ::Date.strptime(value, format)
        end

        TemporalParser.parse_parts(value)
        ::Date.parse(value)
      end
    end
  end
end
