# frozen_string_literal: true

RSpec.describe FieldStruct::Base do
  describe 'the required/optional macros' do
    let(:klass) do
      Class.new(described_class) do
        required :name, :string
        optional :age, :integer
      end
    end

    it 'marks required fields' do
      expect(klass.metadata[:name].required?).to be true
    end

    it 'marks optional fields' do
      expect(klass.metadata[:age].required?).to be false
    end

    it 'still resolves the type and defines accessors like #field' do
      instance = klass.new(name: 'Alice', age: '30')
      expect(instance.name).to eq('Alice')
      expect(instance.age).to eq(30)
    end
  end

  describe 'presence validation on required fields' do
    let(:klass) do
      Class.new(described_class) do
        required :name, :string
        optional :age, :integer
      end
    end

    context 'with a present value' do
      it 'is valid? and has no errors' do
        instance = klass.new(name: 'Alice')
        expect(instance).to be_valid
        expect(instance.errors[:name]).to be_empty
      end
    end

    context 'with a missing value (per the type)' do
      it 'is invalid? and records an error' do
        instance = klass.new(name: '')
        expect(instance).to be_invalid
        expect(instance.errors[:name]).to include(/required/)
      end

      it 'records an error when no value is passed at all' do
        instance = klass.new
        expect(instance.errors[:name]).to include(/required/)
      end

      it 'records an error for whitespace-only strings (per String#missing?)' do
        instance = klass.new(name: '   ')
        expect(instance.errors[:name]).to include(/required/)
      end
    end

    context 'on a later assignment' do
      it 'clears a prior error once the value is present' do
        instance = klass.new(name: '')
        expect(instance.errors[:name]).not_to be_empty
        instance.name = 'Alice'
        expect(instance.errors[:name]).to be_empty
      end

      it 'introduces an error when a present value is cleared' do
        instance = klass.new(name: 'Alice')
        expect(instance.errors[:name]).to be_empty
        instance.name = nil
        expect(instance.errors[:name]).to include(/required/)
      end
    end

    context 'on an optional field' do
      it 'records no error even when missing' do
        instance = klass.new(name: 'Alice', age: nil)
        expect(instance.errors[:age]).to be_empty
        expect(instance).to be_valid
      end
    end
  end

  describe 'integer presence — zero is a valid integer' do
    let(:klass) do
      Class.new(described_class) do
        required :count, :integer
      end
    end

    it 'treats 0 as present' do
      instance = klass.new(count: 0)
      expect(instance.errors[:count]).to be_empty
      expect(instance).to be_valid
    end

    it 'treats nil as missing' do
      instance = klass.new(count: nil)
      expect(instance.errors[:count]).to include(/required/)
    end
  end

  describe 'setter owns its field' do
    let(:klass) do
      Class.new(described_class) do
        required :name, :string
        required :email, :string
      end
    end

    it 'mutating one field does not touch another field\'s errors' do
      instance = klass.new(name: '', email: '')
      expect(instance.errors[:name]).not_to be_empty
      expect(instance.errors[:email]).not_to be_empty

      instance.name = 'Alice'
      expect(instance.errors[:name]).to be_empty
      expect(instance.errors[:email]).not_to be_empty
    end
  end
end
