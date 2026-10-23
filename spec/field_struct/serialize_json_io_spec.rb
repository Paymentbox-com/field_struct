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

  # from_json reuses the reverse (external -> field) map between calls, so
  # each of these reads once BEFORE the mapping changes and checks that the
  # read after it sees the change.
  describe 'from_json after a mapping changes' do
    let(:parent) do
      Class.new(described_class) do
        required :first_name, :string
        optional :nick, :string
        serialize :json, first_name: 'firstName'
      end
    end

    it 'honours a serialize the subclass declares after the parent was read' do
      parent.from_json('{"firstName":"Al"}')
      child = Class.new(parent)
      child.from_json('{"firstName":"Al"}')
      child.serialize :json, first_name: 'given', nick: 'handle'

      expect(child.from_json('{"given":"Al","handle":"A"}').attributes).to eq(first_name: 'Al', nick: 'A')
      expect(parent.from_json('{"firstName":"Al","handle":"A"}').attributes).to eq(first_name: 'Al', nick: nil)
    end

    it 'honours a serialize that replaces the mapping on the class already read' do
      parent.from_json('{"firstName":"Al"}')
      parent.serialize :json, first_name: 'given'

      expect(parent.from_json('{"given":"Al"}').first_name).to eq('Al')
      expect(parent.from_json('{"firstName":"Al"}').first_name).to be_nil
    end

    it 'gives a subclass created after a read the mapping it inherits' do
      parent.from_json('{"firstName":"Al"}')
      expect(Class.new(parent).from_json('{"firstName":"Al"}').first_name).to eq('Al')
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

  describe 'unions of nested FieldStructs with serialize :json' do
    # unknown_attributes :raise lets the union tell the members apart: a
    # member handed the other member's keys raises, so the next one is tried.
    let(:card) do
      Class.new(described_class) do
        unknown_attributes :raise
        required :card_number, :string
        serialize :json, card_number: 'cardNumber'
      end
    end
    let(:bank) do
      Class.new(described_class) do
        unknown_attributes :raise
        required :account_number, :string
        serialize :json, account_number: 'accountNumber'
      end
    end
    let(:payment) do
      members = [card, bank]
      Class.new(described_class) do
        required :source, :union, of: members
      end
    end

    it 'reverse-maps the first member' do
      instance = payment.from_json('{"source":{"cardNumber":"4242"}}')
      expect(instance.source).to eq(card.new(card_number: '4242'))
      expect(instance).to be_valid
    end

    it 'reverse-maps a later member with its own mapping' do
      instance = payment.from_json('{"source":{"accountNumber":"99"}}')
      expect(instance.source).to eq(bank.new(account_number: '99'))
      expect(instance).to be_valid
    end

    it 'round-trips either member through to_json / from_json' do
      [card.new(card_number: '4242'), bank.new(account_number: '99')].each do |source|
        original = payment.new(source: source)
        expect(payment.from_json(original.to_json)).to eq(original)
      end
    end

    it 'reverse-maps a struct member alongside a scalar member' do
      nested = card
      loose = Class.new(described_class) { required :payload, :union, of: [nested, :boolean] }
      original = loose.new(payload: card.new(card_number: '1'))

      expect(loose.from_json(original.to_json)).to eq(original)
      expect(loose.from_json('{"payload":true}').payload).to be(true)
    end

    it 'moves past an earlier scalar member that rejects the Hash' do
      nested = card
      klass = Class.new(described_class) { required :payload, :union, of: [:integer, nested] }
      original = klass.new(payload: card.new(card_number: '1'))

      expect(klass.from_json(original.to_json)).to eq(original)
    end

    it 'keeps declared order: an earlier non-struct member that accepts the Hash wins' do
      nested = card
      klass = Class.new(described_class) { required :payload, :union, of: [:value, nested] }

      expect(klass.from_json('{"payload":{"cardNumber":"1"}}').payload).to eq('cardNumber' => '1')
    end

    it 'leaves the failure to coercion_policy when no member matches' do
      instance = payment.from_json('{"source":{"iban":"DE00"}}')
      expect(instance).not_to be_valid
      expect(instance.errors[:source].first).to start_with('could not be coerced')
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
