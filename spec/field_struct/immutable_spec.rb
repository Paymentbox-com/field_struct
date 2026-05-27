# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'immutable! macro' do
  describe 'default mutability' do
    let(:klass) { Class.new(described_class) { optional :name, :string } }

    it 'reports immutable? false' do
      expect(klass.immutable?).to be false
    end

    it 'allows reassignment after construction' do
      instance = klass.new(name: 'A')
      instance.name = 'B'
      expect(instance.name).to eq('B')
    end
  end

  describe 'an immutable! class' do
    let(:klass) do
      Class.new(described_class) do
        immutable!
        optional :name, :string
      end
    end

    it 'reports immutable? true' do
      expect(klass.immutable?).to be true
    end

    it 'still allows assignment during initialize' do
      expect(klass.new(name: 'A').name).to eq('A')
    end

    it 'blocks reassignment after construction' do
      instance = klass.new(name: 'A')
      expect { instance.name = 'B' }.to raise_error(FieldStruct::ImmutableError, /immutable/)
    end
  end

  describe 'inheritance' do
    it 'inherits immutable from an immutable parent' do
      parent = Class.new(described_class) { immutable! }
      child = Class.new(parent)
      expect(child.immutable?).to be true
    end

    it 'lets a child of a mutable parent opt in to immutability' do
      parent = Class.new(described_class) { optional :name, :string }
      child = Class.new(parent) { immutable! }
      expect(child.immutable?).to be true
      expect(parent.immutable?).to be false
    end

    it 'reflects parent mutability before the child opts in' do
      parent = Class.new(described_class)
      child = Class.new(parent)
      expect(child.immutable?).to be false
    end
  end

  describe 'interaction with coercion' do
    let(:klass) do
      Class.new(described_class) do
        immutable!
        optional :age, :integer
      end
    end

    it 'still coerces during initialize' do
      expect(klass.new(age: '42').age).to eq(42)
    end

    it 'blocks post-init coerced reassignment too' do
      instance = klass.new(age: 42)
      expect { instance.age = '99' }.to raise_error(FieldStruct::ImmutableError)
    end
  end
end
