# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Float do
  let(:type) { described_class.new }

  describe 'coercing input to a float' do
    context 'with a float value' do
      it 'returns the float unchanged' do
        expect(type.coerce(3.14)).to eq(3.14)
      end
    end

    context 'with an integer value' do
      it 'returns the float form' do
        expect(type.coerce(42)).to eq(42.0)
      end
    end

    context 'with a numeric string' do
      it 'returns the parsed float' do
        expect(type.coerce('3.14')).to eq(3.14)
        expect(type.coerce('42')).to eq(42.0)
        expect(type.coerce('-2.5')).to eq(-2.5)
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

    context 'with an unsupported type' do
      it 'raises TypeError' do
        expect { type.coerce(:hello) }.to raise_error(TypeError)
      end
    end
  end

  describe 'reporting missing values' do
    context 'when value is nil' do
      it 'is missing' do
        expect(type.missing?(nil)).to be true
      end
    end

    context 'when value is 0.0' do
      it 'is not missing' do
        expect(type.missing?(0.0)).to be false
      end
    end

    context 'when value is a non-zero float' do
      it 'is not missing' do
        expect(type.missing?(3.14)).to be false
      end
    end
  end

  describe 'reporting ruby_type' do
    it 'returns the top-level Float class' do
      expect(type.ruby_type).to eq(Float)
    end
  end
end
