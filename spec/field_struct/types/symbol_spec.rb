# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Symbol do
  let(:type) { described_class.new }

  describe 'coercing input to a symbol' do
    it 'returns a Symbol unchanged' do
      expect(type.coerce(:hello)).to eq(:hello)
    end

    it 'coerces a String to a Symbol' do
      expect(type.coerce('hello')).to eq(:hello)
    end

    it 'returns nil for nil input' do
      expect(type.coerce(nil)).to be_nil
    end

    it 'raises TypeError on non-nil non-Symbol non-String input' do
      expect { type.coerce(42) }.to raise_error(TypeError)
      expect { type.coerce(true) }.to raise_error(TypeError)
      expect { type.coerce(Object.new) }.to raise_error(TypeError)
    end
  end

  describe 'reporting missing values' do
    it 'is missing only for nil' do
      expect(type.missing?(nil)).to be true
      expect(type.missing?(:hello)).to be false
      expect(type.missing?(:'')).to be false  # empty symbol still counts as present
    end
  end

  describe 'reporting ruby_type' do
    it 'returns the top-level Symbol class' do
      expect(type.ruby_type).to eq(Symbol)
    end
  end

  describe 'integration via the DSL' do
    let(:klass) do
      Class.new(FieldStruct::Base) { required :role, :symbol }
    end

    it 'is registered as :symbol on the base registry' do
      expect(klass.new(role: 'admin').role).to eq(:admin)
    end

    it 'passes a Symbol through' do
      expect(klass.new(role: :admin).role).to eq(:admin)
    end

    it 'is required-aware — nil counts as missing' do
      expect(klass.new(role: nil).errors[:role]).to include('is required')
    end
  end
end
