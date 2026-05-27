# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'assign_attributes' do
  let(:klass) do
    Class.new(described_class) do
      optional :name, :string
      optional :age, :integer
    end
  end

  describe 'as a public method' do
    it 'returns self' do
      instance = klass.new
      expect(instance.assign_attributes(name: 'Alice')).to equal(instance)
    end

    it 'updates the named attributes by running their setters' do
      instance = klass.new
      instance.assign_attributes(name: 'Alice', age: '30')
      expect(instance.name).to eq('Alice')
      expect(instance.age).to eq(30) # coerced through the integer type
    end

    it 'accepts string keys' do
      instance = klass.new
      instance.assign_attributes('name' => 'Alice')
      expect(instance.name).to eq('Alice')
    end

    it 'leaves untouched fields alone' do
      instance = klass.new(name: 'Alice', age: 1)
      instance.assign_attributes(age: 2)
      expect(instance.name).to eq('Alice')
      expect(instance.age).to eq(2)
    end
  end

  describe 'policy respect' do
    it 'respects unknown_attributes :raise on post-init bulk update' do
      strict = Class.new(described_class) do
        unknown_attributes :raise
        optional :name, :string
      end
      instance = strict.new(name: 'Alice')
      expect { instance.assign_attributes(extra: 'x') }
        .to raise_error(FieldStruct::UnknownAttributeError, /extra/)
    end

    it 'respects immutable! on post-init bulk update' do
      immutable = Class.new(described_class) do
        immutable!
        optional :name, :string
      end
      instance = immutable.new(name: 'Alice')
      expect { instance.assign_attributes(name: 'B') }
        .to raise_error(FieldStruct::ImmutableError)
    end

    it 'applies coercion_policy :replace per field' do
      replace_klass = Class.new(described_class) do
        coercion_policy :replace
        optional :age, :integer
      end
      instance = replace_klass.new(age: 10)
      instance.assign_attributes(age: 'bad')
      expect(instance.age).to be_nil
      expect(instance.errors[:age]).to include(/coerce/)
    end
  end

  describe 'initialize routed through assign_attributes' do
    let(:defaulted) do
      Class.new(described_class) do
        optional :name, :string, default: 'Anon'
        optional :age, :integer, default: 0
      end
    end

    it 'applies defaults for fields the user did not provide' do
      instance = defaulted.new(name: 'Alice')
      expect(instance.name).to eq('Alice')
      expect(instance.age).to eq(0)
    end

    it 'applies defaults for every field when no input is given' do
      instance = defaulted.new
      expect(instance.name).to eq('Anon')
      expect(instance.age).to eq(0)
    end
  end
end
