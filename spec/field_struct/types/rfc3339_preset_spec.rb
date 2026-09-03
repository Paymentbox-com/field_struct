# frozen_string_literal: true

require 'date'
require 'time'

# The `:iso8601` preset is RFC 3339 — the profile of ISO 8601 that "ISO-8601"
# actually means in an API contract, and what JSON Schema's `date-time` refers
# to. FieldStruct parses and renders it itself.
#
# It is deliberately NOT `Time.iso8601` / `DateTime.iso8601`. Those two disagree
# with each other on nearly every edge, and `Time.iso8601` reintroduces the very
# defect this release exists to remove:
#
#   Time.iso8601('2026-02-30T10:30:00Z')      # => 2026-03-02 10:30:00 UTC
#   DateTime.iso8601('2026-02-30T10:30:00Z')  # => refused
#   Time.iso8601('2026-07-03T10:30Z')         # => refused
#   DateTime.iso8601('2026-07-03T10:30Z')     # => accepted
#   DateTime.iso8601('10:30:00Z')             # => TODAY at 10:30
#
# A `:time` field and a `:datetime` field both declaring `format: :iso8601`
# would otherwise accept different strings. They accept the same strings here.
RSpec.describe 'the iso8601 preset (RFC 3339)' do
  describe ':date' do
    let(:klass) { Class.new(FieldStruct::Base) { required :on, :date, format: :iso8601 } }

    it 'accepts a full-width date' do
      expect(klass.new(on: '2026-07-03').on).to eq(Date.new(2026, 7, 3))
    end

    # Every one of these was ACCEPTED by leftover-anchored strptime, which is
    # why anchoring alone was not enough to let a consumer drop a hand-rolled
    # /\A\d{4}-\d{2}-\d{2}\z/ regex. %m and %d take one or two digits and %Y
    # takes a sign and unlimited digits.
    {
      '2026-7-3' => 'single-digit month and day',
      '+2026-07-03' => 'a signed year',
      '20261-07-03' => 'a five-digit year',
      '20260703' => 'the basic (unseparated) format',
      '2026-W27-5' => 'an ISO week date',
      '2026-184' => 'an ordinal date',
      '2026-07-03T10:30:00Z' => 'a full timestamp'
    }.each do |input, description|
      it "refuses #{description}" do
        expect(klass.new(on: input)).not_to be_valid
      end
    end

    it 'refuses a day that never existed' do
      expect(klass.new(on: '2026-02-30')).not_to be_valid
      expect(klass.new(on: '2026-06-31')).not_to be_valid
    end

    it 'renders back as a full-width date' do
      expect(klass.new(on: '2026-07-03').as_json[:on]).to eq('2026-07-03')
    end
  end

  # These run identically for :time and :datetime — that parity is the point.
  %i[time datetime].each do |type_name|
    describe ":#{type_name}" do
      let(:klass) do
        name = type_name
        Class.new(FieldStruct::Base) { required :at, name, format: :iso8601 }
      end

      it 'accepts a timestamp with a numeric offset' do
        expect(klass.new(at: '2026-07-03T10:30:00-06:00')).to be_valid
      end

      it 'accepts Z' do
        expect(klass.new(at: '2026-07-03T10:30:00Z')).to be_valid
      end

      # Most JSON APIs emit these, and the strftime-based preset refused them:
      # no strftime string can express "optional fractional seconds".
      it 'accepts fractional seconds' do
        instance = klass.new(at: '2026-07-03T10:30:00.123456Z')
        expect(instance).to be_valid
      end

      # v0.9.0 rendered `+0000`, so its own output has to keep parsing.
      it 'accepts the offset spelling v0.9.0 used to emit' do
        expect(klass.new(at: '2026-07-03T10:30:00+0000')).to be_valid
      end

      {
        '2026-07-03T10:30:00' => 'no offset at all',
        '2026-07-03 10:30:00Z' => 'a space instead of T',
        '2026-07-03T10:30Z' => 'missing seconds',
        '2026-07-03' => 'a date with no time',
        '10:30:00Z' => 'a time with no date',
        '2026-07-03T10:30:00+0000-NONSENSE' => 'trailing junk',
        '20261-07-03T10:30:00Z' => 'a five-digit year',
        '2026-07-03T24:00:00Z' => 'hour 24',
        '2026-07-03T10:30:60Z' => 'second 60',
        '2026-02-30T10:30:00Z' => 'a day that never existed',
        '2026-07-03T10:30:00+25:00' => 'an impossible UTC offset'
      }.each do |input, description|
        it "refuses #{description}" do
          expect(klass.new(at: input)).not_to be_valid
        end
      end

      # RFC 3339 wants `+00:00` or `Z`. The preset named iso8601 used to emit
      # `+0000` — a value its own documented format would reject, and one that
      # JSON Schema's `date-time` does not accept.
      it 'renders a UTC value as Z, not +0000' do
        expect(klass.new(at: '2026-07-03T10:30:00Z').as_json[:at]).to eq('2026-07-03T10:30:00Z')
      end

      it 'renders a non-UTC offset with a colon' do
        expect(klass.new(at: '2026-07-03T10:30:00-06:00').as_json[:at]).to eq('2026-07-03T10:30:00-06:00')
      end

      it 'renders fractional seconds when the value carries them' do
        expect(klass.new(at: '2026-07-03T10:30:00.5Z').as_json[:at]).to eq('2026-07-03T10:30:00.5Z')
      end

      it 'round-trips through JSON' do
        original = klass.new(at: '2026-07-03T10:30:00-06:00')
        expect(klass.from_json(original.to_json)).to eq(original)
      end

      it 'preserves the instant across the offset it was given' do
        utc = klass.new(at: '2026-07-03T16:30:00Z')
        mst = klass.new(at: '2026-07-03T10:30:00-06:00')
        expect(mst.at.strftime('%s')).to eq(utc.at.strftime('%s'))
      end
    end
  end

  # :time and :datetime declaring the same preset must accept the same strings.
  # Routing them through Time.iso8601 and DateTime.iso8601 would not do that.
  it 'accepts and refuses identically for :time and :datetime' do
    times = Class.new(FieldStruct::Base) { required :at, :time, format: :iso8601 }
    datetimes = Class.new(FieldStruct::Base) { required :at, :datetime, format: :iso8601 }

    %w[
      2026-07-03T10:30:00Z 2026-07-03T10:30:00.5-06:00 2026-07-03T10:30Z
      2026-02-30T10:30:00Z 10:30:00Z 2026-07-03 20260703T103000Z
      2026-07-03T10:30:00+25:00
    ].each do |input|
      expect(times.new(at: input).valid?).to eq(datetimes.new(at: input).valid?),
        "disagreed on #{input.inspect}"
    end
  end

  # The other presets are display and interchange formats, not wire contracts,
  # so they stay strptime-based. They still get anchoring and civil validity.
  describe 'the other presets stay strptime-based' do
    it ':db keeps accepting a zone-less database timestamp' do
      klass = Class.new(FieldStruct::Base) { required :at, :datetime, format: :db }

      expect(klass.new(at: '2026-07-03 10:30:00')).to be_valid
    end

    it ':us and :eu read the same digits differently, as declared' do
      us = Class.new(FieldStruct::Base) { required :on, :date, format: :us }
      eu = Class.new(FieldStruct::Base) { required :on, :date, format: :eu }

      expect(us.new(on: '07/03/2026').on).to eq(Date.new(2026, 7, 3))
      expect(eu.new(on: '07/03/2026').on).to eq(Date.new(2026, 3, 7))
    end

    it ':rfc2822 still round-trips' do
      klass = Class.new(FieldStruct::Base) { required :at, :datetime, format: :rfc2822 }
      instance = klass.new(at: 'Fri, 03 Jul 2026 10:30:00 +0000')

      expect(instance).to be_valid
      expect(klass.from_json(instance.to_json)).to eq(instance)
    end
  end
end
