# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Boolean do
  let(:type) { described_class.new }

  describe 'coercing input to a boolean' do
    context 'with literal true' do
      it 'returns true' do
        expect(type.coerce(true)).to be true
      end
    end

    context 'with literal false' do
      it 'returns false' do
        expect(type.coerce(false)).to be false
      end
    end

    context 'with truthy strings' do
      it 'returns true' do
        expect(type.coerce('true')).to be true
        expect(type.coerce('TRUE')).to be true
        expect(type.coerce('1')).to be true
      end
    end

    context 'with falsey strings' do
      it 'returns false' do
        expect(type.coerce('false')).to be false
        expect(type.coerce('FALSE')).to be false
        expect(type.coerce('0')).to be false
      end
    end

    context 'with numeric 1 and 0' do
      it 'maps to the matching boolean' do
        expect(type.coerce(1)).to be true
        expect(type.coerce(0)).to be false
      end
    end

    context 'with nil' do
      it 'returns nil' do
        expect(type.coerce(nil)).to be_nil
      end
    end

    context 'with a non-coercible value' do
      it 'raises ArgumentError for unsupported strings' do
        expect { type.coerce('maybe') }.to raise_error(ArgumentError)
      end

      it 'raises ArgumentError for unsupported numbers' do
        expect { type.coerce(2) }.to raise_error(ArgumentError)
      end

      it 'raises ArgumentError for unsupported types' do
        expect { type.coerce(:yes) }.to raise_error(ArgumentError)
      end
    end
  end

  describe 'reporting missing values' do
    context 'when value is nil' do
      it 'is missing' do
        expect(type.missing?(nil)).to be true
      end
    end

    context 'when value is false' do
      it 'is not missing' do
        expect(type.missing?(false)).to be false
      end
    end

    context 'when value is true' do
      it 'is not missing' do
        expect(type.missing?(true)).to be false
      end
    end
  end

  describe 'reporting ruby_type' do
    it 'returns the TrueClass/FalseClass pair' do
      expect(type.ruby_type).to eq([TrueClass, FalseClass])
    end
  end
end
