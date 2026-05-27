# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Value do
  let(:type) { described_class.new }

  describe 'coercing input' do
    context 'with any non-nil value' do
      it 'returns the value untouched' do
        obj = Object.new
        expect(type.coerce(obj)).to equal(obj)
        expect(type.coerce('hello')).to eq('hello')
        expect(type.coerce(42)).to eq(42)
        expect(type.coerce(true)).to be true
        expect(type.coerce(false)).to be false
        expect(type.coerce({a: 1})).to eq({a: 1})
        expect(type.coerce([1, 2])).to eq([1, 2])
      end
    end

    context 'with nil' do
      it 'returns nil' do
        expect(type.coerce(nil)).to be_nil
      end
    end
  end

  describe 'reporting missing values' do
    context 'when value is nil' do
      it 'is missing' do
        expect(type.missing?(nil)).to be true
      end
    end

    context 'when value is empty but not nil' do
      it 'is not missing' do
        expect(type.missing?('')).to be false
        expect(type.missing?([])).to be false
        expect(type.missing?({})).to be false
      end
    end

    context 'when value is false' do
      it 'is not missing' do
        expect(type.missing?(false)).to be false
      end
    end
  end

  describe 'reporting ruby_type' do
    it 'returns Object — the broadest sensible class' do
      expect(type.ruby_type).to eq(Object)
    end
  end
end
