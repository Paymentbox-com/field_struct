# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'unknown_attributes macro' do
  describe 'the class macro' do
    it 'defaults to :ignore on Base' do
      expect(described_class.unknown_attributes).to eq(:ignore)
    end

    it 'lets a subclass set its own policy' do
      klass = Class.new(described_class) { unknown_attributes :raise }
      expect(klass.unknown_attributes).to eq(:raise)
    end

    it 'is inherited by descendants' do
      parent = Class.new(described_class) { unknown_attributes :raise }
      child = Class.new(parent)
      expect(child.unknown_attributes).to eq(:raise)
    end

    it 'lets a descendant override the parent' do
      parent = Class.new(described_class) { unknown_attributes :raise }
      child = Class.new(parent) { unknown_attributes :ignore }
      expect(child.unknown_attributes).to eq(:ignore)
    end

    it 'rejects an unknown policy name' do
      expect { Class.new(described_class) { unknown_attributes :explode } }
        .to raise_error(ArgumentError, /unknown unknown_attributes policy/i)
    end
  end

  describe 'policy :ignore (default)' do
    let(:klass) do
      Class.new(described_class) do
        optional :name, :string
      end
    end

    it 'silently accepts extra keys' do
      expect { klass.new(name: 'Alice', extra: 'whatever') }.not_to raise_error
    end

    it 'still assigns the known fields normally' do
      instance = klass.new(name: 'Alice', extra: 'whatever')
      expect(instance.name).to eq('Alice')
    end
  end

  describe 'policy :raise' do
    let(:klass) do
      Class.new(described_class) do
        unknown_attributes :raise
        optional :name, :string
      end
    end

    it 'raises UnknownAttributeError on an extra key' do
      expect { klass.new(name: 'Alice', extra: 'whatever') }
        .to raise_error(FieldStruct::UnknownAttributeError, /extra/)
    end

    it 'carries the unknown keys on the error' do
      klass.new(name: 'Alice', a: 1, b: 2)
    rescue FieldStruct::UnknownAttributeError => e
      expect(e.keys).to contain_exactly(:a, :b)
    end

    it 'still constructs cleanly with only declared keys' do
      expect(klass.new(name: 'Alice').name).to eq('Alice')
    end

    it 'treats string and symbol keys as the same field' do
      expect { klass.new('name' => 'Alice') }.not_to raise_error
    end
  end
end
