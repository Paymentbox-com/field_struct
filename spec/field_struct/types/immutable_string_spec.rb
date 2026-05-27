# frozen_string_literal: true

RSpec.describe FieldStruct::Types::ImmutableString do
  let(:type) { described_class.new }

  describe 'coercing input to a frozen string' do
    context 'with a string value' do
      it 'returns a frozen string equal to the input' do
        result = type.coerce('hello')
        expect(result).to eq('hello')
        expect(result).to be_frozen
      end
    end

    context 'with a symbol value' do
      it 'returns a frozen string form of the symbol' do
        result = type.coerce(:hello)
        expect(result).to eq('hello')
        expect(result).to be_frozen
      end
    end

    context 'with a numeric value' do
      it 'returns a frozen string form of the number' do
        result = type.coerce(42)
        expect(result).to eq('42')
        expect(result).to be_frozen
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

    context 'when value is empty or whitespace-only' do
      it 'is missing' do
        expect(type.missing?('')).to be true
        expect(type.missing?('  ')).to be true
      end
    end

    context 'when value is a non-empty string' do
      it 'is not missing' do
        expect(type.missing?('hello')).to be false
      end
    end
  end

  describe 'reporting ruby_type' do
    it 'returns the top-level String class' do
      expect(type.ruby_type).to eq(String)
    end
  end
end
