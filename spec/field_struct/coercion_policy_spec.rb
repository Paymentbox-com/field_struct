# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'coercion_policy' do
  describe 'the class macro' do
    it 'defaults to :keep_raw on Base' do
      expect(described_class.coercion_policy).to eq(:keep_raw)
    end

    it 'lets a subclass set its own policy' do
      klass = Class.new(described_class) { coercion_policy :raise }
      expect(klass.coercion_policy).to eq(:raise)
    end

    it 'is inherited by descendants' do
      parent = Class.new(described_class) { coercion_policy :replace }
      child = Class.new(parent)
      expect(child.coercion_policy).to eq(:replace)
    end

    it 'lets a descendant override the parent' do
      parent = Class.new(described_class) { coercion_policy :raise }
      child = Class.new(parent) { coercion_policy :keep_raw }
      expect(child.coercion_policy).to eq(:keep_raw)
    end

    it 'leaves the parent unchanged when a child overrides' do
      parent = Class.new(described_class) { coercion_policy :raise }
      Class.new(parent) { coercion_policy :keep_raw }
      expect(parent.coercion_policy).to eq(:raise)
    end

    it 'rejects an unknown policy name' do
      expect { Class.new(described_class) { coercion_policy :explode } }
        .to raise_error(ArgumentError, /unknown coercion policy/i)
    end
  end

  describe 'policy :keep_raw (default)' do
    let(:klass) do
      Class.new(described_class) do
        optional :age, :integer
      end
    end

    it 'stores the raw uncoercible value on the instance' do
      instance = klass.new(age: 'abc')
      expect(instance.age).to eq('abc')
    end

    it 'records a coercion error on the field' do
      instance = klass.new(age: 'abc')
      expect(instance.errors[:age]).to include(/coerce/)
    end

    it 'leaves the instance invalid' do
      instance = klass.new(age: 'abc')
      expect(instance).to be_invalid
    end

    it 'clears the coercion error once a good value is assigned' do
      instance = klass.new(age: 'abc')
      instance.age = '42'
      expect(instance.age).to eq(42)
      expect(instance.errors[:age]).to be_empty
    end
  end

  describe 'policy :replace' do
    let(:klass) do
      Class.new(described_class) do
        coercion_policy :replace
        optional :age, :integer
      end
    end

    it 'stores nil instead of the raw value' do
      instance = klass.new(age: 'abc')
      expect(instance.age).to be_nil
    end

    it 'still records a coercion error' do
      instance = klass.new(age: 'abc')
      expect(instance.errors[:age]).to include(/coerce/)
    end
  end

  describe 'policy :raise' do
    let(:klass) do
      Class.new(described_class) do
        coercion_policy :raise
        optional :age, :integer
      end
    end

    it 'raises FieldStruct::CoercionError on bad input' do
      expect { klass.new(age: 'abc') }
        .to raise_error(FieldStruct::CoercionError, /age/)
    end

    it 'wraps the original error with the field context' do
      klass.new(age: 'abc')
    rescue FieldStruct::CoercionError => e
      expect(e.field_name).to eq(:age)
      expect(e.original).to be_a(ArgumentError)
    end
  end

  describe 'policy and required-presence interaction' do
    let(:klass) do
      Class.new(described_class) do
        coercion_policy :replace
        required :age, :integer
      end
    end

    it 'records only the coercion error, not also "is required"' do
      instance = klass.new(age: 'abc')
      expect(instance.errors[:age].size).to eq(1)
      expect(instance.errors[:age].first).to match(/coerce/)
    end
  end

  describe 'array fields under each policy' do
    let(:klass) do
      Class.new(described_class) do
        coercion_policy :keep_raw
        optional :ages, :array, of: :integer
      end
    end

    it 'under :keep_raw, keeps the raw array and records a coercion error' do
      instance = klass.new(ages: [1, 'bad', 3])
      expect(instance.ages).to eq([1, 'bad', 3])
      expect(instance.errors[:ages]).to include(/coerce/)
    end

    it 'under :replace, stores nil' do
      replace_klass = Class.new(described_class) do
        coercion_policy :replace
        optional :ages, :array, of: :integer
      end
      instance = replace_klass.new(ages: [1, 'bad', 3])
      expect(instance.ages).to be_nil
      expect(instance.errors[:ages]).to include(/coerce/)
    end

    it 'under :raise, raises CoercionError' do
      raise_klass = Class.new(described_class) do
        coercion_policy :raise
        optional :ages, :array, of: :integer
      end
      expect { raise_klass.new(ages: [1, 'bad', 3]) }
        .to raise_error(FieldStruct::CoercionError, /ages/)
    end
  end
end
