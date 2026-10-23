# frozen_string_literal: true

require 'date'

RSpec.describe FieldStruct::Types::Date do
  let(:type) { described_class.new }

  describe 'coercing input to a date' do
    context 'with a Date value' do
      it 'returns the same Date' do
        date = Date.new(2024, 1, 15)
        expect(type.coerce(date)).to equal(date)
      end
    end

    context 'with a DateTime value' do
      it 'returns a Date for that calendar day (not a DateTime)' do
        dt = DateTime.new(2024, 1, 15, 12, 30)
        result = type.coerce(dt)
        expect(result).to be_an_instance_of(Date)
        expect(result).to eq(Date.new(2024, 1, 15))
      end
    end

    context 'with a Time value' do
      it 'returns a Date for that calendar day' do
        time = Time.local(2024, 1, 15, 12, 30)
        result = type.coerce(time)
        expect(result).to be_an_instance_of(Date)
        expect(result).to eq(Date.new(2024, 1, 15))
      end
    end

    context 'with an ISO-8601 string' do
      it 'returns the parsed Date' do
        expect(type.coerce('2024-01-15')).to eq(Date.new(2024, 1, 15))
      end
    end

    context 'with nil' do
      it 'returns nil' do
        expect(type.coerce(nil)).to be_nil
      end
    end

    context 'with an unparseable string' do
      it 'raises ArgumentError' do
        expect { type.coerce('not-a-date') }.to raise_error(ArgumentError)
      end
    end
  end

  # `format:` is documented to control BOTH parsing and serialization, and
  # DateTime and Time both honour it on the way in. Date did not, and nothing
  # here covered it.
  describe 'coercing a string with a format' do
    it 'parses through strptime rather than Date.parse' do
      expect(type.coerce('15/01/2024', format: '%d/%m/%Y')).to eq(Date.new(2024, 1, 15))
    end

    # The whole point of declaring a format: an ambiguous date must be read the
    # way the field says, not the way Date.parse guesses. Date.parse reads this
    # as 3 July; the format says 7 March.
    it 'reads an ambiguous date the way the format says, not the way Date.parse guesses' do
      expect(type.coerce('07/03/2026', format: '%d/%m/%Y')).to eq(Date.new(2026, 3, 7))
      expect(Date.parse('07/03/2026')).to eq(Date.new(2026, 3, 7))
    end

    it 'raises ArgumentError when the string does not match the format' do
      expect { type.coerce('07/03/2026', format: '%Y-%m-%d') }.to raise_error(ArgumentError)
    end

    # REGRESSION. `coerce` used to convert anything responding to `to_date`
    # BEFORE consulting the format, so a String that also answers `to_date`
    # never reached strptime and the declared format was silently ignored.
    #
    # That is not hypothetical and it is not rare: ActiveSupport defines
    # String#to_date, so under Rails EVERY string took the wrong branch. The
    # gem's own suite could never catch it — plain Ruby has no String#to_date,
    # so the branch was simply never taken here. This subclass reproduces the
    # exact condition Rails creates, without depending on ActiveSupport.
    #
    # DateTime and Time already guarded this with `value.is_a?(::String) &&
    # format`; Date is now consistent with them.
    context 'when the string also responds to to_date, as it does under ActiveSupport' do
      let(:stringish) do
        Class.new(String) do
          def to_date
            Date.new(2000, 1, 1)
          end
        end
      end

      it 'still parses through the format instead of taking the to_date branch' do
        expect(type.coerce(stringish.new('15/01/2024'), format: '%d/%m/%Y')).to eq(Date.new(2024, 1, 15))
      end

      it 'still rejects a string that does not match the format' do
        expect { type.coerce(stringish.new('nope'), format: '%d/%m/%Y') }.to raise_error(ArgumentError)
      end
    end

    # `format:` governs how a STRING is read. A value that is already a date-like
    # object carries no formatting, so it keeps converting through `to_date`.
    context 'with a non-string value' do
      it 'converts a DateTime through to_date even when a format is set' do
        result = type.coerce(DateTime.new(2024, 1, 15, 12, 30), format: '%d/%m/%Y')

        expect(result).to eq(Date.new(2024, 1, 15))
      end

      it 'passes a Date through untouched even when a format is set' do
        date = Date.new(2024, 1, 15)

        expect(type.coerce(date, format: '%d/%m/%Y')).to equal(date)
      end
    end
  end

  # A string is parsed once: the Date is built from the parts the validation
  # step already read, except where the stdlib would read those parts
  # differently (a day of the year or Julian day number among them), or where
  # they don't name a whole day. Each case pins the stdlib's answer.
  describe 'what a parsed string becomes' do
    it 'matches Date.parse for the forms it reads, calendar reform and BC included' do
      ['2026-01-05', 'Jan 5 2026', 'Monday 2026-01-06', '26-1-5', '5 Jan 2026 BC', '1582-10-15', ' 2026-01-05 '].each do |input|
        result = type.coerce(input)
        expect([result, result.start]).to eq([Date.parse(input), Date::ITALY]), input
      end
    end

    it 'refuses an ordinal date without a format, as before' do
      expect { type.coerce('2026-032') }.to raise_error(ArgumentError, 'expected a date with a year, a month and a day')
    end

    it 'reads a format with a day of the year the way strptime does' do
      expect(type.coerce('2026-01-05 200', format: '%Y-%m-%d %j')).to eq(Date.new(2026, 7, 19))
    end

    it 'reads a format without a day the way strptime does' do
      expect(type.coerce('2026-01', format: '%Y-%m')).to eq(Date.new(2026, 1, 1))
    end

    it 'keeps the written day when a format also carries epoch seconds' do
      expect(type.coerce('2026-01-05 0', format: '%Y-%m-%d %s')).to eq(Date.new(2026, 1, 5))
    end

    it 'still refuses a day that does not exist' do
      expect { type.coerce('2026-02-30') }.to raise_error(ArgumentError, 'invalid date')
      expect { type.coerce('30/02/2026', format: '%d/%m/%Y') }.to raise_error(ArgumentError, 'invalid date')
    end
  end

  describe 'reporting missing values' do
    context 'when value is nil' do
      it 'is missing' do
        expect(type.missing?(nil)).to be true
      end
    end

    context 'when value is a real Date' do
      it 'is not missing' do
        expect(type.missing?(Date.today)).to be false
      end
    end
  end

  describe 'reporting ruby_type' do
    it 'returns the top-level Date class' do
      expect(type.ruby_type).to eq(Date)
    end
  end
end
