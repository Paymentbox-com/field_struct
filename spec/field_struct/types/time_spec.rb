# frozen_string_literal: true

require 'time'

RSpec.describe FieldStruct::Types::Time do
  let(:type) { described_class.new }

  describe 'coercing input to a time' do
    context 'with a Time value' do
      it 'returns the same Time' do
        t = Time.local(2024, 1, 15, 12, 30)
        expect(type.coerce(t)).to equal(t)
      end
    end

    context 'with a Date value' do
      it 'returns a Time at the start of that day' do
        date = Date.new(2024, 1, 15)
        result = type.coerce(date)
        expect(result).to be_a(Time)
        expect(result.year).to eq(2024)
        expect(result.month).to eq(1)
        expect(result.day).to eq(15)
      end
    end

    context 'with a DateTime value' do
      it 'returns the equivalent Time' do
        dt = DateTime.new(2024, 1, 15, 12, 30)
        result = type.coerce(dt)
        expect(result).to be_a(Time)
        expect(result.year).to eq(2024)
        expect(result.hour).to eq(12)
      end
    end

    context 'with an ISO-8601 string' do
      it 'returns the parsed Time' do
        result = type.coerce('2024-01-15T12:30:00Z')
        expect(result).to be_a(Time)
        expect(result.year).to eq(2024)
        expect(result.utc?).to be true
      end
    end

    context 'with nil' do
      it 'returns nil' do
        expect(type.coerce(nil)).to be_nil
      end
    end

    context 'with an unparseable string' do
      it 'raises ArgumentError' do
        expect { type.coerce('not-a-time') }.to raise_error(ArgumentError)
      end
    end
  end

  describe 'reporting missing values' do
    context 'when value is nil' do
      it 'is missing' do
        expect(type.missing?(nil)).to be true
      end
    end

    context 'when value is a real Time' do
      it 'is not missing' do
        expect(type.missing?(Time.now)).to be false
      end
    end
  end

  describe 'reporting ruby_type' do
    it 'returns the top-level Time class' do
      expect(type.ruby_type).to eq(Time)
    end
  end
end
