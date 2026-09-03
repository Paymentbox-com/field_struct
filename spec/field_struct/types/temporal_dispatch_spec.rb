# frozen_string_literal: true

require 'date'
require 'time'

# Coercion for the three temporal types dispatches on explicit stdlib classes,
# never on `respond_to?` probes against the value.
#
# The distinction is not academic. ActiveSupport defines `String#to_date`,
# `String#to_time` and `String#to_datetime` on core classes, so a probe that is
# false on plain Ruby is TRUE under Rails and the types took a different branch
# there than they did in their own suite. Measured on v0.9.0 under Rails, that
# made `optional :t, :time` accept "not-a-time" as VALID with a nil value,
# because AS's String#to_time returns nil rather than raising.
#
# `Date.parse`, `Time.parse`, `DateTime.parse` and `strptime` are not redefined
# by ActiveSupport, so dispatching on those keeps one behaviour in both worlds.
#
# The doubles below answer the AS-added predicates without ActiveSupport being
# loaded, so this file proves the branch in the PLAIN Ruby lane too — the lane
# that could never reach it before.
RSpec.describe 'temporal coercion dispatch' do
  # A String that answers `to_date` / `to_time` / `to_datetime`, exactly as
  # every String does once ActiveSupport is loaded. The return values are
  # deliberately wrong so that taking the probe branch is visible as a failure
  # rather than a coincidence.
  let(:stringish) do
    Class.new(String) do
      def to_date = Date.new(1999, 12, 31)
      def to_time = nil
      def to_datetime = DateTime.new(1999, 12, 31)
    end
  end

  describe FieldStruct::Types::Date do
    let(:type) { described_class.new }

    it 'parses a to_date-answering String through Date.parse, not the probe' do
      expect(type.coerce(stringish.new('2024-01-15'))).to eq(Date.new(2024, 1, 15))
    end

    it 'honours a declared format on a to_date-answering String' do
      expect(type.coerce(stringish.new('15/01/2024'), format: '%d/%m/%Y')).to eq(Date.new(2024, 1, 15))
    end

    it 'refuses garbage that AS would answer nil for' do
      expect { type.coerce(stringish.new('not-a-date')) }.to raise_error(ArgumentError)
    end

    it 'converts a DateTime down to a plain Date' do
      result = type.coerce(DateTime.new(2024, 1, 15, 12, 30))
      expect(result).to eq(Date.new(2024, 1, 15))
      expect(result.instance_of?(Date)).to be true
    end

    it 'converts a Time down to a Date' do
      expect(type.coerce(Time.utc(2024, 1, 15, 12, 30))).to eq(Date.new(2024, 1, 15))
    end
  end

  describe FieldStruct::Types::Time do
    let(:type) { described_class.new }

    it 'parses a to_time-answering String through Time.parse, not the probe' do
      result = type.coerce(stringish.new('2024-01-15T12:30:00Z'))
      expect(result).to be_a(Time)
      expect(result.utc?).to be true
    end

    # THE regression. Under ActiveSupport this string was VALID with a nil
    # value, because String#to_time returns nil for a string with no date parts
    # instead of raising. Garbage must be refused, not silently nilled.
    ['not-a-time', 'tomorrow at noon', '', '   '].each do |garbage|
      it "refuses #{garbage.inspect} rather than coercing it to nil" do
        expect { type.coerce(stringish.new(garbage)) }.to raise_error(ArgumentError)
      end
    end

    # Built from components rather than `DateTime#to_time`, which ActiveSupport
    # redefines: under AS 7.2 it converts to the system-local zone AND emits a
    # deprecation warning, while 8.x preserves the offset. Constructing from
    # parts gives one answer in all three environments.
    it 'converts a DateTime preserving both the instant and the offset' do
      dt = DateTime.new(2024, 1, 15, 12, 30, 0, '+00:00')
      result = type.coerce(dt)
      expect(result).to be_a(Time)
      expect(result.hour).to eq(12)
      expect(result.utc_offset).to eq(0)
    end

    it 'keeps sub-second precision when converting a DateTime' do
      dt = DateTime.new(2024, 1, 15, 12, 30, Rational(15.25.to_s.to_r), '+00:00')
      expect(type.coerce(dt).subsec).to eq(Rational(1, 4))
    end

    it 'converts a Date to the start of that day' do
      expect(type.coerce(Date.new(2024, 1, 15)).year).to eq(2024)
    end

    it 'returns an actual Time instance unchanged' do
      t = Time.utc(2024, 1, 15, 12, 30)
      expect(type.coerce(t)).to equal(t)
    end

    # ActiveSupport::TimeWithZone matches `case value when ::Time` because AS
    # overrides Time.===, but it is NOT `instance_of?(::Time)`. Without an
    # explicit conversion it would be stored raw in a field declared :time.
    it 'converts a Time-like value that is not itself a Time, preserving the instant' do
      time_like = Class.new do
        def initialize(time) = @time = time
        def to_r = @time.to_r
        def utc_offset = @time.utc_offset
        def self.name = 'TimeLike'
      end
      # Stand in for TWZ by making ::Time === it, the way AS does.
      allow(Time).to receive(:===).and_wrap_original do |orig, other|
        other.is_a?(time_like) || orig.call(other)
      end
      source = Time.utc(2024, 1, 15, 12, 30)
      result = type.coerce(time_like.new(source))
      expect(result).to be_an_instance_of(Time)
      expect(result.to_r).to eq(source.to_r)
    end
  end

  describe FieldStruct::Types::DateTime do
    let(:type) { described_class.new }

    it 'parses a to_datetime-answering String through DateTime.parse, not the probe' do
      expect(type.coerce(stringish.new('2024-01-15T12:30:00+00:00'))).to eq(DateTime.new(2024, 1, 15, 12, 30, 0, '+00:00'))
    end

    it 'refuses garbage' do
      expect { type.coerce(stringish.new('not-a-datetime')) }.to raise_error(ArgumentError)
    end

    it 'converts a Time preserving the instant and the offset' do
      t = Time.new(2024, 1, 15, 12, 30, 0, '-06:00')
      result = type.coerce(t)
      expect(result).to be_a(DateTime)
      # Compared via strftime('%s%N') rather than #to_time: ActiveSupport 7.2
      # deprecates DateTime#to_time, and this lane raises on deprecations.
      expect(result.strftime('%s%N')).to eq(t.strftime('%s%N'))
      expect(result.offset).to eq(Rational(-6, 24))
    end

    it 'converts a Date to midnight' do
      expect(type.coerce(Date.new(2024, 1, 15))).to eq(DateTime.new(2024, 1, 15))
    end
  end

  # A blank string is a coercion failure for every other non-string scalar
  # (integer, float, big_decimal, boolean all refuse ""), and the stdlib parsers
  # refuse it too. Only :string treats blank as missing — it is the outlier, not
  # the rule. Under ActiveSupport this used to come back VALID with a nil value.
  describe 'a blank string' do
    %i[date time datetime].each do |type_name|
      it "is a coercion failure for :#{type_name}, not a missing value" do
        klass = Class.new(FieldStruct::Base) { optional :v, type_name }
        instance = klass.new(v: '')
        expect(instance).not_to be_valid
        expect(instance.errors.full_messages.first).to match(/could not be coerced/)
      end
    end
  end

  # `X.parse(value.to_s)` was the terminal arm, and it invents data rather than
  # refusing: Time.parse('[2026, 7, 3]') returns NOW, 'v1.2.3' reads as
  # 2001-02-03, and the Integer 20260703 parses as a valid Date. It was already
  # inconsistent — with a format declared, :date refused the Integer (strptime)
  # while :time accepted it (fell through to parse).
  describe 'a value that is neither a String nor a temporal object' do
    [20_260_703, :today, [2026, 7, 3], {year: 2026}, 1.5].each do |value|
      %i[date time datetime].each do |type_name|
        it "is refused by :#{type_name} rather than parsed from #{value.class}" do
          type = FieldStruct.types.lookup(type_name).new
          expect { type.coerce(value) }.to raise_error(ArgumentError, /expected/)
        end
      end
    end

    # The message names the class but never the value: FieldStruct wraps it as
    # "could not be coerced: <message>" and that string reaches API responses
    # and audit rows, so an echoed value is a published value.
    it 'names the class in the message but never the value' do
      type = FieldStruct::Types::Date.new
      expect { type.coerce('4111111111111111'.to_i) }
        .to raise_error(ArgumentError) { |e| expect(e.message).not_to include('4111') }
    end
  end
end
