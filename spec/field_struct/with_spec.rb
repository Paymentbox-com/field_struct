# frozen_string_literal: true

# with(**changes): a new instance with the given attributes changed, the
# receiver untouched — Data#with for FieldStructs. Changed fields go through
# the normal setter pipeline; unchanged ones are carried over as they are,
# errors included (the same shallow copy dup makes).
RSpec.describe FieldStruct::Base, '#with' do
  let(:address_class) do
    Class.new(described_class) do
      optional :city, :string
    end
  end

  let(:klass) do
    address = address_class
    Class.new(described_class) do
      required :name, :string
      optional :age, :integer
      optional :address, address
      optional :tags, :array, of: :string
    end
  end

  let(:original) { klass.new(name: 'Ann', age: 30, address: {city: 'Provo'}, tags: %w[a]) }

  it 'returns a new instance with the change, leaving the receiver untouched' do
    changed = original.with(age: 31)

    expect(changed).not_to equal(original)
    expect(changed.age).to eq(31)
    expect(changed.name).to eq('Ann')
    expect(original.age).to eq(30)
  end

  it 'returns an equal copy (not self) when given no changes' do
    copy = original.with

    expect(copy).not_to equal(original)
    expect(copy).to eq(original)
  end

  it 'accepts String keys' do
    expect(original.with('age' => 40).age).to eq(40)
  end

  describe 'the setter pipeline' do
    it 'coerces changed values' do
      expect(original.with(age: '42').age).to eq(42)
    end

    it 'refreshes the changed field’s errors' do
      broken = original.with(name: '')
      expect(broken.errors[:name]).to eq(['is required'])
      expect(original).to be_valid

      expect(broken.with(name: 'Bo')).to be_valid
    end

    it 'follows the field’s coercion_policy' do
      expect(original.with(age: 'abc').age).to eq('abc')
      replace = Class.new(described_class) do
        coercion_policy :replace
        optional :age, :integer
      end
      expect(replace.new(age: 1).with(age: 'abc').age).to be_nil
    end

    it 'raises under coercion_policy :raise and leaves the receiver as it was' do
      strict = Class.new(described_class) do
        coercion_policy :raise
        optional :age, :integer
      end
      record = strict.new(age: 1)
      expect { record.with(age: 'abc') }.to raise_error(FieldStruct::CoercionError)
      expect(record.age).to eq(1)
    end

    it 'keeps an unchanged field’s errors' do
      invalid = klass.new(name: '', age: 1)
      expect(invalid.with(age: 2).errors[:name]).to eq(['is required'])
    end

    it 'reruns cross-field validators' do
      ranged = Class.new(described_class) do
        optional :low, :integer
        optional :high, :integer
        validate { |r| r.errors.add(:base, 'low must not exceed high') if r.low && r.high && r.low > r.high }
      end
      record = ranged.new(low: 1, high: 5)
      expect(record.with(low: 9).errors[:base]).to eq(['low must not exceed high'])
      expect(record).to be_valid
    end

    it 'does not re-run callable defaults' do
      calls = 0
      counted = Class.new(described_class) do
        optional :id, :integer, default: -> { calls += 1 }
        optional :note, :string
      end
      record = counted.new
      expect { record.with(note: 'x') }.not_to(change { calls })
      expect(record.with(note: 'x').id).to eq(record.id)
    end
  end

  describe 'unknown keys' do
    it 'are dropped under unknown_attributes :ignore (the default)' do
      expect(original.with(nope: 1)).to eq(original)
    end

    it 'raise under unknown_attributes :raise, naming the keys' do
      strict = Class.new(klass) { unknown_attributes :raise }
      record = strict.new(name: 'Ann')
      expect { record.with(nope: 1) }.to raise_error(FieldStruct::UnknownAttributeError, /:nope/)
    end
  end

  describe 'copy depth (shallow, like dup)' do
    it 'shares unchanged nested structs and arrays with the receiver' do
      changed = original.with(age: 31)
      expect(changed.address).to equal(original.address)
      expect(changed.tags).to equal(original.tags)
    end

    it 'gives the copy its own errors' do
      changed = original.with(age: 31)
      changed.name = ''
      expect(original).to be_valid
    end
  end

  describe 'immutable and frozen receivers' do
    it 'works on an immutable! instance, and the copy stays immutable' do
      immutable = Class.new(described_class) do
        immutable!
        optional :age, :integer
      end
      changed = immutable.new(age: 1).with(age: 2)
      expect(changed.age).to eq(2)
      expect { changed.age = 3 }.to raise_error(FieldStruct::ImmutableError)
    end

    it 'works on a frozen! instance and returns a frozen copy' do
      frozen = Class.new(described_class) do
        frozen!
        optional :age, :integer
      end
      record = frozen.new(age: 1)
      changed = record.with(age: 2)
      expect(changed.age).to eq(2)
      expect(changed).to be_frozen
      expect(record.age).to eq(1)
    end

    it 'returns a frozen copy of a manually frozen instance, and a mutable one otherwise' do
      expect(original.freeze.with(age: 2)).to be_frozen
      expect(klass.new(name: 'Ann').with(age: 2)).not_to be_frozen
    end
  end

  it 'returns an instance of the receiver’s class (subclass-safe)' do
    sub = Class.new(klass) { optional :extra, :string }
    changed = sub.new(name: 'Ann', extra: 'x').with(age: 3)
    expect(changed).to be_an_instance_of(sub)
    expect(changed.extra).to eq('x')
  end

  it 'refuses positional arguments, pointing at keywords' do
    expect { original.with({age: 1}) }.to raise_error(ArgumentError, /with takes keyword arguments only.*with\(\*\*hash\)/)
  end

  it 'reserves the name: field :with is refused at declaration' do
    expect { Class.new(described_class) { optional :with, :string } }
      .to raise_error(ArgumentError, /\Afield :with is reserved/)
  end
end
