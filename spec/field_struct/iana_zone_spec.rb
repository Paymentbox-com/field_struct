# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'tzinfo'

# zone: with an IANA name. A fixed offset (zone_option_spec.rb) is the same
# offset all year; "America/Denver" is -06:00 in July and -07:00 in January, so
# a zone-less string is read as the wall clock in that zone ON THAT DATE. The
# zone database is tzinfo's, loaded only when a field declares a name.
RSpec.describe 'zone: with an IANA name' do
  # Every example runs under three process zones (one with DST, one without,
  # and UTC): the answer must not depend on the server.
  process_zones = %w[America/Denver Asia/Tokyo UTC].freeze

  def with_process_zone(zone)
    saved = ENV.fetch('TZ', nil)
    ENV['TZ'] = zone
    yield
  ensure
    ENV['TZ'] = saved
  end

  define_method(:under_each_zone) do |&block|
    process_zones.map { |zone| with_process_zone(zone) { block.call } }
  end

  let(:klass) do
    Class.new(FieldStruct::Base) do
      optional :at, :time, zone: 'America/Denver'
      optional :stamp, :datetime, zone: 'America/Denver'
      optional :db_at, :time, format: :db, zone: 'America/Denver'
      optional :db_stamp, :datetime, format: :db, zone: 'America/Denver'
      optional :epoch_at, :time, format: '%s', zone: 'America/Denver'
      optional :epoch_stamp, :datetime, format: '%s', zone: 'America/Denver'
      optional :chile, :time, zone: 'America/Santiago'
    end
  end

  def described(value)
    offset = value.is_a?(DateTime) ? (value.offset * 86_400).to_i : value.utc_offset
    [value.class, value.year, value.mon, value.mday, value.hour, value.min, value.sec, offset]
  end

  describe 'a zone-less string' do
    it 'is read at the zone offset in force on that date (DST-correct), on every server' do
      answers = under_each_zone do
        summer = klass.new(at: '2026-07-01 10:00', stamp: '2026-07-01 10:00')
        winter = klass.new(at: '2026-01-15 10:00', stamp: '2026-01-15 10:00')
        [summer.at, summer.stamp, winter.at, winter.stamp].map { |value| described(value) }
      end
      expect(answers.uniq).to eq([[[Time, 2026, 7, 1, 10, 0, 0, -21_600], [DateTime, 2026, 7, 1, 10, 0, 0, -21_600],
                                   [Time, 2026, 1, 15, 10, 0, 0, -25_200], [DateTime, 2026, 1, 15, 10, 0, 0, -25_200]]])
    end

    it 'returns a plain Time, not a TZInfo::TimeWithOffset' do
      at = klass.new(at: '2026-07-01 10:00').at
      expect(at).to be_instance_of(Time)
      expect(at.utc?).to be(false)
    end

    it 'keeps sub-second precision' do
      expect(klass.new(at: '2026-07-01 10:00:30.25').at.subsec).to eq(Rational(1, 4))
    end

    it 'applies to a declared format without an offset, at that date' do
      answers = under_each_zone do
        summer = klass.new(db_at: '2026-07-01 10:00:00', db_stamp: '2026-07-01 10:00:00')
        winter = klass.new(db_at: '2026-01-15 10:00:00', db_stamp: '2026-01-15 10:00:00')
        [summer.db_at, summer.db_stamp, winter.db_at, winter.db_stamp].map { |value| described(value) }
      end
      expect(answers.uniq).to eq([[[Time, 2026, 7, 1, 10, 0, 0, -21_600], [DateTime, 2026, 7, 1, 10, 0, 0, -21_600],
                                   [Time, 2026, 1, 15, 10, 0, 0, -25_200], [DateTime, 2026, 1, 15, 10, 0, 0, -25_200]]])
    end

    it 'fills a format that omits the date with today in the zone' do
      # Kiritimati is +14:00 all year, 26 hours from a -12:00 process zone, so
      # borrowing the process zone's date cannot pass by luck.
      clock = Class.new(FieldStruct::Base) { optional :at, :time, format: '%H:%M', zone: 'Pacific/Kiritimati' }
      answers = [*process_zones, 'Etc/GMT+12'].map do |zone|
        with_process_zone(zone) do
          at = clock.new(at: '10:00').at
          today = Time.now.getlocal(50_400)
          [at.utc_offset, [at.year, at.mon, at.mday] == [today.year, today.mon, today.mday], at.hour]
        end
      end
      expect(answers.uniq).to eq([[50_400, true, 10]])
    end

    describe 'daylight-saving edges' do
      it 'refuses a wall-clock time the zone skips (spring forward), naming no value' do
        # Denver goes 01:59:59 -07:00 -> 03:00:00 -06:00 on 8 March 2026.
        answers = under_each_zone do
          record = klass.new(at: '2026-03-08 02:30', stamp: '2026-03-08 02:30', db_at: '2026-03-08 02:30:00')
          [record.errors[:at], record.errors[:stamp], record.errors[:db_at]].map(&:join)
        end
        expect(answers.uniq.size).to eq(1)
        expect(answers.first).to all(include('does not exist in America/Denver'))
        expect(answers.first.join).not_to include('02:30')
      end

      it 'reads a wall-clock time the zone repeats (fall back) at its daylight-time offset, as ActiveSupport does' do
        # 01:30 happens twice on 1 November 2026: at -06:00, then at -07:00.
        answers = under_each_zone do
          record = klass.new(at: '2026-11-01 01:30', stamp: '2026-11-01 01:30')
          [described(record.at), record.at.to_i, described(record.stamp)]
        end
        expect(answers.uniq).to eq([[[Time, 2026, 11, 1, 1, 30, 0, -21_600], Time.utc(2026, 11, 1, 7, 30).to_i,
                                     [DateTime, 2026, 11, 1, 1, 30, 0, -21_600]]])
      end
    end
  end

  describe 'input that carries its own offset keeps it' do
    it 'keeps a string offset, a Time and a DateTime' do
      time = Time.new(2026, 7, 1, 10, 0, 0, '+02:00')
      date_time = DateTime.new(2026, 1, 15, 10, 0, 0, '+02:00')
      record = klass.new(at: '2026-07-01T10:00:00+02:00', stamp: time, db_at: date_time)
      expect(described(record.at)).to eq([Time, 2026, 7, 1, 10, 0, 0, 7200])
      expect(described(record.stamp)).to eq([DateTime, 2026, 7, 1, 10, 0, 0, 7200])
      expect(described(record.db_at)).to eq([Time, 2026, 1, 15, 10, 0, 0, 7200])
    end
  end

  describe 'a Date' do
    it 'becomes midnight at the offset in force that day' do
      answers = under_each_zone do
        summer = klass.new(at: Date.new(2026, 7, 1), stamp: Date.new(2026, 7, 1))
        winter = klass.new(at: Date.new(2026, 1, 15), stamp: Date.new(2026, 1, 15))
        [summer.at, summer.stamp, winter.at, winter.stamp].map { |value| described(value) }
      end
      expect(answers.uniq).to eq([[[Time, 2026, 7, 1, 0, 0, 0, -21_600], [DateTime, 2026, 7, 1, 0, 0, 0, -21_600],
                                   [Time, 2026, 1, 15, 0, 0, 0, -25_200], [DateTime, 2026, 1, 15, 0, 0, 0, -25_200]]])
    end

    it 'becomes the first moment of the day when the zone skips midnight' do
      # Chile springs forward at 00:00 on 6 September 2026: the day starts at 01:00 -03:00.
      answers = under_each_zone { described(klass.new(chile: Date.new(2026, 9, 6)).chile) }
      expect(answers.uniq).to eq([[Time, 2026, 9, 6, 1, 0, 0, -10_800]])
    end
  end

  it 'places an epoch under format: "%s" at the zone offset in force at that instant' do
    answers = under_each_zone do
      summer = klass.new(epoch_at: '1792656000', epoch_stamp: '1792656000') # 2026-10-22 08:00Z
      winter = klass.new(epoch_at: '1768478400', epoch_stamp: '1768478400') # 2026-01-15 12:00Z
      [described(summer.epoch_at), summer.epoch_at.to_i, described(summer.epoch_stamp),
       described(winter.epoch_at), winter.epoch_at.to_i, described(winter.epoch_stamp)]
    end
    expect(answers.uniq).to eq([[[Time, 2026, 10, 22, 2, 0, 0, -21_600], 1_792_656_000,
                                 [DateTime, 2026, 10, 22, 2, 0, 0, -21_600],
                                 [Time, 2026, 1, 15, 5, 0, 0, -25_200], 1_768_478_400,
                                 [DateTime, 2026, 1, 15, 5, 0, 0, -25_200]]])
  end

  it 'round-trips through JSON' do
    record = klass.new(at: '2026-07-01 10:00', stamp: '2026-01-15 10:00', db_at: '2026-07-01 10:00:00')
    expect(klass.from_json(record.to_json)).to eq(record)
  end

  it 'applies to array elements through element:' do
    shifts = Class.new(FieldStruct::Base) { optional :at, :array, of: :time, element: {zone: 'America/Denver'} }
    expect(shifts.new(at: ['2026-07-01 10:00', '2026-01-15 10:00']).at.map(&:utc_offset)).to eq([-21_600, -25_200])
  end

  describe 'declaration' do
    def declare(zone, type = :time)
      Class.new(FieldStruct::Base) { optional :at, type, zone: zone }
    end

    it 'accepts Area/Location names from the zone database' do
      %w[America/Denver Asia/Kolkata Europe/London Etc/UTC America/Argentina/Buenos_Aires].each do |zone|
        expect { declare(zone) }.not_to raise_error
        expect { declare(zone, :datetime) }.not_to raise_error
      end
    end

    it 'refuses a name the zone database does not have, naming the option and what it takes' do
      expect { declare('Mars/Olympus_Mons') }.to raise_error(
        ArgumentError,
        %r{\Azone: on Time expects an IANA name like "America/Denver", "UTC" or a UTC offset like "-06:00", got "Mars/Olympus_Mons"}
      )
      expect { declare('Mars/Olympus_Mons', :datetime) }.to raise_error(ArgumentError, /\Azone: on DateTime expects an IANA name/)
    end

    it 'refuses a Rails zone name, saying it is an ActiveSupport alias' do
      expect { declare('Mountain Time (US & Canada)') }.to raise_error(
        ArgumentError, /got "Mountain Time \(US & Canada\)".*ActiveSupport alias.*ActiveSupport::TimeZone::MAPPING/
      )
    end

    it 'refuses an abbreviation or legacy alias, even one the zone database lists' do
      %w[MST EST EST5EDT Zulu].each do |zone|
        expect { declare(zone) }.to raise_error(ArgumentError, %r{got "#{zone}".*Area/Location name})
      end
    end

    it 'says to add tzinfo-data when no zone data can be found' do
      allow(TZInfo::Timezone).to receive(:get).and_raise(TZInfo::DataSourceNotFound, 'no source')
      expect { declare('Africa/Abidjan') }.to raise_error(ArgumentError, %r{\Azone: on Time names "Africa/Abidjan".*tzinfo-data})
    end

    it 'shows the name as declared in Metadata#to_h and describe' do
      expect(klass.metadata.to_h[:at][:options]).to include(zone: 'America/Denver')
      expect(klass.describe).to include('at (Time, optional) — zone: "America/Denver"')
    end
  end

  describe 'loading tzinfo' do
    # A fresh process, so whatever this suite (or ActiveSupport) has loaded
    # cannot hide an eager require.
    def tzinfo_loaded_after(declaration)
      script = <<~RUBY
        require 'field_struct'
        klass = Class.new(FieldStruct::Base) { #{declaration} }
        klass.new(at: '2026-07-01 10:00')
        print defined?(TZInfo) ? 'loaded' : 'not loaded'
      RUBY
      lib = File.expand_path('../../lib', __dir__)
      out, status = Open3.capture2e(RbConfig.ruby, '-I', lib, '-e', script)
      raise out unless status.success?

      out
    end

    it 'is not required by field_struct, nor by a "UTC" or fixed-offset zone' do
      expect(tzinfo_loaded_after("optional :at, :time, zone: '-06:00'; optional :b, :datetime, zone: 'UTC'"))
        .to eq('not loaded')
    end

    it 'is required when a field declares an IANA name' do
      expect(tzinfo_loaded_after("optional :at, :time, zone: 'America/Denver'")).to eq('loaded')
    end
  end
end
