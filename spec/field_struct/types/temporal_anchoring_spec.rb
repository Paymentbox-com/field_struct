# frozen_string_literal: true

require 'date'
require 'time'

# Two rules the stdlib parsers leave to the caller, and which FieldStruct now
# enforces for all three temporal types.
#
# ANCHORING — `strptime` matches a PREFIX and discards the rest. A declared
# `format:` is a contract about the whole string, so a string with characters
# left over is refused rather than half-read.
#
# CIVIL VALIDITY — `Date` and `DateTime` refuse the 30th of February. `Time` did
# not: `Time.parse`, `Time.strptime` and `Time.new` all roll it forward to 2
# March and say nothing. That is a wrong answer delivered confidently, which is
# the failure mode this whole release is about.
RSpec.describe 'temporal string parsing rules' do
  describe 'anchoring a declared format' do
    # strptime stops at the end of the format and throws away whatever follows,
    # so both of these parsed clean on v0.9.0 — the first as the 3rd, the second
    # as a perfectly good timestamp with '-NONSENSE' silently dropped.
    it 'refuses trailing characters after a complete date' do
      klass = Class.new(FieldStruct::Base) { required :on, :date, format: :iso8601 }

      expect(klass.new(on: '2026-07-031').errors[:on].first).to match(/could not be coerced/)
    end

    it 'refuses trailing junk after a complete timestamp' do
      klass = Class.new(FieldStruct::Base) { required :at, :datetime, format: :iso8601 }

      expect(klass.new(at: '2026-07-03T10:30:00+0000-NONSENSE')).not_to be_valid
    end

    it 'refuses a trailing space' do
      type = FieldStruct::Types::Date.new

      expect { type.coerce('2026-07-03 ', format: '%Y-%m-%d') }.to raise_error(ArgumentError)
    end

    # Leading whitespace needs no rule of its own: `Date._strptime` already
    # returns nil for it, so it was refused before and still is. Asserted so a
    # future refactor can't quietly start accepting it.
    it 'refuses leading whitespace' do
      type = FieldStruct::Types::Date.new

      expect { type.coerce(' 2026-07-03', format: '%Y-%m-%d') }.to raise_error(ArgumentError)
    end

    it 'still accepts a string that matches the format exactly' do
      klass = Class.new(FieldStruct::Base) { required :on, :date, format: :iso8601 }

      expect(klass.new(on: '2026-07-03').on).to eq(Date.new(2026, 7, 3))
    end

    # Anchoring means trailing-junk rejection, and nothing more. Widths and
    # sign stay strptime-lenient for a HAND-WRITTEN format — `%m` and `%d`
    # accept one or two digits, and that is strptime's contract, not a defect.
    # Strictness for the built-in presets is a separate matter.
    it 'does not tighten widths for a hand-written format' do
      type = FieldStruct::Types::Date.new

      expect(type.coerce('2026-7-3', format: '%Y-%m-%d')).to eq(Date.new(2026, 7, 3))
    end
  end

  describe 'civil-date validity' do
    # THE :time regression. Both of these were accepted on v0.9.0 in BOTH
    # lanes — with and without ActiveSupport — and read as the following month.
    {
      '2026-02-30 10:30:00' => 'the 30th of February',
      '2026-06-31 10:30:00' => 'the 31st of June'
    }.each do |input, description|
      it "refuses #{description} for :time rather than rolling it forward" do
        klass = Class.new(FieldStruct::Base) { required :at, :time }

        expect(klass.new(at: input)).not_to be_valid
      end

      it "refuses #{description} for :time with a declared format too" do
        klass = Class.new(FieldStruct::Base) { required :at, :time, format: :db }

        expect(klass.new(at: input)).not_to be_valid
      end
    end

    it 'refuses an impossible day for :date and :datetime, as it always did' do
      dates = Class.new(FieldStruct::Base) { required :on, :date }
      times = Class.new(FieldStruct::Base) { required :at, :datetime }

      expect(dates.new(on: '2026-02-30')).not_to be_valid
      expect(times.new(at: '2026-02-30T10:30:00+00:00')).not_to be_valid
    end

    it 'still accepts a leap day in a leap year' do
      klass = Class.new(FieldStruct::Base) { required :at, :time }

      expect(klass.new(at: '2024-02-29 10:30:00')).to be_valid
    end

    it 'refuses a leap day in a non-leap year' do
      klass = Class.new(FieldStruct::Base) { required :at, :time }

      expect(klass.new(at: '2026-02-29 10:30:00')).not_to be_valid
    end
  end

  # Without a declared format the stdlib parsers fill in whatever the string
  # omits, from TODAY. `Time.parse('10:30')` is today at 10:30; `'July'` is the
  # 1st of July this year; `'12'` is the 12th of this month. A value whose
  # meaning changes depending on when it is parsed is not a value.
  describe 'partial input with no declared format' do
    %w[10:30 July 12].each do |partial|
      %i[date time datetime].each do |type_name|
        it "refuses #{partial.inspect} for :#{type_name} rather than filling in today" do
          klass = Class.new(FieldStruct::Base) { required :v, type_name }

          expect(klass.new(v: partial)).not_to be_valid
        end
      end
    end

    it 'accepts a string that names a whole day' do
      klass = Class.new(FieldStruct::Base) { required :v, :date }

      expect(klass.new(v: '2026-07-03')).to be_valid
    end

    it 'accepts a full timestamp' do
      klass = Class.new(FieldStruct::Base) { required :v, :time }

      expect(klass.new(v: '2026-07-03T10:30:00Z')).to be_valid
    end

    # The completeness rule catches input that names only PART of a day. It
    # does not — and cannot — make `Date.parse` strict about what counts as a
    # day: `'v1.2.3'` reads as 2001-02-03 because `Date._parse` finds `1.2.3`
    # and treats it as d.m.y. All three components are present, so nothing here
    # can object. That is stdlib permissiveness, which the no-format path
    # explicitly delegates to; a caller who needs a narrow contract declares a
    # format, and `format: :iso8601` is narrow by construction.
    it 'documents that a complete-but-absurd date still parses without a format' do
      loose = Class.new(FieldStruct::Base) { required :v, :date }
      strict = Class.new(FieldStruct::Base) { required :v, :date, format: :iso8601 }

      expect(loose.new(v: 'v1.2.3').v).to eq(Date.new(2001, 2, 3))
      expect(strict.new(v: 'v1.2.3')).not_to be_valid
    end

    # A time-only format is a deliberate declaration, so it keeps working — the
    # completeness rule applies only where nothing was declared.
    it 'still allows a declared format that names only part of a day' do
      klass = Class.new(FieldStruct::Base) { required :at, :time, format: '%H:%M' }

      expect(klass.new(at: '10:30')).to be_valid
    end
  end
end
