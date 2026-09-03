# frozen_string_literal: true

require 'date'

module FieldStruct
  module Types
    # Shared String-parsing rules for {Date}, {Time} and {DateTime}.
    #
    # Three rules the stdlib parsers leave to their caller. Each of them is a
    # case where the stdlib answers a question it was not asked, confidently.
    #
    # **Anchoring.** +strptime+ matches a PREFIX and discards the rest.
    # +Date.strptime('2026-07-031', '%Y-%m-%d')+ returns the 3rd and throws the
    # trailing +1+ away; +'2026-07-03T10:30:00+0000-NONSENSE'+ parses clean
    # under the +iso8601+ preset. A declared +format:+ is a contract about the
    # whole string, so anything left over is refused. (Leading whitespace needs
    # no rule — +Date._strptime+ already returns +nil+ for it.)
    #
    # **Civil validity.** +Date.strptime+ and +DateTime.strptime+ refuse the
    # 30th of February. +Time+ does not: +Time.parse+, +Time.strptime+ and
    # +Time.new+ all roll it forward to 2 March and say nothing. All three
    # types refuse it here.
    #
    # **Completeness.** With no declared format the stdlib parsers fill in
    # whatever the string omits, from *today*: +Time.parse('10:30')+ is today
    # at 10:30, +'July'+ is the 1st of July this year, +'12'+ is the 12th of
    # this month. A value whose meaning depends on when it was parsed is not a
    # value, so a string with no declared format must name a whole day.
    #
    # Anchoring is trailing-junk rejection and nothing more. Widths, sign and
    # case stay strptime-lenient for a hand-written format: +%m+ and +%d+
    # accept one or two digits, which is strptime's contract rather than a
    # defect. Strictness for the built-in presets is a separate concern.
    module TemporalParser
      # Validate a String against a declared format.
      #
      # @param value [::String] the raw string
      # @param format [::String] a resolved strftime/strptime format
      # @return [::Hash{::Symbol => Object}] the parsed fragments
      # @raise [ArgumentError] when the string does not match the format, has
      #   characters left over, or names a day that does not exist
      def self.strptime_parts(value, format)
        parts = ::Date._strptime(value, format)
        raise ArgumentError, "does not match format #{format.inspect}" if parts.nil?

        if parts.key?(:leftover)
          raise ArgumentError,
            "does not match format #{format.inspect} — unexpected trailing characters"
        end

        ensure_real_day!(parts)
        parts
      end

      # Validate a String with no declared format.
      #
      # @param value [::String] the raw string
      # @return [::Hash{::Symbol => Object}] the parsed fragments
      # @raise [ArgumentError] when the string names only part of a day, or a
      #   day that does not exist
      def self.parse_parts(value)
        parts = ::Date._parse(value)
        ensure_whole_day!(parts)
        ensure_real_day!(parts)
        parts
      end

      # @param parts [::Hash{::Symbol => Object}] fragments from +Date._parse+
      # @return [void]
      # @raise [ArgumentError] when year, month or day is missing
      def self.ensure_whole_day!(parts)
        return if parts[:year] && parts[:mon] && parts[:mday]

        # The value is deliberately not echoed: FieldStruct wraps this as
        # "could not be coerced: <message>" and that string reaches API
        # responses and audit rows.
        raise ArgumentError, 'expected a date with a year, a month and a day'
      end

      # @param parts [::Hash{::Symbol => Object}] fragments from +Date._parse+
      #   or +Date._strptime+
      # @return [void]
      # @raise [ArgumentError] when the fragments name a day that never existed
      def self.ensure_real_day!(parts)
        year, month, day = parts.values_at(:year, :mon, :mday)
        return if year.nil? || month.nil? || day.nil?
        return if ::Date.valid_civil?(year, month, day)

        raise ArgumentError, 'invalid date'
      end
    end
  end
end
