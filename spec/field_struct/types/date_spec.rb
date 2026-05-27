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
