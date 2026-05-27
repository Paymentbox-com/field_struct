# frozen_string_literal: true

require 'date'

RSpec.describe FieldStruct::Types::DateTime do
  let(:type) { described_class.new }

  describe 'coercing input to a datetime' do
    context 'with a DateTime value' do
      it 'returns the same DateTime' do
        dt = DateTime.new(2024, 1, 15, 12, 30)
        expect(type.coerce(dt)).to eq(dt)
      end
    end

    context 'with a Date value' do
      it 'returns a DateTime at the start of that day' do
        date = Date.new(2024, 1, 15)
        result = type.coerce(date)
        expect(result).to be_a(DateTime)
        expect(result.year).to eq(2024)
        expect(result.hour).to eq(0)
      end
    end

    context 'with a Time value' do
      it 'returns the equivalent DateTime' do
        t = Time.utc(2024, 1, 15, 12, 30)
        result = type.coerce(t)
        expect(result).to be_a(DateTime)
        expect(result.year).to eq(2024)
        expect(result.hour).to eq(12)
      end
    end

    context 'with an ISO-8601 string' do
      it 'returns the parsed DateTime' do
        result = type.coerce('2024-01-15T12:30:00')
        expect(result).to be_a(DateTime)
        expect(result.year).to eq(2024)
        expect(result.hour).to eq(12)
      end
    end

    context 'with nil' do
      it 'returns nil' do
        expect(type.coerce(nil)).to be_nil
      end
    end

    context 'with an unparseable string' do
      it 'raises ArgumentError' do
        expect { type.coerce('not-a-datetime') }.to raise_error(ArgumentError)
      end
    end
  end

  describe 'reporting missing values' do
    context 'when value is nil' do
      it 'is missing' do
        expect(type.missing?(nil)).to be true
      end
    end

    context 'when value is a real DateTime' do
      it 'is not missing' do
        expect(type.missing?(DateTime.now)).to be false
      end
    end
  end

  describe 'reporting ruby_type' do
    it 'returns the top-level DateTime class' do
      expect(type.ruby_type).to eq(DateTime)
    end
  end
end
