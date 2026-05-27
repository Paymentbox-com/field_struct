# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'field-level coercion_policy override' do
  describe 'declaration' do
    it 'stores the override on the Field' do
      klass = Class.new(described_class) do
        required :age, :integer, coercion_policy: :raise
      end
      expect(klass.metadata[:age].coercion_policy).to eq(:raise)
    end

    it 'leaves the override nil when not specified' do
      klass = Class.new(described_class) do
        required :age, :integer
      end
      expect(klass.metadata[:age].coercion_policy).to be_nil
    end

    it 'rejects an unknown override value at class load' do
      expect do
        Class.new(described_class) do
          required :age, :integer, coercion_policy: :explode
        end
      end.to raise_error(ArgumentError, /unknown coercion policy/i)
    end
  end

  describe ':raise on a single field, class default :keep_raw' do
    let(:klass) do
      Class.new(described_class) do
        coercion_policy :keep_raw
        required :age, :integer, coercion_policy: :raise
        optional :nick, :string
      end
    end

    it 'raises on the overridden field even though the class is lenient' do
      expect { klass.new(age: 'abc') }.to raise_error(FieldStruct::CoercionError, /age/)
    end

    it 'still keeps the lenient class default for other fields' do
      instance = klass.new(age: 42, nick: 'Alice')
      expect(instance).to be_valid
      # No way to fail a string coerce, but verifying the class default
      # path still resolves to :keep_raw on a different field.
      expect(klass.metadata[:nick].coercion_policy).to be_nil
    end
  end

  describe ':keep_raw on a single field, class default :raise' do
    let(:klass) do
      Class.new(described_class) do
        coercion_policy :raise
        required :strict_age, :integer
        optional :lenient_count, :integer, coercion_policy: :keep_raw
      end
    end

    it 'raises on the class-default field' do
      expect { klass.new(strict_age: 'abc') }.to raise_error(FieldStruct::CoercionError, /strict_age/)
    end

    it 'silently keeps raw on the overridden field' do
      instance = klass.new(strict_age: 1, lenient_count: 'abc')
      expect(instance.lenient_count).to eq('abc')
      expect(instance.errors[:lenient_count]).to include(/coerce/)
    end
  end

  describe ':replace on a single field' do
    let(:klass) do
      Class.new(described_class) do
        optional :age, :integer, coercion_policy: :replace
      end
    end

    it 'stores nil and records the coercion error' do
      instance = klass.new(age: 'abc')
      expect(instance.age).to be_nil
      expect(instance.errors[:age]).to include(/coerce/)
    end
  end

  describe 'inheritance' do
    let(:parent) do
      Class.new(described_class) do
        coercion_policy :keep_raw
        required :age, :integer, coercion_policy: :raise
      end
    end

    it 'the child inherits the override along with parent metadata' do
      child = Class.new(parent)
      expect(child.metadata[:age].coercion_policy).to eq(:raise)
    end

    it 'a child can shadow the field and remove the override' do
      child = Class.new(parent) do
        required :age, :integer # no override — defers to class
      end
      expect(child.metadata[:age].coercion_policy).to be_nil
    end
  end
end
