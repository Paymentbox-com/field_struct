# frozen_string_literal: true

RSpec.describe FieldStruct::Types::String do
  let(:type) { described_class.new }

  describe 'coercing input to a string' do
    context 'with a string value' do
      it 'returns the string unchanged' do
        expect(type.coerce('hello')).to eq('hello')
      end
    end

    context 'with a symbol value' do
      it 'returns the symbol as a string' do
        expect(type.coerce(:hello)).to eq('hello')
      end
    end

    context 'with a numeric value' do
      it 'returns the to_s form' do
        expect(type.coerce(42)).to eq('42')
        expect(type.coerce(3.14)).to eq('3.14')
      end
    end

    context 'with nil' do
      it 'returns nil' do
        expect(type.coerce(nil)).to be_nil
      end
    end

    context 'with a whitespace string' do
      it 'preserves the whitespace' do
        expect(type.coerce('   ')).to eq('   ')
      end
    end
  end

  describe 'reporting missing values' do
    context 'when value is nil' do
      it 'is missing' do
        expect(type.missing?(nil)).to be true
      end
    end

    context 'when value is an empty string' do
      it 'is missing' do
        expect(type.missing?('')).to be true
      end
    end

    context 'when value is whitespace-only' do
      it 'is missing' do
        expect(type.missing?('   ')).to be true
        expect(type.missing?("\t\n")).to be true
      end
    end

    context 'when value is a non-empty string' do
      it 'is not missing' do
        expect(type.missing?('hello')).to be false
      end
    end

    context 'when value has whitespace surrounding non-whitespace' do
      it 'is not missing' do
        expect(type.missing?('  hello  ')).to be false
      end
    end
  end

  describe 'reporting ruby_type' do
    it 'returns the top-level String class' do
      expect(type.ruby_type).to eq(String)
    end
  end
end
