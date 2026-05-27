# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Union do
  describe 'coercing input — declared order wins' do
    let(:string_first) do
      described_class.new([FieldStruct::Types::String.new, FieldStruct::Types::Integer.new])
    end
    let(:integer_first) do
      described_class.new([FieldStruct::Types::Integer.new, FieldStruct::Types::String.new])
    end

    it 'returns the first successful member coercion' do
      expect(string_first.coerce('42')).to eq('42')
      expect(integer_first.coerce('42')).to eq(42)
    end

    it 'falls through to the next member when the first rejects' do
      union = described_class.new([FieldStruct::Types::Integer.new, FieldStruct::Types::String.new])
      expect(union.coerce('abc')).to eq('abc')
    end

    it 'returns nil for nil input' do
      expect(string_first.coerce(nil)).to be_nil
    end
  end

  describe 'when every member rejects' do
    let(:union) do
      described_class.new([FieldStruct::Types::Integer.new, FieldStruct::Types::Float.new])
    end

    it 'raises TypeError' do
      expect { union.coerce('abc') }.to raise_error(TypeError, /no union member/)
    end
  end

  describe 'reporting missing values' do
    let(:union) do
      described_class.new([FieldStruct::Types::String.new, FieldStruct::Types::Integer.new])
    end

    it 'is missing only for nil' do
      expect(union.missing?(nil)).to be true
      expect(union.missing?('')).to be false # union does not delegate to member missing?
      expect(union.missing?(0)).to be false
    end
  end

  describe 'reporting ruby_type' do
    it 'flattens member ruby_types into a single Array<Class>' do
      union = described_class.new([FieldStruct::Types::String.new, FieldStruct::Types::Boolean.new])
      expect(union.ruby_type).to eq([String, TrueClass, FalseClass])
    end

    it 'deduplicates overlapping ruby_types' do
      union = described_class.new([FieldStruct::Types::String.new, FieldStruct::Types::ImmutableString.new])
      expect(union.ruby_type).to eq([String])
    end
  end
end

RSpec.describe 'union field DSL' do
  describe 'declaring a union with scalar members' do
    let(:klass) do
      Class.new(FieldStruct::Base) do
        optional :payload, :union, of: %i[string integer]
      end
    end

    it 'records Types::Union as the field type' do
      expect(klass.metadata[:payload].type).to eq(FieldStruct::Types::Union)
    end

    it 'tries members in declared order' do
      expect(klass.new(payload: '42').payload).to eq('42') # string wins
    end

    it 'falls through to a later member when an earlier one rejects' do
      klass = Class.new(FieldStruct::Base) do
        optional :payload, :union, of: %i[integer string]
      end
      expect(klass.new(payload: 'abc').payload).to eq('abc')
    end
  end

  describe 'declaring a union with a nested FieldStruct member' do
    let(:payload_class) do
      Class.new(FieldStruct::Base) do
        required :kind, :string
        required :value, :integer
      end
    end
    let(:klass) do
      payload = payload_class
      Class.new(FieldStruct::Base) do
        optional :data, :union, of: [payload, :boolean]
      end
    end

    it 'constructs the nested struct from a Hash member input' do
      instance = klass.new(data: {kind: 'count', value: 10})
      expect(instance.data).to be_a(payload_class)
    end

    it 'passes a boolean through to the boolean member' do
      expect(klass.new(data: true).data).to be true
      expect(klass.new(data: false).data).to be false
    end

    it 'records a coercion error when no member can take the value' do
      instance = klass.new(data: 99) # neither Payload nor Boolean accepts 99
      expect(instance.errors[:data]).to include(/coerce/)
    end
  end

  describe 'declaration-time guards' do
    it 'raises when of: is missing' do
      expect do
        Class.new(FieldStruct::Base) { optional :x, :union }
      end.to raise_error(ArgumentError, /of:/)
    end

    it 'raises when of: is not an Array' do
      expect do
        Class.new(FieldStruct::Base) { optional :x, :union, of: :string }
      end.to raise_error(ArgumentError, /Array/)
    end

    it 'raises when of: has fewer than two members' do
      expect do
        Class.new(FieldStruct::Base) { optional :x, :union, of: [:string] }
      end.to raise_error(ArgumentError, /at least two/)
    end
  end

  describe 'interaction with required-presence' do
    let(:klass) do
      Class.new(FieldStruct::Base) do
        required :data, :union, of: %i[string integer]
      end
    end

    it 'records "is required" for nil on a required union' do
      expect(klass.new(data: nil).errors[:data]).to include('is required')
    end

    it 'is valid for any value that some member can coerce' do
      expect(klass.new(data: 'hello')).to be_valid
      expect(klass.new(data: 42)).to be_valid
    end
  end
end
