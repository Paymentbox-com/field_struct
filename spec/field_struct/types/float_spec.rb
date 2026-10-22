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

  describe 'parsing a string in base 10 only' do
    it 'refuses a hex prefix, as :integer does' do
      %w[0x1A 0X1a -0x1A +0x10 0x1p3].each do |string|
        expect { type.coerce(string) }.to raise_error(ArgumentError)
      end
      expect { type.coerce(' 0x1A ') }.to raise_error(ArgumentError)
    end

    it 'still refuses binary and octal prefixes' do
      %w[0b101 0o17 0B1 0O7].each do |string|
        expect { type.coerce(string) }.to raise_error(ArgumentError)
      end
    end

    it 'keeps every other Kernel#Float string form' do
      {'1_000.5' => 1000.5, ' 2.5 ' => 2.5, '1e3' => 1000.0, '017' => 17.0,
       '.5' => 0.5, '5.' => 5.0, '-0.25' => -0.25, '0' => 0.0}.each do |string, expected|
        expect(type.coerce(string)).to eq(expected)
      end
    end

    it 'names the class in the message, never the value' do
      expect { type.coerce('0x1A') }.to raise_error(ArgumentError, /base-10/) { |error|
        expect(error.message).to include('String')
        expect(error.message).not_to include('0x1A')
      }
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
