# frozen_string_literal: true

require 'date'
require 'time'

module FieldStruct
  module Types
    # RFC 3339 — the profile of ISO 8601 that "ISO-8601" means in an API
    # contract, and what JSON Schema's +date-time+ refers to. This is what the
    # +:iso8601+ preset resolves to for {Date}, {Time} and {DateTime}.
    #
    # FieldStruct parses and renders it itself, for two reasons.
    #
    # **It cannot be written as a strftime string.** +%z+ renders +\+0000+,
    # which RFC 3339 rejects — so the preset named +iso8601+ used to emit a
    # value its own documented format would refuse. And no strftime string can
    # express "optional fractional seconds", which most JSON APIs emit.
    #
    # **The stdlib helpers disagree with each other.** Routing +Time+ through
    # +Time.iso8601+ and +DateTime+ through +DateTime.iso8601+ would give the
    # same declared preset two different contracts:
    #
    #     Time.iso8601('2026-02-30T10:30:00Z')      # => 2026-03-02 10:30 UTC
    #     DateTime.iso8601('2026-02-30T10:30:00Z')  # => refused
    #     Time.iso8601('2026-07-03T10:30Z')         # => refused
    #     DateTime.iso8601('2026-07-03T10:30Z')     # => accepted
    #     DateTime.iso8601('10:30:00Z')             # => TODAY at 10:30
    #
    # +Time.iso8601+ reading 30 February as 2 March is the exact
    # silently-wrong-day defect this release exists to remove, so it cannot be
    # the thing that implements the strict preset.
    #
    # The pattern is deliberately narrow: fixed-width fields, a mandatory
    # offset, and no week dates, ordinal dates or basic (unseparated) forms.
    # That narrowness is the point — it is what lets a caller replace a
    # hand-rolled +/\A\d{4}-\d{2}-\d{2}\z/+ with a declared format.
    class Rfc3339Format
      # Full-width calendar date. No sign, no week or ordinal forms.
      DATE = /\A(\d{4})-(\d{2})-(\d{2})\z/

      # Date, +T+, time to whole seconds, optional fraction, mandatory offset.
      # +±hhmm+ (no colon) is accepted on input because that is what FieldStruct
      # v0.9.0 emitted, and its own output has to keep parsing.
      TIMESTAMP = /\A(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})(\.\d+)?([Zz]|[+-]\d{2}:?\d{2})\z/

      # @return [Rfc3339Format] the date-only form, for {Types::Date}
      def self.date
        @date ||= new(:date)
      end

      # @return [Rfc3339Format] the timestamp form, for {Types::Time} and {Types::DateTime}
      def self.timestamp
        @timestamp ||= new(:timestamp)
      end

      # @return [::Symbol] +:date+ or +:timestamp+
      attr_reader :kind

      # @param kind [::Symbol] +:date+ or +:timestamp+
      def initialize(kind)
        @kind = kind
        freeze
      end

      # @return [::Symbol] the preset name this format implements
      def name
        :iso8601
      end

      # The accepted shape, as a regular expression whose source is also valid
      # as an ECMA pattern — so a schema or documentation generator can publish
      # the enforced contract rather than a prose approximation of it.
      #
      # @return [::Regexp]
      def pattern
        kind == :date ? DATE : TIMESTAMP
      end

      # @return [::String] the format's name, for error messages and inspection
      def to_s
        'iso8601 (RFC 3339)'
      end

      # Parse a String into date/time fragments.
      #
      # @param value [::String] the raw string
      # @return [::Hash{::Symbol => Object}] +:year+, +:mon+, +:mday+ and, for a
      #   timestamp, +:hour+, +:min+, +:sec+, +:sec_fraction+, +:offset+
      # @raise [ArgumentError] when the string is not RFC 3339, or names a day,
      #   hour, minute or second that cannot exist
      def parse(value)
        match = pattern.match(value)
        # The value is not echoed: FieldStruct wraps this as "could not be
        # coerced: <message>" and that string reaches API responses.
        raise ArgumentError, "expected an RFC 3339 #{kind}" if match.nil?

        kind == :date ? date_parts(match) : timestamp_parts(match)
      end

      # Render a coerced value back to RFC 3339.
      #
      # @param value [::Date, ::Time, ::DateTime] the coerced value
      # @return [::String]
      def render(value)
        # Date#iso8601, never Date#xmlschema: ActiveSupport redefines the
        # latter to emit a full timestamp, which would make output depend on
        # whether the host loaded Rails.
        return value.iso8601 if kind == :date

        "#{value.strftime("%Y-%m-%dT%H:%M:%S")}#{fraction_of(value)}#{offset_of(value)}"
      end

      private

      # @return [::Hash{::Symbol => ::Integer}]
      def date_parts(match)
        year, month, day = match.captures.map { |capture| Integer(capture, 10) }
        TemporalParser.ensure_real_day!({year: year, mon: month, mday: day})

        {year: year, mon: month, mday: day}
      end

      # @return [::Hash{::Symbol => Object}]
      def timestamp_parts(match)
        year, month, day, hour, minute, second = match.captures[0, 6].map { |c| Integer(c, 10) }
        TemporalParser.ensure_real_day!({year: year, mon: month, mday: day})
        # RFC 3339 permits a leap second, but Time rolls :60 into the next
        # minute and DateTime clamps it to :59 — the two stdlib classes give
        # different answers, so the strict preset refuses it rather than
        # picking one silently. Hour 24 is not RFC 3339 at all.
        raise ArgumentError, 'invalid time of day' if hour > 23 || minute > 59 || second > 59

        {
          year: year, mon: month, mday: day, hour: hour, min: minute, sec: second,
          sec_fraction: fraction_from(match.captures[6]),
          offset: offset_from(match.captures[7])
        }
      end

      # @return [::Rational] seconds after the whole second, exact
      def fraction_from(text)
        return 0r if text.nil?

        ::Kernel.Rational(text[1..], 10**(text.length - 1))
      end

      # @return [::Integer] seconds east of UTC
      # @raise [ArgumentError] when the offset names an hour or minute that
      #   cannot exist. Validated here rather than left to the constructors,
      #   because they disagree: +Time.new+ refuses a +25:00 offset while
      #   +DateTime.new+ accepts it and silently drops it to +00:00. A preset
      #   that means two different things depending on the field's type is the
      #   defect this class exists to avoid.
      def offset_from(text)
        return 0 if text.casecmp('Z').zero?

        sign = text.start_with?('-') ? -1 : 1
        digits = text[1..].delete(':')
        hours = Integer(digits[0, 2], 10)
        minutes = Integer(digits[2, 2], 10)
        raise ArgumentError, 'invalid UTC offset' if hours > 23 || minutes > 59

        sign * ((hours * 3600) + (minutes * 60))
      end

      # @return [::String] +".123"+, or empty when the value is on a whole second
      def fraction_of(value)
        subsec = value.is_a?(::Time) ? value.subsec : value.sec_fraction
        return '' if subsec.zero?

        # Exact digits from the Rational; %f would round to six places and
        # invent precision the value never carried.
        digits = (subsec.to_r * 1_000_000_000).to_i.to_s.rjust(9, '0').sub(/0+\z/, '')
        ".#{digits}"
      end

      # @return [::String] +"Z"+ for UTC, otherwise +"+HH:MM"+
      def offset_of(value)
        seconds = value.is_a?(::Time) ? value.utc_offset : (value.offset * 86_400).to_i
        return 'Z' if seconds.zero?

        sign = seconds.negative? ? '-' : '+'
        magnitude = seconds.abs
        format('%s%02d:%02d', sign, magnitude / 3600, (magnitude % 3600) / 60)
      end
    end
  end
end
