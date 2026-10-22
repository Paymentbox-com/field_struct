# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Integer do
  let(:type) { described_class.new }

  describe 'coercing input to an integer' do
    context 'with an integer value' do
      it 'returns the integer unchanged' do
        expect(type.coerce(42)).to eq(42)
      end
    end

    context 'with a string of digits' do
      it 'returns the parsed integer' do
        expect(type.coerce('42')).to eq(42)
        expect(type.coerce('-7')).to eq(-7)
      end
    end

    context 'with a float value' do
      it 'returns the truncated integer' do
        expect(type.coerce(3.14)).to eq(3)
        expect(type.coerce(-2.9)).to eq(-2)
      end
    end

    context 'with nil' do
      it 'returns nil' do
        expect(type.coerce(nil)).to be_nil
      end
    end

    context 'with a non-coercible string' do
      it 'raises ArgumentError' do
        expect { type.coerce('abc') }.to raise_error(ArgumentError)
      end

      it 'raises ArgumentError on a float-shaped string' do
        expect { type.coerce('3.14') }.to raise_error(ArgumentError)
      end
    end

    context 'with an unsupported type' do
      it 'raises TypeError' do
        expect { type.coerce(:hello) }.to raise_error(TypeError)
      end
    end
  end

  describe 'parsing a string in base 10 by default' do
    it 'reads a leading zero as decimal, not octal' do
      expect(type.coerce('010')).to eq(10)
      expect(type.coerce('007')).to eq(7)
    end

    it 'refuses a hex or binary prefix' do
      expect { type.coerce('0x1A') }.to raise_error(ArgumentError)
      expect { type.coerce('0b11') }.to raise_error(ArgumentError)
    end

    it 'accepts underscores between digits' do
      expect(type.coerce('1_000')).to eq(1000)
    end

    it 'accepts surrounding whitespace' do
      expect(type.coerce(' 42 ')).to eq(42)
    end

    it 'names the class in the message, never the value' do
      expect { type.coerce('0x1A') }.to raise_error(ArgumentError) { |error|
        expect(error.message).to include('String')
        expect(error.message).not_to include('0x1A')
      }
    end
  end

  describe 'parsing a string in a declared base' do
    it 'reads the digits in that base' do
      expect(type.coerce('1A', base: 16)).to eq(26)
      expect(type.coerce('11', base: 2)).to eq(3)
    end

    it 'refuses digits outside that base' do
      expect { type.coerce('12', base: 2) }.to raise_error(ArgumentError, /base-2/)
    end

    it 'treats base: nil as base 10' do
      expect(type.coerce('010', base: nil)).to eq(10)
    end

    it 'leaves non-string numerics alone' do
      expect(type.coerce(26, base: 16)).to eq(26)
      expect(type.coerce(3.9, base: 16)).to eq(3)
    end
  end

  describe 'reporting missing values' do
    context 'when value is nil' do
      it 'is missing' do
        expect(type.missing?(nil)).to be true
      end
    end

    context 'when value is zero' do
      it 'is not missing' do
        expect(type.missing?(0)).to be false
      end
    end

    context 'when value is a non-zero integer' do
      it 'is not missing' do
        expect(type.missing?(42)).to be false
        expect(type.missing?(-1)).to be false
      end
    end
  end

  describe 'reporting ruby_type' do
    it 'returns the top-level Integer class' do
      expect(type.ruby_type).to eq(Integer)
    end
  end
end
