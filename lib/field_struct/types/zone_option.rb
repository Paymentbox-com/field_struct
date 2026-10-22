# frozen_string_literal: true

require 'date'
require 'time'

module FieldStruct
  module Types
    # The +zone:+ option shared by {Time} and {DateTime}.
    #
    # A zone-less string (+"2026-10-22 10:00"+) names a wall-clock time, not an
    # instant: by default +:time+ reads it in the *process* zone and +:datetime+
    # in UTC, so the same input meant different instants on different servers.
    # +zone:+ supplies the missing offset, so it means one instant everywhere.
    #
    # It only fills in an offset that is MISSING. A string with an offset, a
    # +Time+, a +DateTime+ (and ActiveSupport's TimeWithZone) keep theirs; a
    # +Date+, which has none, becomes midnight in the zone.
    #
    # Accepted values are +"UTC"+ and fixed offsets +"±HH:MM"+. IANA names
    # (+"America/Denver"+) are refused: the stdlib has no time zone database,
    # and accepting them only when a host happens to load ActiveSupport would
    # make a declaration valid in one process and invalid in another
    # (invariant 7). A DST-aware zone is a different contract — a per-instant
    # offset — and is left for a separate option.
    module ZoneOption
      # A fixed UTC offset, colon required.
      # @return [::Regexp]
      OFFSET = /\A([+-])(\d{2}):(\d{2})\z/

      # Refuse a +zone:+ value FieldStruct cannot read, at declaration. A
      # non-String is left for the option-shape check to report.
      #
      # @param type_name [::String] the type's short name, for the message
      # @param options [::Hash{::Symbol => Object, nil}] the per-field options
      # @return [::Hash{::Symbol => Object, nil}] the options, unchanged
      # @raise [ArgumentError] when +zone:+ is a String that is neither +"UTC"+
      #   nor a valid +±HH:MM+ offset
      def self.validate!(type_name, options)
        zone = options[:zone]
        return options unless zone.is_a?(::String)
        return options if offset_seconds(zone)

        raise ArgumentError,
          "zone: on #{type_name} expects \"UTC\" or a UTC offset like \"+00:00\" or \"-06:00\", " \
          "got #{zone.inspect}. Zone names such as \"America/Denver\" are not accepted: Ruby's " \
          'stdlib has no time zone database, so declare the fixed offset you mean.'
      end

      # @param zone [::String] a declared +zone:+
      # @return [::Integer, nil] seconds east of UTC, or +nil+ when +zone+ is
      #   not a value {.validate!} accepts
      def self.offset_seconds(zone)
        return 0 if zone == 'UTC'

        match = OFFSET.match(zone)
        return nil if match.nil?

        hours = Integer(match[2], 10)
        minutes = Integer(match[3], 10)
        return nil if hours > 23 || minutes > 59

        (match[1] == '-' ? -1 : 1) * ((hours * 3600) + (minutes * 60))
      end

      # Whether parsed fragments leave the offset to +zone:+.
      #
      # @param parts [::Hash{::Symbol => Object}] fragments from +Date._parse+
      #   or +Date._strptime+
      # @return [Boolean] +true+ when the string named no offset at all
      # @raise [ArgumentError] when the string names a zone the stdlib cannot
      #   turn into an offset (+"XYZ"+, +"America/Denver"+): +zone:+ never
      #   overrides a zone the input stated
      def self.zoneless?(parts)
        # An epoch (%s / %Q) is an instant already; {.time_at} keeps it and
        # only places it at the zone's offset, as it does for any other input.
        return false unless parts[:offset].nil?
        return true if parts[:zone].nil?

        # The input is not echoed — see Types::Time#coerce.
        raise ArgumentError, 'names a time zone with no fixed offset, which zone: does not override'
      end

      # Read a zone-less String as a wall-clock time at +zone+'s offset.
      #
      # @param value [::String] a string {.zoneless?} accepted
      # @param format [::String, nil] a resolved strptime format, or +nil+ for
      #   the no-format path (which has already required a whole day)
      # @param zone [::String] a declared +zone:+
      # @return [::Time] at +zone+'s offset (+utc?+ for +"UTC"+)
      def self.time_at(value, format, zone)
        offset = offset_seconds(zone)
        time = if format
                 # Appending the offset lets strptime do everything else as usual.
                 # Given an offset, it also fills a date the format omits from today
                 # *at that offset*, where plain strptime uses the process zone's
                 # today, and places an epoch (%s) at that offset.
                 ::Time.strptime("#{value} #{offset_text(offset)}", "#{format} %z")
               else
                 # DateTime.parse reads the wall clock with no zone involved, so a
                 # time the process zone skips for DST (02:30 on a spring-forward day)
                 # is kept rather than moved, as Time.parse would.
                 wall = ::DateTime.parse(value)
                 ::Time.new(wall.year, wall.mon, wall.mday, wall.hour, wall.min, wall.sec + wall.sec_fraction, offset)
               end
        zone == 'UTC' ? time.utc : time
      end

      # @param value [::Date] a plain Date
      # @param zone [::String] a declared +zone:+
      # @return [::Time] midnight at +zone+'s offset
      def self.midnight(value, zone)
        time = ::Time.new(value.year, value.mon, value.mday, 0, 0, 0, offset_seconds(zone))
        zone == 'UTC' ? time.utc : time
      end

      # @param seconds [::Integer] seconds east of UTC
      # @return [::String] +"+HH:MM"+ / +"-HH:MM"+
      def self.offset_text(seconds)
        format('%s%02d:%02d', seconds.negative? ? '-' : '+', seconds.abs / 3600, (seconds.abs % 3600) / 60)
      end
    end
  end
end
