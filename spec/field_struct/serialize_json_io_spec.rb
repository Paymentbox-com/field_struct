# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'serialize :json wiring' do
  describe 'as_json applies the :json mapping' do
    let(:klass) do
      Class.new(described_class) do
        required :email, :string
        required :first_name, :string
        required :last_name, :string

        serialize :json,
          first_name: 'firstName',
          last_name: 'lastName'
      end
    end

    it 'rewrites mapped keys to their external names' do
      instance = klass.new(email: 'a@b.com', first_name: 'Alice', last_name: 'Smith')
      expect(instance.as_json).to eq(
        email: 'a@b.com',
        firstName: 'Alice',
        lastName: 'Smith'
      )
    end

    it 'leaves unmapped fields with canonical keys' do
      instance = klass.new(email: 'a@b.com', first_name: 'Alice', last_name: 'Smith')
      expect(instance.as_json.keys).to include(:email)
    end

    it 'to_json produces external-keyed JSON' do
      instance = klass.new(email: 'a@b.com', first_name: 'Alice', last_name: 'Smith')
      parsed = Oj.load(instance.to_json, mode: :compat)
      expect(parsed.keys).to contain_exactly('email', 'firstName', 'lastName')
    end
  end

  describe 'classes without a serialize :json declaration' do
    let(:klass) do
      Class.new(described_class) do
        required :first_name, :string
        required :last_name, :string
      end
    end

    it 'as_json emits canonical names (identity mapping)' do
      instance = klass.new(first_name: 'Alice', last_name: 'Smith')
      expect(instance.as_json).to eq(first_name: 'Alice', last_name: 'Smith')
    end

    it 'to_json emits canonical names' do
      instance = klass.new(first_name: 'Alice', last_name: 'Smith')
      parsed = Oj.load(instance.to_json, mode: :compat)
      expect(parsed.keys).to contain_exactly('first_name', 'last_name')
    end
  end

  describe 'from_json reverse-maps via :json' do
    let(:klass) do
      Class.new(described_class) do
        required :email, :string
        required :first_name, :string
        required :last_name, :string

        serialize :json,
          first_name: 'firstName',
          last_name: 'lastName'
      end
    end

    it 'reads external keys and assigns to canonical fields' do
      instance = klass.from_json('{"email":"a@b.com","firstName":"Alice","lastName":"Smith"}')
      expect(instance.email).to eq('a@b.com')
      expect(instance.first_name).to eq('Alice')
      expect(instance.last_name).to eq('Smith')
    end

    it 'passes through unmapped keys (canonical-form input still works)' do
      instance = klass.from_json('{"email":"a@b.com","first_name":"Alice","last_name":"Smith"}')
      # First name is mapped, so 'first_name' (canonical) is unknown to the
      # reverse mapping and passes through. assign_attributes then sees
      # :first_name canonical. Works.
      expect(instance.first_name).to eq('Alice')
    end
  end

  describe 'round-trip — to_json then from_json' do
    let(:klass) do
      Class.new(described_class) do
        required :email, :string
        required :first_name, :string
        required :last_name, :string

        serialize :json,
          first_name: 'firstName',
          last_name: 'lastName'
      end
    end

    it 'preserves structural equality' do
      original = klass.new(email: 'a@b.com', first_name: 'Alice', last_name: 'Smith')
      restored = klass.from_json(original.to_json)
      expect(restored).to eq(original)
    end

    it 'preserves the JSON string exactly (modulo key ordering)' do
      original = klass.new(email: 'a@b.com', first_name: 'Alice', last_name: 'Smith')
      json = original.to_json
      restored = klass.from_json(json)
      expect(Oj.load(restored.to_json, mode: :compat)).to eq(Oj.load(json, mode: :compat))
    end
  end

  describe 'nested FieldStructs with their own serialize :json' do
    let(:address_class) do
      Class.new(described_class) do
        required :street, :string
        required :city, :string
        serialize :json, street: 'streetName'
      end
    end
    let(:user_class) do
      addr = address_class
      Class.new(described_class) do
        required :name, :string
        required :address, addr
      end
    end

    it 'as_json deep-walks each nested through its own mapping' do
      instance = user_class.new(name: 'Alice', address: {street: '1 Main', city: 'NYC'})
      expect(instance.as_json).to eq(
        name: 'Alice',
        address: {streetName: '1 Main', city: 'NYC'}
      )
    end

    it 'from_json recursively canonicalizes nested objects' do
      json = '{"name":"Alice","address":{"streetName":"1 Main","city":"NYC"}}'
      instance = user_class.from_json(json)
      expect(instance.address.street).to eq('1 Main')
      expect(instance.address.city).to eq('NYC')
    end

    it 'nested round-trip preserves equality' do
      original = user_class.new(name: 'Alice', address: {street: '1 Main', city: 'NYC'})
      restored = user_class.from_json(original.to_json)
      expect(restored).to eq(original)
    end
  end

  describe 'arrays of nested with serialize :json' do
    let(:address_class) do
      Class.new(described_class) do
        required :street, :string
        required :city, :string
        serialize :json, street: 'streetName'
      end
    end
    let(:book_class) do
      addr = address_class
      Class.new(described_class) do
        required :addresses, :array, of: addr
      end
    end

    it 'as_json applies each element\'s mapping' do
      instance = book_class.new(addresses: [
        {street: '1', city: 'NYC'},
        {street: '2', city: 'LA'}
      ])
      expect(instance.as_json).to eq(
        addresses: [
          {streetName: '1', city: 'NYC'},
          {streetName: '2', city: 'LA'}
        ]
      )
    end

    it 'from_json canonicalizes each element' do
      json = '{"addresses":[{"streetName":"1","city":"NYC"},{"streetName":"2","city":"LA"}]}'
      instance = book_class.from_json(json)
      expect(instance.addresses.first.street).to eq('1')
      expect(instance.addresses.last.city).to eq('LA')
    end

    it 'round-trips arrays of nested via the mapping' do
      original = book_class.new(addresses: [
        {street: '1', city: 'NYC'},
        {street: '2', city: 'LA'}
      ])
      restored = book_class.from_json(original.to_json)
      expect(restored).to eq(original)
    end
  end

  describe 'legacy aliased: true still works during the transition' do
    let(:klass) do
      Class.new(described_class) do
        required :first_name, :string, aliases: ['FirstName']
      end
    end

    it 'as_json(aliased: true) uses Field#export_name' do
      instance = klass.new(first_name: 'Alice')
      expect(instance.as_json(aliased: true)).to eq(FirstName: 'Alice')
    end

    it 'to_json(aliased: true) emits the alias key' do
      instance = klass.new(first_name: 'Alice')
      parsed = Oj.load(instance.to_json(aliased: true), mode: :compat)
      expect(parsed.keys).to eq(['FirstName'])
    end

    it 'from_json still accepts alias keys via legacy field_for path' do
      instance = klass.from_json('{"FirstName":"Alice"}')
      expect(instance.first_name).to eq('Alice')
    end
  end

  describe 'when a class declares BOTH legacy aliases and a serialize :json mapping' do
    let(:klass) do
      Class.new(described_class) do
        required :first_name, :string, aliases: ['OldName']
        serialize :json, first_name: 'firstName'
      end
    end

    it 'as_json uses the serialize mapping (new path wins for default)' do
      instance = klass.new(first_name: 'Alice')
      expect(instance.as_json).to eq(firstName: 'Alice')
    end

    it 'from_json prefers the serialize mapping for incoming keys' do
      instance = klass.from_json('{"firstName":"Alice"}')
      expect(instance.first_name).to eq('Alice')
    end

    it 'from_json still accepts the legacy alias because field_for handles it after pass-through' do
      instance = klass.from_json('{"OldName":"Alice"}')
      expect(instance.first_name).to eq('Alice')
    end

    it 'as_json(aliased: true) still uses the legacy export_name' do
      instance = klass.new(first_name: 'Alice')
      expect(instance.as_json(aliased: true)).to eq(OldName: 'Alice')
    end
  end

  describe 'to_h and attributes stay canonical regardless of serialize :json' do
    let(:klass) do
      Class.new(described_class) do
        required :first_name, :string
        serialize :json, first_name: 'firstName'
      end
    end

    it 'attributes always returns canonical names' do
      instance = klass.new(first_name: 'Alice')
      expect(instance.attributes).to eq(first_name: 'Alice')
    end

    it 'to_h always returns canonical names' do
      instance = klass.new(first_name: 'Alice')
      expect(instance.to_h).to eq(first_name: 'Alice')
    end
  end
end
