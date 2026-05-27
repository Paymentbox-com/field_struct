# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Nested do
  let(:address_class) do
    Class.new(FieldStruct::Base) do
      required :street, :string
      required :city, :string
    end
  end
  let(:type) { described_class.new(address_class) }

  describe 'coercing input into the wrapped struct class' do
    context 'with an instance of the struct class' do
      it 'returns the same object' do
        instance = address_class.new(street: '123 Main', city: 'NYC')
        expect(type.coerce(instance)).to equal(instance)
      end
    end

    context 'with a subclass instance' do
      it 'returns the same object (Liskov passthrough)' do
        sub = Class.new(address_class)
        instance = sub.new(street: '1', city: 'NYC')
        expect(type.coerce(instance)).to equal(instance)
      end
    end

    context 'with a Hash' do
      it 'constructs the struct from the hash' do
        result = type.coerce(street: '1 Main', city: 'NYC')
        expect(result).to be_a(address_class)
        expect(result.street).to eq('1 Main')
        expect(result.city).to eq('NYC')
      end

      it 'still constructs (invalidly) when required keys are missing' do
        result = type.coerce({})
        expect(result).to be_a(address_class)
        expect(result).to be_invalid
      end
    end

    context 'with nil' do
      it 'returns nil' do
        expect(type.coerce(nil)).to be_nil
      end
    end

    context 'with an unrelated value' do
      it 'raises TypeError' do
        expect { type.coerce(42) }.to raise_error(TypeError)
        expect { type.coerce('hi') }.to raise_error(TypeError)
        expect { type.coerce(Object.new) }.to raise_error(TypeError)
      end
    end
  end

  describe 'reporting missing values' do
    it 'is missing only when nil' do
      expect(type.missing?(nil)).to be true
      expect(type.missing?(address_class.new)).to be false
    end
  end

  describe 'reporting ruby_type' do
    it 'returns the wrapped struct class' do
      expect(type.ruby_type).to equal(address_class)
    end
  end
end
