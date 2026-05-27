# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'field aliases' do
  let(:klass) do
    Class.new(described_class) do
      required :email, :string, aliases: %w[EmailAddress email_address]
      optional :age, :integer
    end
  end

  describe 'declaration' do
    it 'records aliases as a frozen array of symbols on the Field' do
      field = klass.metadata[:email]
      expect(field.aliases).to eq(%i[EmailAddress email_address])
      expect(field.aliases).to be_frozen
    end

    it 'leaves fields without aliases with an empty array' do
      expect(klass.metadata[:age].aliases).to eq([])
    end

    it 'does not retain :aliases in the Field options hash' do
      expect(klass.metadata[:email].options).not_to have_key(:aliases)
    end
  end

  describe 'import — single alias key' do
    it 'routes a string-keyed alias to the canonical field' do
      instance = klass.new('EmailAddress' => 'a@b.com')
      expect(instance.email).to eq('a@b.com')
    end

    it 'routes a symbol-keyed alias to the canonical field' do
      instance = klass.new(EmailAddress: 'a@b.com')
      expect(instance.email).to eq('a@b.com')
    end

    it 'routes any declared alias — including a second one' do
      instance = klass.new('email_address' => 'a@b.com')
      expect(instance.email).to eq('a@b.com')
    end

    it 'still accepts the canonical name' do
      instance = klass.new(email: 'a@b.com')
      expect(instance.email).to eq('a@b.com')
    end
  end

  describe 'import — conflict resolution' do
    it 'canonical wins when both canonical and alias are present' do
      instance = klass.new(email: 'canonical@x.com', EmailAddress: 'alias@x.com')
      expect(instance.email).to eq('canonical@x.com')
    end

    it 'canonical wins even when iteration would normally favor the alias' do
      # Reverse the input order: alias key first
      instance = klass.new(EmailAddress: 'alias@x.com', email: 'canonical@x.com')
      expect(instance.email).to eq('canonical@x.com')
    end
  end

  describe 'unknown_attributes :raise treats aliases as known' do
    let(:strict) do
      Class.new(described_class) do
        unknown_attributes :raise
        required :email, :string, aliases: ['EmailAddress']
      end
    end

    it 'does not raise on an alias key' do
      expect { strict.new(EmailAddress: 'a@b.com') }.not_to raise_error
    end

    it 'still raises on truly unknown keys' do
      expect { strict.new(EmailAddress: 'a@b.com', made_up: 'x') }
        .to raise_error(FieldStruct::UnknownAttributeError, /made_up/)
    end
  end

  describe 'no Ruby methods are defined for aliases' do
    it 'has no accessor under the alias name' do
      instance = klass.new(email: 'a@b.com')
      expect(instance.respond_to?(:EmailAddress)).to be false
      expect(instance.respond_to?(:email_address)).to be false
    end
  end

  describe 'export with aliased: true' do
    let(:instance) { klass.new(email: 'a@b.com', age: 30) }

    it 'attributes(aliased: true) uses the first alias per field' do
      expect(instance.attributes(aliased: true)).to eq(EmailAddress: 'a@b.com', age: 30)
    end

    it 'attributes() without aliased keeps canonical names' do
      expect(instance.attributes).to eq(email: 'a@b.com', age: 30)
    end

    it 'to_h(aliased: true) mirrors attributes(aliased: true)' do
      expect(instance.to_h(aliased: true)).to eq(EmailAddress: 'a@b.com', age: 30)
    end

    it 'as_json(aliased: true) keys with the first alias' do
      expect(instance.as_json(aliased: true)).to eq(EmailAddress: 'a@b.com', age: 30)
    end

    it 'to_json(aliased: true) produces JSON with the alias key' do
      parsed = Oj.load(instance.to_json(aliased: true), mode: :compat)
      expect(parsed.keys).to contain_exactly('EmailAddress', 'age')
    end

    it 'falls back to canonical for fields without an alias' do
      expect(instance.as_json(aliased: true)[:age]).to eq(30)
    end
  end

  describe 'round-trip through aliased export and import' do
    it 'survives aliased to_json -> from_json' do
      original = klass.new(email: 'a@b.com', age: 30)
      json = original.to_json(aliased: true)
      restored = klass.from_json(json)
      expect(restored).to eq(original)
    end
  end

  describe 'aliases with nested FieldStructs' do
    let(:address_class) do
      Class.new(described_class) do
        required :street, :string, aliases: ['StreetAddress']
        required :city, :string
      end
    end
    let(:person_class) do
      addr = address_class
      Class.new(described_class) do
        required :name, :string, aliases: ['Name']
        required :address, addr, aliases: ['Address']
      end
    end

    it 'imports aliased keys at every level' do
      person = person_class.new(
        Name: 'Alice',
        Address: {StreetAddress: '1 Main', city: 'NYC'}
      )
      expect(person.name).to eq('Alice')
      expect(person.address.street).to eq('1 Main')
      expect(person.address.city).to eq('NYC')
    end

    it 'exports aliased keys at every level' do
      person = person_class.new(
        name: 'Alice',
        address: {street: '1 Main', city: 'NYC'}
      )
      out = person.as_json(aliased: true)
      expect(out).to eq(
        Name: 'Alice',
        Address: {StreetAddress: '1 Main', city: 'NYC'}
      )
    end
  end
end
