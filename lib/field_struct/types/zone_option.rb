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
    # Accepted values are +"UTC"+, fixed offsets +"±HH:MM"+ and IANA
    # Area/Location names (+"America/Denver"+). A fixed offset is the same all
    # year. A name is read through tzinfo's zone database, so a wall-clock time
    # gets the offset in force at that date and an instant (an epoch) the
    # offset in force at that instant. tzinfo is required only when a field
    # declares a name.
    #
    # Daylight-saving edges, for a name:
    #
    # - A wall-clock time the zone skips (02:30 on a spring-forward day) is
    #   refused, as a 30 February is: it names no instant. ActiveSupport moves
    #   it an hour forward instead; FieldStruct does not guess.
    # - A wall-clock time the zone repeats (01:30 on a fall-back day) is read
    #   at its daylight-time offset — the earlier instant — which is what
    #   ActiveSupport's TimeWithZone picks, so a Rails app sees the same answer.
    # - A +Date+ whose midnight the zone skips becomes the first moment of that
    #   day (01:00 in Santiago on its spring-forward day), as
    #   +Date#in_time_zone+ does.
    #
    # The value returned is a plain +::Time+ (or +::DateTime+) carrying the
    # offset, never a +TZInfo::TimeWithOffset+; it does not carry the zone
    # itself, so arithmetic on it keeps that offset rather than following DST.
    #
    # Refused: abbreviations and legacy aliases with no +/+ (+"MST"+ is a fixed
    # -07:00 in the database, not Mountain time with DST) and Rails' friendly
    # names (+"Mountain Time (US & Canada)"+), which only exist when
    # ActiveSupport is loaded and so would make a declaration valid in one
    # process and invalid in another (invariant 7).
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
      # @raise [ArgumentError] when +zone:+ is a String that is not +"UTC"+, a
      #   valid +±HH:MM+ offset or an IANA name in the zone database, or when
      #   no zone database can be found
      def self.validate!(type_name, options)
        zone = options[:zone]
        return options unless zone.is_a?(::String)
        return options if offset_seconds(zone)

        raise ArgumentError, refusal(type_name, zone) unless zone.include?('/')

        load_timezone(type_name, zone)
        options
      end

      # @param type_name [::String] the type's short name
      # @param zone [::String] the refused +zone:+
      # @return [::String] the declaration error, with a hint for the
      #   shape of +zone+
      def self.refusal(type_name, zone)
        hint = if zone.match?(/[ ()&]/)
                 'Rails zone names are an ActiveSupport alias, not IANA names, and exist only when ' \
                   'ActiveSupport is loaded: use the name it maps to (ActiveSupport::TimeZone::MAPPING[name]).'
               elsif zone.include?('/')
                 'The zone database has no zone by that name.'
               else
                 'Use an Area/Location name: abbreviations and aliases are refused ("MST" is a fixed ' \
                   '-07:00 in the zone database, not Mountain time with DST), and an offset needs its colon.'
               end
        "zone: on #{type_name} expects an IANA name like \"America/Denver\", \"UTC\" or a UTC offset " \
          "like \"-06:00\", got #{zone.inspect}. #{hint}"
      end

      # Look up (and cache) a zone by name, requiring tzinfo on first use.
      #
      # @param type_name [::String] the type's short name, for the message
      # @param zone [::String] an IANA name
      # @return [Object] the +TZInfo::Timezone+
      # @raise [ArgumentError] when the name is unknown, or no zone data is
      #   installed
      def self.load_timezone(type_name, zone)
        require 'tzinfo'
        @timezones ||= {}
        @timezones[zone] ||= ::TZInfo::Timezone.get(zone)
      rescue ::TZInfo::InvalidTimezoneIdentifier
        raise ArgumentError, refusal(type_name, zone)
      rescue ::TZInfo::DataSourceNotFound
        raise ArgumentError,
          "zone: on #{type_name} names #{zone.inspect}, but no time zone data was found on this system. " \
          'Add the tzinfo-data gem to your Gemfile (or install the OS zoneinfo package).'
      end

      # @param zone [::String] an IANA name {.validate!} accepted
      # @return [Object] the cached +TZInfo::Timezone+
      # @raise [ArgumentError] for a name {.validate!} would refuse, when a
      #   type is called directly with one
      def self.timezone(zone)
        cached = @timezones && @timezones[zone]
        return cached if cached
        raise ArgumentError, refusal('the field', zone) unless zone.include?('/')

        load_timezone('the field', zone)
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

      # Read a zone-less String as a wall-clock time in +zone+.
      #
      # @param value [::String] a string {.zoneless?} accepted
      # @param format [::String, nil] a resolved strptime format, or +nil+ for
      #   the no-format path (which has already required a whole day)
      # @param zone [::String] a declared +zone:+
      # @param parts [::Hash{::Symbol => Object}] the fragments the string
      #   parsed to; an epoch (+%s+ / +%Q+) shows up as +:seconds+
      # @return [::Time] at +zone+'s offset (+utc?+ for +"UTC"+)
      # @raise [ArgumentError] when +zone+ is a name and the wall-clock time
      #   falls in a gap the zone skips
      def self.time_at(value, format, zone, parts)
        offset = offset_seconds(zone)
        return named_time_at(value, format, timezone(zone), parts) if offset.nil?

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

      # {.time_at} for an IANA name: the offset depends on the date.
      #
      # @param value [::String] the zone-less string
      # @param format [::String, nil] a resolved strptime format, or +nil+
      # @param timezone [Object] a +TZInfo::Timezone+
      # @param parts [::Hash{::Symbol => Object}] the parsed fragments
      # @return [::Time]
      def self.named_time_at(value, format, timezone, parts)
        # An epoch is an instant already: keep it, at the offset of that instant.
        return in_zone(::Time.strptime(value, format), timezone) if format && parts.key?(:seconds)

        wall = if format
                 # The offset in force NOW only decides which day "today" is when
                 # the format omits the date; the wall clock is resolved below.
                 now = offset_text(timezone.period_for(::Time.now).observed_utc_offset)
                 ::Time.strptime("#{value} #{now}", "#{format} %z")
               else
                 ::DateTime.parse(value)
               end
        sec = wall.sec + (wall.is_a?(::DateTime) ? wall.sec_fraction : wall.subsec)
        local(timezone, [wall.year, wall.mon, wall.mday, wall.hour, wall.min, sec])
      end

      # A wall-clock time in a named zone.
      #
      # @param timezone [Object] a +TZInfo::Timezone+
      # @param civil [::Array<::Numeric>] year, month, day, hour, minute and
      #   seconds (with any fraction)
      # @return [::Time] at the offset in force at that wall-clock time
      # @raise [ArgumentError] when the zone skips that wall-clock time
      def self.local(timezone, civil)
        # tzinfo reads the components and ignores the offset of the Time it is
        # given. In an overlap, dst = true and the block pick what
        # ActiveSupport's TimeZone#period_for_local picks.
        period = timezone.period_for_local(::Time.utc(*civil), true, &:last)
        ::Time.new(*civil, period.observed_utc_offset)
      rescue ::TZInfo::PeriodNotFound
        # The input is not echoed — see Types::Time#coerce. The zone is the
        # declaration, not the value.
        raise ArgumentError,
          "names a local time that does not exist in #{timezone.identifier} (skipped by a daylight-saving change)"
      end

      # @param time [::Time] an instant
      # @param timezone [Object] a +TZInfo::Timezone+
      # @return [::Time] the same instant at the zone's offset at that instant
      def self.in_zone(time, timezone)
        time.getlocal(timezone.period_for(time).observed_utc_offset)
      end

      # @param value [::Date] a plain Date
      # @param zone [::String] a declared +zone:+
      # @return [::Time] midnight at +zone+'s offset — for a name, the first
      #   moment of that day
      def self.midnight(value, zone)
        offset = offset_seconds(zone)
        return named_midnight(value, timezone(zone)) if offset.nil?

        time = ::Time.new(value.year, value.mon, value.mday, 0, 0, 0, offset)
        zone == 'UTC' ? time.utc : time
      end

      # @param value [::Date] a plain Date
      # @param timezone [Object] a +TZInfo::Timezone+
      # @return [::Time] the first moment of that day in the zone
      def self.named_midnight(value, timezone)
        local(timezone, [value.year, value.mon, value.mday, 0, 0, 0])
      rescue ArgumentError
        # The zone skips midnight: the day starts where the gap ends, the
        # instant midnight would be at the offset in force just before it.
        before = timezone.period_for_local(::Time.utc(value.year, value.mon, value.mday) - 1, true, &:last)
        in_zone(::Time.utc(value.year, value.mon, value.mday) - before.observed_utc_offset, timezone)
      end

      # @param seconds [::Integer] seconds east of UTC
      # @return [::String] +"+HH:MM"+ / +"-HH:MM"+
      def self.offset_text(seconds)
        format('%s%02d:%02d', seconds.negative? ? '-' : '+', seconds.abs / 3600, (seconds.abs % 3600) / 60)
      end
    end
  end
end
