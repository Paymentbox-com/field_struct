# frozen_string_literal: true

require 'bigdecimal'

RSpec.describe FieldStruct::Types::BigDecimal do
  let(:type) { described_class.new }

  describe 'coercing input to a big decimal' do
    context 'with a BigDecimal value' do
      it 'returns the value unchanged' do
        bd = BigDecimal('3.14')
        expect(type.coerce(bd)).to equal(bd)
      end
    end

    context 'with an integer value' do
      it 'returns a BigDecimal equal to the integer' do
        result = type.coerce(42)
        expect(result).to be_a(BigDecimal)
        expect(result).to eq(BigDecimal('42'))
      end
    end

    context 'with a float value' do
      it 'returns a BigDecimal close to the float' do
        result = type.coerce(3.14)
        expect(result).to be_a(BigDecimal)
        expect(result).to eq(BigDecimal('3.14'))
      end
    end

    context 'with a numeric string' do
      it 'returns the parsed BigDecimal' do
        expect(type.coerce('3.14')).to eq(BigDecimal('3.14'))
        expect(type.coerce('-2.5')).to eq(BigDecimal('-2.5'))
      end

      it 'accepts scientific notation' do
        expect(type.coerce('1.5e10')).to eq(BigDecimal('1.5e10'))
      end
    end

    context 'with nil' do
      it 'returns nil' do
        expect(type.coerce(nil)).to be_nil
      end
    end

    context 'with a non-numeric string' do
      it 'raises ArgumentError' do
        expect { type.coerce('abc') }.to raise_error(ArgumentError)
      end
    end
  end

  describe 'reporting missing values' do
    context 'when value is nil' do
      it 'is missing' do
        expect(type.missing?(nil)).to be true
      end
    end

    context 'when value is BigDecimal zero' do
      it 'is not missing' do
        expect(type.missing?(BigDecimal('0'))).to be false
      end
    end

    context 'when value is non-zero' do
      it 'is not missing' do
        expect(type.missing?(BigDecimal('3.14'))).to be false
      end
    end
  end

  describe 'reporting ruby_type' do
    it 'returns the top-level BigDecimal class' do
      expect(type.ruby_type).to eq(BigDecimal)
    end
  end
end
