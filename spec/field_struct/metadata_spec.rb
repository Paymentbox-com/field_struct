# frozen_string_literal: true

RSpec.describe FieldStruct::Metadata do
  let(:string_type) { FieldStruct::Types::String }
  let(:integer_type) { FieldStruct::Types::Integer }
  let(:name_field) { FieldStruct::Field.new(name: :name, type: string_type, required: true) }
  let(:age_field) { FieldStruct::Field.new(name: :age, type: integer_type) }

  describe 'an empty metadata' do
    let(:metadata) { described_class.new }

    it 'has no names' do
      expect(metadata.names).to eq([])
    end

    it 'returns nil for a non-existent lookup' do
      expect(metadata[:nope]).to be_nil
    end

    it 'yields nothing when iterated' do
      expect { |b| metadata.each(&b) }.not_to yield_control
    end
  end

  describe 'adding fields' do
    let(:metadata) { described_class.new }

    before do
      metadata.add(name_field)
      metadata.add(age_field)
    end

    it 'looks up a field by name' do
      expect(metadata[:name]).to equal(name_field)
      expect(metadata[:age]).to equal(age_field)
    end

    it 'accepts string-form names on lookup' do
      expect(metadata['name']).to equal(name_field)
    end

    it 'reports names in insertion order' do
      expect(metadata.names).to eq(%i[name age])
    end

    it 'iterates fields in insertion order' do
      yielded = metadata.map { |f| f }
      expect(yielded).to eq([name_field, age_field])
    end

    context 'when add is called again with the same name' do
      it 'overwrites the prior field' do
        replacement = FieldStruct::Field.new(name: :name, type: integer_type)
        metadata.add(replacement)
        expect(metadata[:name]).to equal(replacement)
      end

      it 'keeps the original insertion position' do
        replacement = FieldStruct::Field.new(name: :name, type: integer_type)
        metadata.add(replacement)
        expect(metadata.names).to eq(%i[name age])
      end
    end
  end

  describe 'merging parent metadata' do
    let(:parent) do
      described_class.new.tap do |m|
        m.add(FieldStruct::Field.new(name: :id, type: integer_type))
        m.add(FieldStruct::Field.new(name: :name, type: string_type))
      end
    end
    let(:child) { described_class.new }

    it 'adds parent fields the child does not have' do
      child.merge(parent)
      expect(child.names).to eq(%i[id name])
    end

    it 'returns self for chaining' do
      expect(child.merge(parent)).to equal(child)
    end

    context 'when the child already declares a name that the parent also declares' do
      it 'keeps the child field — the child wins' do
        child_name = FieldStruct::Field.new(name: :name, type: integer_type)
        child.add(child_name)
        child.merge(parent)
        expect(child[:name]).to equal(child_name)
      end

      it 'preserves the parent fields not shadowed by the child' do
        child.add(FieldStruct::Field.new(name: :name, type: integer_type))
        child.merge(parent)
        expect(child.names).to include(:id)
      end
    end
  end
end
