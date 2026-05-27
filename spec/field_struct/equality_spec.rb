# frozen_string_literal: true

require 'set'

RSpec.describe FieldStruct::Base, 'structural equality and hashing' do
  let(:klass) do
    Class.new(described_class) do
      optional :name, :string
      optional :age, :integer
    end
  end

  describe '#==' do
    it 'is true for two instances of the same class with equal attributes' do
      a = klass.new(name: 'Alice', age: 30)
      b = klass.new(name: 'Alice', age: 30)
      expect(a).to eq(b)
    end

    it 'is false when an attribute differs' do
      a = klass.new(name: 'Alice', age: 30)
      b = klass.new(name: 'Alice', age: 31)
      expect(a).not_to eq(b)
    end

    it 'is false across different FieldStruct classes even with the same attributes' do
      other = Class.new(described_class) do
        optional :name, :string
        optional :age, :integer
      end
      expect(klass.new(name: 'Alice', age: 30)).not_to eq(other.new(name: 'Alice', age: 30))
    end

    it 'is false against an instance of a subclass with the same shape' do
      sub = Class.new(klass)
      expect(klass.new(name: 'Alice')).not_to eq(sub.new(name: 'Alice'))
    end

    it 'ignores errors — two equal-value instances are equal regardless of validity' do
      strict = Class.new(described_class) do
        required :name, :string
      end
      invalid_a = strict.new(name: '')
      invalid_b = strict.new(name: '')
      expect(invalid_a).not_to be_valid
      expect(invalid_a).to eq(invalid_b)
    end
  end

  describe '#eql?' do
    it 'is aliased to ==' do
      a = klass.new(name: 'Alice')
      b = klass.new(name: 'Alice')
      expect(a.eql?(b)).to be true
    end
  end

  describe '#hash' do
    it 'is equal for equal instances' do
      a = klass.new(name: 'Alice', age: 30)
      b = klass.new(name: 'Alice', age: 30)
      expect(a.hash).to eq(b.hash)
    end

    it 'lets instances dedupe inside a Set' do
      a = klass.new(name: 'Alice', age: 30)
      b = klass.new(name: 'Alice', age: 30)
      c = klass.new(name: 'Bob', age: 30)
      expect(Set.new([a, b, c]).size).to eq(2)
    end

    it 'lets instances be used as Hash keys' do
      a = klass.new(name: 'Alice', age: 30)
      lookup = {a => 'first'}
      expect(lookup[klass.new(name: 'Alice', age: 30)]).to eq('first')
    end
  end

  describe '#dup' do
    it 'returns an instance with the same attributes' do
      original = klass.new(name: 'Alice', age: 30)
      copy = original.dup
      expect(copy.attributes).to eq(original.attributes)
    end

    it 'is equal to the original' do
      original = klass.new(name: 'Alice', age: 30)
      expect(original.dup).to eq(original)
    end

    it 'does not share attribute mutations with the original' do
      original = klass.new(name: 'Alice', age: 30)
      copy = original.dup
      copy.name = 'Bob'
      expect(original.name).to eq('Alice')
    end

    it 'carries the immutable flag (because it is class-level)' do
      immutable_klass = Class.new(described_class) do
        immutable!
        optional :name, :string
      end
      original = immutable_klass.new(name: 'Alice')
      copy = original.dup
      expect { copy.name = 'B' }.to raise_error(FieldStruct::ImmutableError)
    end
  end
end
