# frozen_string_literal: true

# zone: on :time and :datetime. A zone-less string ("2026-10-22 10:00") means
# nothing until something supplies its offset: by default :time borrows the
# process zone and :datetime assumes UTC. zone: names the offset, so the same
# input gives the same answer on any server. It only fills in a MISSING offset;
# anything that already carries one keeps it.
RSpec.describe 'zone: option' do
  # Ruby re-reads the zone when ENV['TZ'] is assigned, so every example below
  # runs once per process zone. The zones straddle UTC and include one with DST
  # (Denver) and one without (Tokyo).
  process_zones = %w[America/Denver Asia/Tokyo UTC].freeze

  def with_process_zone(zone)
    saved = ENV.fetch('TZ', nil)
    ENV['TZ'] = zone
    yield
  ensure
    ENV['TZ'] = saved
  end

  # @return [Array] the block's answer under each process zone
  define_method(:under_each_zone) do |&block|
    process_zones.map { |zone| with_process_zone(zone) { block.call } }
  end

  let(:klass) do
    Class.new(FieldStruct::Base) do
      optional :at, :time, zone: '-06:00'
      optional :utc_at, :time, zone: 'UTC'
      optional :stamp, :datetime, zone: '+09:00'
      optional :utc_stamp, :datetime, zone: 'UTC'
      optional :db_at, :time, format: :db, zone: '-06:00'
      optional :clock, :time, format: '%H:%M', zone: '+14:00'
      optional :db_stamp, :datetime, format: :db, zone: '-06:00'
    end
  end

  # [value, offset in seconds] — Time and DateTime both answer these.
  def described(value)
    offset = value.is_a?(DateTime) ? (value.offset * 86_400).to_i : value.utc_offset
    [value.class, value.year, value.mon, value.mday, value.hour, value.min, value.sec, offset]
  end

  it 'makes the default :time answer process-independent (the problem it solves)' do
    plain = Class.new(FieldStruct::Base) { optional :at, :time }
    answers = under_each_zone { plain.new(at: '2026-10-22 10:00').at.utc_offset }
    expect(answers.uniq.size).to be > 1
  end

  describe 'a zone-less string' do
    it 'is read in the declared offset by :time, on every server' do
      answers = under_each_zone { described(klass.new(at: '2026-10-22 10:00').at) }
      expect(answers.uniq).to eq([[Time, 2026, 10, 22, 10, 0, 0, -21_600]])
    end

    it 'is read in UTC by :time with zone: "UTC", and the Time is utc?' do
      answers = under_each_zone do
        at = klass.new(utc_at: '2026-10-22 10:00:30.25').utc_at
        [described(at), at.utc?, at.subsec]
      end
      expect(answers.uniq).to eq([[[Time, 2026, 10, 22, 10, 0, 30, 0], true, Rational(1, 4)]])
    end

    it 'is read in the declared offset by :datetime, on every server' do
      answers = under_each_zone { described(klass.new(stamp: '2026-10-22 10:00').stamp) }
      expect(answers.uniq).to eq([[DateTime, 2026, 10, 22, 10, 0, 0, 32_400]])
    end

    it 'keeps :datetime in UTC with zone: "UTC" (its default, now explicit)' do
      answers = under_each_zone { described(klass.new(utc_stamp: '2026-10-22 10:00').utc_stamp) }
      expect(answers.uniq).to eq([[DateTime, 2026, 10, 22, 10, 0, 0, 0]])
    end

    it 'keeps a wall-clock time that a DST process zone skips (no spring-forward shift)' do
      # 02:30 on 8 March 2026 does not exist in Denver; Time.parse there moves it to 03:30.
      answers = under_each_zone { described(klass.new(at: '2026-03-08 02:30').at) }
      expect(answers.uniq).to eq([[Time, 2026, 3, 8, 2, 30, 0, -21_600]])
    end

    it 'applies to a declared format without an offset' do
      answers = under_each_zone do
        record = klass.new(db_at: '2026-10-22 10:00:00', db_stamp: '2026-10-22 10:00:00')
        [described(record.db_at), described(record.db_stamp)]
      end
      expect(answers.uniq).to eq([[[Time, 2026, 10, 22, 10, 0, 0, -21_600],
                                   [DateTime, 2026, 10, 22, 10, 0, 0, -21_600]]])
    end

    it 'fills a format that omits the date with today in the declared zone' do
      # +14:00 and a -12:00 process zone are 26 hours apart, so their "today"
      # always differs: borrowing the process zone's date cannot pass by luck.
      answers = [*process_zones, 'Etc/GMT+12'].map do |zone|
        with_process_zone(zone) do
          clock = klass.new(clock: '10:00').clock
          today = Time.now.getlocal(50_400)
          [clock.utc_offset, [clock.year, clock.mon, clock.mday] == [today.year, today.mon, today.mday], clock.hour]
        end
      end
      expect(answers.uniq).to eq([[50_400, true, 10]])
    end

    it 'keeps every other rule: a partial or impossible day is still refused' do
      ['10:30', '2026-02-30 10:00'].each do |input|
        record = klass.new(at: input, stamp: input)
        expect(record.errors[:at]).not_to be_empty, input
        expect(record.errors[:stamp]).not_to be_empty, input
      end
    end
  end

  describe 'input that carries its own offset keeps it' do
    it 'keeps a string offset' do
      answers = under_each_zone do
        record = klass.new(at: '2026-10-22T10:00:00+02:00', stamp: '2026-10-22 10:00 Z')
        [described(record.at), described(record.stamp)]
      end
      expect(answers.uniq).to eq([[[Time, 2026, 10, 22, 10, 0, 0, 7200],
                                   [DateTime, 2026, 10, 22, 10, 0, 0, 0]]])
    end

    it 'keeps a Time and a DateTime unchanged (instant and offset)' do
      time = Time.new(2026, 10, 22, 10, 0, 0, '+02:00')
      date_time = DateTime.new(2026, 10, 22, 10, 0, 0, '+02:00')
      record = klass.new(at: time, stamp: date_time, utc_at: date_time, utc_stamp: time)
      expect(described(record.at)).to eq(described(time))
      expect(described(record.stamp)).to eq(described(date_time))
      expect(record.utc_at.utc_offset).to eq(7200)
      expect((record.utc_stamp.offset * 86_400).to_i).to eq(7200)
    end

    it 'refuses a zone name with no fixed offset rather than overriding it' do
      record = klass.new(at: '2026-10-22 10:00 XYZ', stamp: '2026-10-22 10:00 America/Denver')
      expect(record.errors[:at].join).to match(/time zone with no fixed offset/)
      expect(record.errors[:stamp].join).to match(/time zone with no fixed offset/)
      expect(record.errors.full_messages.join).not_to include('XYZ')
    end
  end

  it 'reads a Date as midnight in the declared offset' do
    answers = under_each_zone do
      record = klass.new(at: Date.new(2026, 10, 22), stamp: Date.new(2026, 10, 22))
      [described(record.at), described(record.stamp)]
    end
    expect(answers.uniq).to eq([[[Time, 2026, 10, 22, 0, 0, 0, -21_600],
                                 [DateTime, 2026, 10, 22, 0, 0, 0, 32_400]]])
  end

  it 'places an epoch string read by format: "%s" at the declared offset, keeping the instant' do
    epoch = Class.new(FieldStruct::Base) do
      optional :at, :time, format: '%s', zone: '-06:00'
      optional :stamp, :datetime, format: '%s', zone: '-06:00'
    end
    answers = under_each_zone do
      record = epoch.new(at: '1792656000', stamp: '1792656000')
      [described(record.at), record.at.to_i, described(record.stamp), record.stamp.strftime('%s').to_i]
    end
    expect(answers.uniq).to eq([[[Time, 2026, 10, 22, 2, 0, 0, -21_600], 1_792_656_000,
                                 [DateTime, 2026, 10, 22, 2, 0, 0, -21_600], 1_792_656_000]])
  end

  it 'leaves Integer epochs refused, as without zone:' do
    expect(klass.new(at: 1_792_656_000, stamp: 1_792_656_000).errors.to_h.keys).to contain_exactly(:at, :stamp)
  end

  it 'round-trips through JSON' do
    record = klass.new(at: '2026-10-22 10:00', stamp: '2026-10-22 10:00', db_at: '2026-10-22 10:00:00')
    expect(klass.from_json(record.to_json)).to eq(record)
  end

  describe 'declaration' do
    def declare(zone, type = :time)
      Class.new(FieldStruct::Base) { optional :at, type, zone: zone }
    end

    it 'accepts UTC and fixed offsets from -23:59 to +23:59' do
      %w[UTC +00:00 -00:00 -06:00 +05:30 +14:00 -23:59].each do |zone|
        expect { declare(zone) }.not_to raise_error
        expect { declare(zone, :datetime) }.not_to raise_error
      end
    end

    {
      'an abbreviation' => 'MST',
      'a lowercase utc' => 'utc',
      'Z' => 'Z',
      'an offset without a colon' => '-0600',
      'an offset without minutes' => '-06',
      'an out-of-range hour' => '+24:00',
      'an out-of-range minute' => '+05:60',
      'a blank string' => ''
    }.each do |label, zone|
      it "refuses #{label} with an ArgumentError naming the option" do
        expect { declare(zone) }.to raise_error(ArgumentError, %r{\Azone: on Time expects an IANA name like "America/Denver", "UTC" or a UTC offset})
        expect { declare(zone, :datetime) }.to raise_error(ArgumentError, /\Azone: on DateTime expects/)
      end
    end

    it 'accepts an IANA name (see iana_zone_spec.rb)' do
      expect { declare('America/Denver') }.not_to raise_error
    end

    it 'refuses a non-String' do
      expect { declare(-6) }.to raise_error(ArgumentError, /zone: on Time expects String, got Integer/)
    end

    it 'refuses zone: on :date and other types, naming the types it applies to' do
      expect { declare('UTC', :date) }.to raise_error(ArgumentError, /zone: option does not apply to Date fields. It applies to: Time, DateTime/)
      expect { declare('UTC', :string) }.to raise_error(ArgumentError, /does not apply to String/)
    end
  end

  describe 'introspection' do
    it 'shows in Metadata#to_h, describe and the type schema' do
      expect(klass.metadata.to_h[:at][:options]).to include(zone: '-06:00')
      expect(klass.describe).to include('at (Time, optional) — zone: "-06:00"')
      expect(klass.describe).to include('zone (String)')
      expect(FieldStruct::Types::Time.option_schema.keys).to include(:zone)
      expect(FieldStruct::Types::DateTime.option_schema.keys).to include(:zone)
      expect(FieldStruct::Types::Date.option_schema.keys).not_to include(:zone)
    end
  end

  describe 'the type, called directly' do
    it 'takes zone: as a coerce option' do
      expect(FieldStruct::Types::Time.new.coerce('2026-10-22 10:00', zone: '+01:00').utc_offset).to eq(3600)
      expect(FieldStruct::Types::DateTime.new.coerce('2026-10-22 10:00', zone: '+01:00').offset).to eq(Rational(1, 24))
    end
  end
end
