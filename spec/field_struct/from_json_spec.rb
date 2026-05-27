# frozen_string_literal: true

RSpec.describe FieldStruct::Base, '.from_json' do
  describe 'a simple scalar class' do
    let(:klass) do
      Class.new(described_class) do
        required :name, :string
        optional :age, :integer
      end
    end

    it 'builds an instance from a JSON object' do
      instance = klass.from_json('{"name":"Alice","age":30}')
      expect(instance.name).to eq('Alice')
      expect(instance.age).to eq(30)
    end

    it 'coerces JSON-string scalars through the type pipeline' do
      decimal_klass = Class.new(described_class) { optional :price, :decimal }
      instance = decimal_klass.from_json('{"price":"3.14"}')
      expect(instance.price).to eq(BigDecimal('3.14'))
    end

    it 'returns a valid instance when input satisfies the schema' do
      expect(klass.from_json('{"name":"Alice"}')).to be_valid
    end
  end

  describe 'roundtripping via to_json' do
    let(:klass) do
      Class.new(described_class) do
        required :name, :string
        required :age, :integer
        optional :balance, :decimal
        optional :on, :date
      end
    end

    it 'is structurally equal across to_json -> from_json' do
      original = klass.new(name: 'Alice', age: 30, balance: '99.50', on: '2024-01-15')
      restored = klass.from_json(original.to_json)
      expect(restored).to eq(original)
    end
  end

  describe 'nested FieldStruct fields' do
    let(:address_class) do
      Class.new(described_class) do
        required :street, :string
        required :city, :string
      end
    end
    let(:person_class) do
      addr = address_class
      Class.new(described_class) do
        required :name, :string
        required :address, addr
      end
    end

    it 'constructs the nested struct from a nested JSON object' do
      person = person_class.from_json('{"name":"Alice","address":{"street":"1","city":"NYC"}}')
      expect(person.address).to be_a(address_class)
      expect(person.address.city).to eq('NYC')
    end

    it 'roundtrips a nested structure' do
      original = person_class.new(name: 'Alice', address: {street: '1', city: 'NYC'})
      restored = person_class.from_json(original.to_json)
      expect(restored).to eq(original)
    end

    it 'roundtrips arrays of nested structs' do
      addr = address_class
      book_class = Class.new(described_class) do
        required :addresses, :array, of: addr
      end
      original = book_class.new(addresses: [
        {street: '1', city: 'NYC'},
        {street: '2', city: 'LA'}
      ])
      restored = book_class.from_json(original.to_json)
      expect(restored).to eq(original)
    end
  end

  describe 'error cases' do
    let(:klass) do
      Class.new(described_class) do
        optional :name, :string
      end
    end

    it 'raises ArgumentError when the JSON root is not an object' do
      expect { klass.from_json('[1, 2, 3]') }.to raise_error(ArgumentError, /JSON object root/)
      expect { klass.from_json('"hi"') }.to raise_error(ArgumentError, /JSON object root/)
      expect { klass.from_json('42') }.to raise_error(ArgumentError, /JSON object root/)
      expect { klass.from_json('null') }.to raise_error(ArgumentError, /JSON object root/)
    end

    it 'lets the parse error from invalid JSON propagate' do
      # Oj raises EncodingError (or Oj::ParseError which descends from it)
      # for malformed input. Either way it propagates from from_json.
      expect { klass.from_json('not json {') }.to raise_error(EncodingError)
    end
  end

  describe 'policy interaction' do
    it 'honors unknown_attributes :raise' do
      strict = Class.new(described_class) do
        unknown_attributes :raise
        optional :name, :string
      end
      expect { strict.from_json('{"name":"Alice","extra":"x"}') }
        .to raise_error(FieldStruct::UnknownAttributeError, /extra/)
    end

    it 'honors coercion_policy :raise' do
      strict = Class.new(described_class) do
        coercion_policy :raise
        optional :age, :integer
      end
      expect { strict.from_json('{"age":"not a number"}') }
        .to raise_error(FieldStruct::CoercionError)
    end
  end
end
