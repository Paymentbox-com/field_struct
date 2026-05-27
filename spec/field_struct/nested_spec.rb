# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'nested FieldStructs' do
  let(:address_class) do
    Class.new(described_class) do
      required :street, :string
      required :city, :string
    end
  end

  describe 'declaring a nested field with a class argument' do
    let(:person_class) do
      addr = address_class
      Class.new(described_class) do
        required :name, :string
        required :address, addr
      end
    end

    it 'records the resolved nested type on the Field' do
      field = person_class.metadata[:address]
      expect(field.type).to eq(FieldStruct::Types::Nested)
      expect(field.type_instance.struct_class).to equal(address_class)
    end

    it 'constructs the nested struct from a hash input' do
      person = person_class.new(name: 'Alice', address: {street: '1', city: 'NYC'})
      expect(person.address).to be_a(address_class)
      expect(person.address.street).to eq('1')
    end

    it 'passes through an existing instance' do
      addr = address_class.new(street: '1', city: 'NYC')
      person = person_class.new(name: 'Alice', address: addr)
      expect(person.address).to equal(addr)
    end

    it 'records a coercion error under default :keep_raw on a non-Hash non-instance value' do
      person = person_class.new(name: 'Alice', address: 42)
      expect(person.errors[:address]).to include(/coerce/)
      expect(person.address).to eq(42)
    end
  end

  describe 'symbol form via the registry' do
    it 'resolves to Types::Nested when the registered value is a FieldStruct::Base subclass' do
      addr = address_class
      stub_const('NestedSpecRegistry', Module.new)
      NestedSpecRegistry.define_singleton_method(:field_types) do
        @field_types ||= FieldStruct::Registry.new(FieldStruct.types)
      end
      # Register the FieldStruct subclass itself under a symbolic name —
      # the DSL detects this and wraps the resolved class in Nested,
      # so the symbol form participates in the registry chain without
      # needing the user to know about Nested.
      NestedSpecRegistry.field_types.register(:address, addr)

      person_class = Class.new(described_class)
      stub_const('NestedSpecRegistry::Person', person_class)
      person_class.class_eval do
        required :name, :string
        required :address, :address
      end

      expect(person_class.metadata[:address].type).to eq(FieldStruct::Types::Nested)
      expect(person_class.new(name: 'A', address: {street: '1', city: 'NYC'}).address).to be_a(addr)
    end
  end

  describe 'eager validity propagation' do
    let(:person_class) do
      addr = address_class
      Class.new(described_class) do
        required :address, addr
      end
    end

    context 'when the assigned nested struct is invalid' do
      it 'stamps "is invalid" on the parent at assignment time' do
        person = person_class.new(address: {street: '1', city: ''})
        expect(person.errors[:address]).to eq(['is invalid'])
        expect(person).to be_invalid
      end
    end

    context 'when the assigned nested struct is valid' do
      it 'does not stamp the error' do
        person = person_class.new(address: {street: '1', city: 'NYC'})
        expect(person.errors[:address]).to be_empty
        expect(person).to be_valid
      end
    end

    context 'after the setter is called again with a good value' do
      it 'clears the prior "is invalid" stamp' do
        person = person_class.new(address: {street: '1', city: ''})
        expect(person.errors[:address]).not_to be_empty
        person.address = {street: '1', city: 'NYC'}
        expect(person.errors[:address]).to be_empty
      end
    end

    context 'when the assigned value is nil and the field is required' do
      it 'records "is required" (not "is invalid")' do
        person = person_class.new(address: nil)
        expect(person.errors[:address]).to eq(['is required'])
      end
    end

    context 'after nested mutation (eager option A semantics)' do
      it 'does not auto-refresh — Phase 1 setter-owns-errors contract is preserved' do
        person = person_class.new(address: {street: '1', city: 'NYC'})
        expect(person).to be_valid
        person.address.city = ''
        # Parent's errors are stale by design (option A from the design
        # walkthrough). Drilling into the nested gives the truth.
        expect(person.errors[:address]).to be_empty
        expect(person.address.errors[:city]).to include('is required')
      end
    end
  end

  describe 'inner construction errors propagate' do
    context 'when the nested class has unknown_attributes :raise' do
      let(:strict_address) do
        Class.new(described_class) do
          unknown_attributes :raise
          required :street, :string
        end
      end
      let(:person_class) do
        addr = strict_address
        Class.new(described_class) { required :address, addr }
      end

      it 'lets the UnknownAttributeError surface to the caller' do
        expect { person_class.new(address: {street: '1', extra: 'x'}) }
          .to raise_error(FieldStruct::UnknownAttributeError, /extra/)
      end
    end

    context 'when the nested class has coercion_policy :raise' do
      let(:strict_address) do
        Class.new(described_class) do
          coercion_policy :raise
          required :zip, :integer
        end
      end
      let(:person_class) do
        addr = strict_address
        Class.new(described_class) { required :address, addr }
      end

      it 'lets the CoercionError surface to the caller' do
        expect { person_class.new(address: {zip: 'not a number'}) }
          .to raise_error(FieldStruct::CoercionError)
      end
    end
  end

  describe 'parent coercion_policy applies to shape-level rejection' do
    let(:person_class) do
      addr = address_class
      Class.new(described_class) do
        coercion_policy :keep_raw
        required :address, addr
      end
    end

    it 'records a coercion error on a non-Hash non-instance value' do
      person = person_class.new(address: 42)
      expect(person.errors[:address]).to include(/coerce/)
      expect(person.address).to eq(42) # raw kept
    end
  end

  describe 'equality with nested' do
    let(:person_class) do
      addr = address_class
      Class.new(described_class) do
        required :name, :string
        required :address, addr
      end
    end

    it 'is == when class and attribute values (including nested) match' do
      a = person_class.new(name: 'Alice', address: {street: '1', city: 'NYC'})
      b = person_class.new(name: 'Alice', address: {street: '1', city: 'NYC'})
      expect(a).to eq(b)
    end

    it 'is not == when a nested attribute differs' do
      a = person_class.new(name: 'Alice', address: {street: '1', city: 'NYC'})
      b = person_class.new(name: 'Alice', address: {street: '2', city: 'NYC'})
      expect(a).not_to eq(b)
    end
  end

  describe 'as_json deep-walks nested' do
    let(:person_class) do
      addr = address_class
      Class.new(described_class) do
        required :name, :string
        required :address, addr
      end
    end

    it 'returns a hash with the nested as_json substructure' do
      person = person_class.new(name: 'Alice', address: {street: '1', city: 'NYC'})
      expect(person.as_json).to eq(
        name: 'Alice',
        address: {street: '1', city: 'NYC'}
      )
    end

    it 'to_json roundtrips through Oj' do
      person = person_class.new(name: 'Alice', address: {street: '1', city: 'NYC'})
      parsed = Oj.load(person.to_json, mode: :compat)
      expect(parsed.dig('address', 'city')).to eq('NYC')
    end
  end

  describe 'array of nested FieldStructs' do
    let(:contact_book_class) do
      addr = address_class
      Class.new(described_class) do
        required :addresses, :array, of: addr
      end
    end

    it 'coerces each hash element into a nested instance' do
      book = contact_book_class.new(
        addresses: [
          {street: '1', city: 'NYC'},
          {street: '2', city: 'LA'}
        ]
      )
      expect(book.addresses.size).to eq(2)
      expect(book.addresses.first).to be_a(address_class)
      expect(book.addresses.last.city).to eq('LA')
    end

    it 'passes through instances mixed with hashes' do
      pre_built = address_class.new(street: '0', city: 'SEA')
      book = contact_book_class.new(addresses: [pre_built, {street: '1', city: 'NYC'}])
      expect(book.addresses.first).to equal(pre_built)
      expect(book.addresses.last).to be_a(address_class)
    end

    it 'stamps the parent invalid when any element is invalid' do
      book = contact_book_class.new(
        addresses: [
          {street: '1', city: 'NYC'},
          {street: '2', city: ''}
        ]
      )
      expect(book.errors[:addresses]).to eq(['is invalid'])
    end

    it 'is valid when every element is valid' do
      book = contact_book_class.new(
        addresses: [
          {street: '1', city: 'NYC'},
          {street: '2', city: 'LA'}
        ]
      )
      expect(book).to be_valid
    end

    it 'deep-walks as_json over array of nested' do
      book = contact_book_class.new(
        addresses: [{street: '1', city: 'NYC'}, {street: '2', city: 'LA'}]
      )
      expect(book.as_json[:addresses]).to eq([
        {street: '1', city: 'NYC'},
        {street: '2', city: 'LA'}
      ])
    end
  end
end
