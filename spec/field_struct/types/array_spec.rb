# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Array do
  let(:type) { described_class.new }

  describe 'coercing input' do
    context 'with an array and a string element type' do
      it 'returns each element coerced via the element type' do
        result = type.coerce([:a, :b, 1], of_type: FieldStruct::Types::String)
        expect(result).to eq(%w[a b 1])
      end
    end

    context 'with an array and an integer element type' do
      it 'coerces each element' do
        result = type.coerce(['1', 2, '3'], of_type: FieldStruct::Types::Integer)
        expect(result).to eq([1, 2, 3])
      end
    end

    context 'with an empty array' do
      it 'returns a new empty array' do
        expect(type.coerce([], of_type: FieldStruct::Types::String)).to eq([])
      end
    end

    context 'with one element that the element type rejects' do
      it 'propagates the element-type error' do
        expect do
          type.coerce(%w[1 bad], of_type: FieldStruct::Types::Integer)
        end.to raise_error(ArgumentError)
      end
    end

    context 'with nil' do
      it 'returns nil' do
        expect(type.coerce(nil, of_type: FieldStruct::Types::Integer)).to be_nil
      end
    end

    context 'with a non-array value' do
      it 'raises TypeError' do
        expect do
          type.coerce('not an array', of_type: FieldStruct::Types::Integer)
        end.to raise_error(TypeError)
      end
    end
  end

  describe 'reporting missing values' do
    it 'is missing when nil' do
      expect(type.missing?(nil)).to be true
    end

    it 'is missing when empty' do
      expect(type.missing?([])).to be true
    end

    it 'is not missing when populated' do
      expect(type.missing?(['a'])).to be false
      expect(type.missing?([nil])).to be false
    end
  end

  describe 'reporting ruby_type' do
    it 'returns the top-level Array class' do
      expect(type.ruby_type).to eq(Array)
    end
  end
end

RSpec.describe 'array field DSL' do
  describe 'declaring an array field with required of:' do
    let(:klass) do
      Class.new(FieldStruct::Base) do
        required :tags, :array, of: :string
      end
    end

    it 'coerces each element through the named element type' do
      instance = klass.new(tags: [:a, :b, 1])
      expect(instance.tags).to eq(%w[a b 1])
    end

    it 'reaches the element type via the registry chain (so :decimal works)' do
      decimal_klass = Class.new(FieldStruct::Base) do
        required :prices, :array, of: :decimal
      end
      result = decimal_klass.new(prices: ['1.50', '2.75']).prices
      expect(result).to eq([BigDecimal('1.50'), BigDecimal('2.75')])
    end

    context 'when the named element type is not registered' do
      it 'raises KeyError at class-declaration time' do
        expect do
          Class.new(FieldStruct::Base) { required :foo, :array, of: :nope_not_a_type }
        end.to raise_error(KeyError)
      end
    end
  end

  describe 'declaring an array field without of:' do
    it 'raises ArgumentError at class-declaration time' do
      expect do
        Class.new(FieldStruct::Base) { required :tags, :array }
      end.to raise_error(ArgumentError, /of:/)
    end
  end

  describe 'required + missing semantics' do
    let(:klass) do
      Class.new(FieldStruct::Base) do
        required :tags, :array, of: :string
      end
    end

    it 'records an error when nil' do
      instance = klass.new(tags: nil)
      expect(instance.errors[:tags]).to include(/required/)
    end

    it 'records an error when empty' do
      instance = klass.new(tags: [])
      expect(instance.errors[:tags]).to include(/required/)
    end

    it 'is valid when populated' do
      instance = klass.new(tags: ['hi'])
      expect(instance).to be_valid
    end
  end

  describe 'optional arrays' do
    let(:klass) do
      Class.new(FieldStruct::Base) do
        optional :tags, :array, of: :string
      end
    end

    it 'is valid with nil' do
      expect(klass.new(tags: nil)).to be_valid
    end

    it 'is valid with []' do
      expect(klass.new(tags: [])).to be_valid
    end
  end
end
