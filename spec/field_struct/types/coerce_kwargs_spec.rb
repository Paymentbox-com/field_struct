# frozen_string_literal: true

# Each Type's #coerce now declares its consumed options as named
# kwargs (with a trailing ** catch-all so the DSL can splat
# field.options through every type uniformly). This spec exercises
# the kwarg signatures directly — both the happy path and the
# "unknown kwarg gets dropped silently by the catch-all" expectation.

RSpec.describe 'Type#coerce — typed kwarg signatures' do
  describe ':float' do
    let(:type) { FieldStruct::Types::Float.new }

    it 'accepts round: as a named kwarg' do
      expect(type.coerce(3.14159, round: 2)).to eq(3.14)
    end

    it 'ignores unrelated kwargs via the ** catch-all' do
      expect(type.coerce(3.14, format: '%Y', enum: [], something: :else)).to eq(3.14)
    end

    it 'works with no kwargs at all' do
      expect(type.coerce(3.14)).to eq(3.14)
    end
  end

  describe ':big_decimal' do
    let(:type) { FieldStruct::Types::BigDecimal.new }

    it 'accepts round: as a named kwarg' do
      expect(type.coerce('3.14159', round: 3)).to eq(BigDecimal('3.142'))
    end
  end

  describe ':boolean' do
    let(:type) { FieldStruct::Types::Boolean.new }

    it 'accepts values: as a named kwarg' do
      result = type.coerce('on', values: {truthy: %w[on], falsy: %w[off]})
      expect(result).to be true
    end

    it 'falls back to default vocabulary when values: is absent' do
      expect(type.coerce('true')).to be true
    end
  end

  describe ':date / :datetime / :time' do
    it ':date accepts format: as a named kwarg (strptime)' do
      type = FieldStruct::Types::Date.new
      expect(type.coerce('01/15/2024', format: '%m/%d/%Y')).to eq(Date.new(2024, 1, 15))
    end

    it ':datetime accepts format: as a named kwarg' do
      type = FieldStruct::Types::DateTime.new
      expect(type.coerce('2024-01-15 12:00:00', format: '%Y-%m-%d %H:%M:%S')).to be_a(DateTime)
    end

    it ':time accepts format: as a named kwarg' do
      type = FieldStruct::Types::Time.new
      expect(type.coerce('2024-01-15 12:00:00', format: '%Y-%m-%d %H:%M:%S')).to be_a(Time)
    end
  end

  describe ':array' do
    let(:type) { FieldStruct::Types::Array.new }

    it 'accepts of_type: as a named kwarg' do
      result = type.coerce([1, '2', :three], of_type: FieldStruct::Types::String)
      expect(result).to eq(%w[1 2 three])
    end

    it 'raises ArgumentError when of_type: is missing' do
      expect { type.coerce([1, 2]) }.to raise_error(ArgumentError, /of_type:/)
    end
  end

  describe 'unknown-kwarg handling — the ** catch-all' do
    it ':string silently ignores anything beyond value' do
      expect(FieldStruct::Types::String.new.coerce('hi', round: 2, format: /x/)).to eq('hi')
    end

    it ':integer silently ignores anything beyond value' do
      expect(FieldStruct::Types::Integer.new.coerce('42', round: 99)).to eq(42)
    end
  end

  describe 'positional Hash no longer flows as options' do
    # In Ruby 3, def coerce(value, **) means the second positional slot
    # doesn't exist. A bare Hash literal as the second arg is the value
    # itself (for types whose value is a Hash, e.g. Nested), not an
    # options bag.
    it 'Nested.coerce takes a Hash AS the value, not as options' do
      addr = Class.new(FieldStruct::Base) { required :street, :string }
      type = FieldStruct::Types::Nested.new(addr)
      expect(type.coerce({street: '1 Main'})).to be_a(addr)
    end
  end
end
