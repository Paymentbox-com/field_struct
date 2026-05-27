# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'pattern matching' do
  let(:user_class) do
    Class.new(described_class) do
      required :name, :string
      optional :age, :integer
    end
  end

  describe '#deconstruct_keys' do
    it 'returns every declared field when keys is nil' do
      instance = user_class.new(name: 'Alice', age: 30)
      expect(instance.deconstruct_keys(nil)).to eq(name: 'Alice', age: 30)
    end

    it 'returns only the requested subset when keys is an array' do
      instance = user_class.new(name: 'Alice', age: 30)
      expect(instance.deconstruct_keys(%i[name])).to eq(name: 'Alice')
    end

    it 'omits keys not declared on the class' do
      instance = user_class.new(name: 'Alice', age: 30)
      expect(instance.deconstruct_keys(%i[name nope])).to eq(name: 'Alice')
    end
  end

  describe '#deconstruct' do
    it 'returns values in declared field order' do
      instance = user_class.new(name: 'Alice', age: 30)
      expect(instance.deconstruct).to eq(['Alice', 30])
    end
  end

  describe 'hash pattern matching' do
    it 'matches on equality of a literal' do
      instance = user_class.new(name: 'Alice', age: 30)
      result = case instance
               in {name: 'Alice'}
                 :matched
               else
                 :fell_through
               end
      expect(result).to eq(:matched)
    end

    it 'binds variables in the pattern body' do
      instance = user_class.new(name: 'Alice', age: 30)
      result = case instance
               in {name:, age:}
                 "#{name}/#{age}"
               end
      expect(result).to eq('Alice/30')
    end

    it 'matches on type guards' do
      instance = user_class.new(name: 'Alice', age: 30)
      result = case instance
               in {age: Integer => age}
                 age * 2
               end
      expect(result).to eq(60)
    end

    it 'matches on Range' do
      adult = user_class.new(name: 'Adult', age: 30)
      minor = user_class.new(name: 'Kid', age: 12)
      expect(classify(adult)).to eq(:adult)
      expect(classify(minor)).to eq(:minor)
    end

    def classify(user)
      case user
      in {age: ..17}
        :minor
      in {age: 18..}
        :adult
      else
        :unknown
      end
    end

    it 'supports pinning with ^' do
      target_name = 'Alice'
      instance = user_class.new(name: 'Alice', age: 30)
      result = case instance
               in {name: ^target_name}
                 :matched
               else
                 :no
               end
      expect(result).to eq(:matched)
    end

    it 'falls through to the next branch when the value mismatches' do
      instance = user_class.new(name: 'Bob', age: 30)
      result = case instance
               in {name: 'Alice'}
                 :alice
               in {name: 'Bob'}
                 :bob
               end
      expect(result).to eq(:bob)
    end
  end

  describe 'array pattern matching' do
    let(:point_class) do
      Class.new(described_class) do
        required :x, :integer
        required :y, :integer
      end
    end

    it 'binds positional values in declared field order' do
      point = point_class.new(x: 3, y: 4)
      result = case point
               in [x, y]
                 Math.hypot(x, y)
               end
      expect(result).to eq(5.0)
    end

    it 'matches against literal positions' do
      point = point_class.new(x: 0, y: 0)
      result = case point
               in [0, 0]
                 :origin
               in [_, _]
                 :other
               end
      expect(result).to eq(:origin)
    end
  end

  describe 'nested patterns' do
    let(:address_class) do
      Class.new(described_class) do
        required :street, :string
        required :city, :string
      end
    end
    let(:order_class) do
      addr = address_class
      Class.new(described_class) do
        required :id, :integer
        required :address, addr
      end
    end

    it 'matches a nested FieldStruct value via deconstruct_keys' do
      order = order_class.new(id: 1, address: {street: '1', city: 'NYC'})
      result = case order
               in {address: {city: 'NYC'}}
                 :nyc
               in {address: {city: 'LA'}}
                 :la
               end
      expect(result).to eq(:nyc)
    end

    it 'binds nested fields' do
      order = order_class.new(id: 1, address: {street: '1', city: 'NYC'})
      result = case order
               in {address: {street:}}
                 street
               end
      expect(result).to eq('1')
    end
  end

  describe 'find patterns over arrays of nested' do
    let(:member_class) do
      Class.new(described_class) do
        required :name, :string
        required :role, :symbol
      end
    end
    let(:team_class) do
      member = member_class
      Class.new(described_class) do
        required :members, :array, of: member
      end
    end

    it 'locates an element with a matching shape' do
      team = team_class.new(members: [
        {name: 'Alice', role: :member},
        {name: 'Bob', role: :admin},
        {name: 'Carol', role: :member}
      ])

      result = case team
               in {members: [*, {role: :admin, name:} => _admin, *]}
                 name
               end

      expect(result).to eq('Bob')
    end
  end

  describe 'inheritance' do
    let(:parent) do
      Class.new(described_class) do
        required :id, :integer
        required :name, :string
      end
    end

    it 'subclass inherits the protocol and includes inherited fields' do
      child = Class.new(parent) { required :extra, :string }
      instance = child.new(id: 1, name: 'Alice', extra: 'x')

      result = case instance
               in {id:, name:, extra:}
                 [id, name, extra]
               end
      expect(result).to eq([1, 'Alice', 'x'])
    end
  end

  describe 'frozen-instance matching' do
    let(:klass) do
      Class.new(described_class) do
        frozen!
        required :name, :string
      end
    end

    it 'pattern-matches as a normal read' do
      instance = klass.new(name: 'Alice')
      expect(instance).to be_frozen

      result = case instance
               in {name: 'Alice'}
                 :ok
               end
      expect(result).to eq(:ok)
    end
  end

  describe 'aliases do not participate in pattern matching' do
    let(:klass) do
      Class.new(described_class) do
        required :email, :string, aliases: ['EmailAddress']
      end
    end

    it 'matches by canonical name' do
      instance = klass.new(email: 'a@b.com')
      result = case instance
               in {email:}
                 email
               end
      expect(result).to eq('a@b.com')
    end

    it 'omits alias keys from deconstruct_keys' do
      instance = klass.new(email: 'a@b.com')
      expect(instance.deconstruct_keys(nil)).to eq(email: 'a@b.com')
      expect(instance.deconstruct_keys(nil)).not_to have_key(:EmailAddress)
    end

    it 'fails to match a pattern keyed on the alias' do
      # Build the pattern hash explicitly because :EmailAddress with a
      # capital start can't be used as a hash-pattern key literal.
      instance = klass.new(email: 'a@b.com')
      pattern_keys = instance.deconstruct_keys(%i[EmailAddress])
      expect(pattern_keys).to eq({}) # nothing matched
    end
  end

  describe 'errors and validity do not participate in pattern matching' do
    let(:klass) do
      Class.new(described_class) do
        required :name, :string
      end
    end

    it 'does not expose errors via deconstruct_keys' do
      instance = klass.new(name: '')
      expect(instance.deconstruct_keys(nil)).to eq(name: '')
      expect(instance.deconstruct_keys(nil)).not_to have_key(:errors)
    end
  end
end
