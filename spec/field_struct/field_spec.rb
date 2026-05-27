# frozen_string_literal: true

RSpec.describe FieldStruct::Field do
  let(:type_class) { FieldStruct::Types::String }

  describe 'constructing a field' do
    it 'stores the name as a symbol' do
      field = described_class.new(name: 'first_name', type: type_class)
      expect(field.name).to eq(:first_name)
    end

    it 'stores the resolved type class' do
      field = described_class.new(name: :first_name, type: type_class)
      expect(field.type).to eq(type_class)
    end

    it 'defaults required? to false' do
      field = described_class.new(name: :first_name, type: type_class)
      expect(field.required?).to be false
    end

    it 'honors required: true' do
      field = described_class.new(name: :first_name, type: type_class, required: true)
      expect(field.required?).to be true
    end

    it 'defaults default to nil' do
      field = described_class.new(name: :first_name, type: type_class)
      expect(field.default).to be_nil
    end

    it 'preserves an explicit default value' do
      field = described_class.new(name: :first_name, type: type_class, default: 'Anon')
      expect(field.default).to eq('Anon')
    end

    it 'collects extra keyword options into #options' do
      field = described_class.new(name: :email, type: type_class, format: /@/)
      expect(field.options).to include(format: /@/)
    end

    it 'freezes after construction' do
      field = described_class.new(name: :first_name, type: type_class)
      expect(field).to be_frozen
    end

    it 'freezes the options hash' do
      field = described_class.new(name: :email, type: type_class, format: /@/)
      expect(field.options).to be_frozen
    end

    it 'eagerly builds a type instance for the setter pipeline' do
      field = described_class.new(name: :first_name, type: type_class)
      expect(field.type_instance).to be_a(type_class)
    end
  end
end
